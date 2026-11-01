"""Downloads pinned tools, checks their hashes and unpacks them into <workspace>/tools/ (docs/workspace.md#tools).

A download goes to <workspace>/cache/downloads/ first and is hashed while it streams; a file whose hash does not
match the manifest is deleted and never unpacked. An installed tool carries a `.gds-installed` stamp naming the hash
it came from, so running init again skips it, and a changed pin reinstalls it.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import stat
import subprocess
import tarfile
import tempfile
import urllib.request
import zipfile
from collections.abc import Callable
from pathlib import Path, PurePosixPath

from gds_tools.manifest import Download, ManifestError, Tool

USER_AGENT = "gdstudio-bootstrap/0.1 (+https://github.com/Ryubara/gdstudio)"
STAMP = ".gds-installed"
#: Godot's self-contained mode marker: settings and templates stay in editor_data/ beside the program.
SELF_CONTAINED = "_sc_"

Log = Callable[[str], None]


class FetchError(Exception):
    """A download failed, its hash did not match, or the archive could not be unpacked safely."""


def file_digest(path: Path, algorithm: str) -> str:
    """The hex digest of a file."""
    hasher = hashlib.new(algorithm)
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def _stream(url: str, target: Path, algorithm: str, log: Log) -> str:
    """Download `url` to `target`, returning its digest."""
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    hasher = hashlib.new(algorithm)
    with urllib.request.urlopen(request, timeout=60) as response, target.open("wb") as out:
        total = int(response.headers.get("Content-Length") or 0)
        done = 0
        next_report = 0.0
        for chunk in iter(lambda: response.read(1 << 20), b""):
            out.write(chunk)
            hasher.update(chunk)
            done += len(chunk)
            if total and done / total >= next_report:
                log(f"  {done >> 20} / {total >> 20} MB")
                next_report += 0.25
    return hasher.hexdigest()


def download(item: Download, cache: Path, log: Log) -> Path:
    """The verified file for `item` in `cache`, downloaded unless a verified copy is already there."""
    cache.mkdir(parents=True, exist_ok=True)
    final = cache / item.filename
    if final.exists():
        if file_digest(final, item.algorithm) == item.digest:
            log(f"  cached: {final.name}")
            return final
        final.unlink()
    part = final.with_suffix(final.suffix + ".part")
    errors: list[str] = []
    for url in (item.url, *item.mirrors):
        log(f"  downloading {url}")
        try:
            digest = _stream(url, part, item.algorithm, log)
        except OSError as error:  # urllib's errors are OSErrors
            errors.append(f"{url}: {error}")
            part.unlink(missing_ok=True)
            continue
        if digest != item.digest:
            part.unlink(missing_ok=True)
            errors.append(f"{url}: {item.algorithm} mismatch (got {digest[:16]}..., want {item.digest[:16]}...)")
            continue
        part.replace(final)
        return final
    raise FetchError("could not fetch a verified copy:\n    " + "\n    ".join(errors))


def _safe_member(name: str) -> PurePosixPath:
    """An archive member's path, refused when it is absolute or climbs out of the target."""
    path = PurePosixPath(name.replace("\\", "/"))
    if path.is_absolute() or ".." in path.parts:
        raise FetchError(f"unsafe path in archive: {name}")
    return path


def _make_executable(path: Path) -> None:
    """Add the execute bits (zip archives drop them on Linux and macOS)."""
    if os.name != "nt" and path.exists():
        path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def _unzip(archive: Path, target: Path, strip: str | None = None) -> None:
    """Extract a zip into `target`, optionally dropping a leading folder `strip`, keeping Unix modes."""
    with zipfile.ZipFile(archive) as zf:
        for info in zf.infolist():
            member = _safe_member(info.filename)
            if strip:
                if not member.parts or member.parts[0] != strip:
                    continue
                member = PurePosixPath(*member.parts[1:])
                if not member.parts:
                    continue
            dest = target.joinpath(*member.parts)
            if info.is_dir():
                dest.mkdir(parents=True, exist_ok=True)
                continue
            dest.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(info) as src, dest.open("wb") as out:
                shutil.copyfileobj(src, out)
            mode = info.external_attr >> 16
            if os.name != "nt" and mode & 0o111:
                dest.chmod(mode & 0o777)


def _untar(archive: Path, target: Path) -> None:
    """Extract a tar archive with the standard library's safe 'data' filter."""
    with tarfile.open(archive) as tf:
        tf.extractall(target, filter="data")


def _from_dmg(archive: Path, target: Path, app: str) -> None:
    """Copy `app` out of a macOS disk image."""
    with tempfile.TemporaryDirectory() as mount:
        subprocess.run(["hdiutil", "attach", "-nobrowse", "-readonly", "-mountpoint", mount, str(archive)], check=True)
        try:
            shutil.copytree(Path(mount) / app, target / app, symlinks=True)
        finally:
            subprocess.run(["hdiutil", "detach", mount], check=False)


def install_dir(tools_root: Path, tool: Tool) -> Path:
    """Where `tool` is installed."""
    return tools_root / tool.folder


def is_installed(tools_root: Path, tool: Tool, item: Download) -> bool:
    """True when the tool's stamp names this exact download."""
    stamp = install_dir(tools_root, tool) / STAMP
    return stamp.exists() and stamp.read_text(encoding="utf-8").strip() == f"{item.algorithm}:{item.digest}"


def install(tool: Tool, item: Download, archive: Path, tools_root: Path, all_tools: dict[str, Tool]) -> Path:
    """Unpack a verified archive for `tool` and stamp it; returns the install folder."""
    if tool.kind == "godot-templates":
        return _install_templates(tool, item, archive, tools_root, all_tools)
    target = install_dir(tools_root, tool)
    staging = target.with_name(target.name + ".staging")
    shutil.rmtree(staging, ignore_errors=True)
    staging.mkdir(parents=True)
    name = archive.name
    if name.endswith(".zip"):
        _unzip(archive, staging)
    elif name.endswith((".tar.xz", ".tar.gz", ".tgz")):
        _untar(archive, staging)
    elif name.endswith(".dmg"):
        if not item.exe:
            raise FetchError(f"{tool.name}: a .dmg entry needs exe to name the app")
        _from_dmg(archive, staging, item.exe.split("/", 1)[0])
    else:
        raise FetchError(f"{tool.name}: unknown archive type {name}")
    if item.exe:
        exe = staging / item.exe
        if not exe.exists():
            raise FetchError(f"{tool.name}: {item.exe} not found in {name}")
        _make_executable(exe)
        if tool.kind == "godot":
            (exe.parent / SELF_CONTAINED).write_text("", encoding="utf-8")
    (staging / STAMP).write_text(f"{item.algorithm}:{item.digest}\n", encoding="utf-8")
    shutil.rmtree(target, ignore_errors=True)
    staging.replace(target)
    return target


def _install_templates(tool: Tool, item: Download, archive: Path, tools_root: Path, all_tools: dict[str, Tool]) -> Path:
    """Unpack Godot export templates into the pinned Godot's self-contained editor_data/."""
    if not tool.requires:
        raise ManifestError(f"{tool.name} must name the Godot it belongs to with `requires`")
    godot = all_tools[tool.requires]
    godot_dir = install_dir(tools_root, godot)
    exe_rel = next((d.exe for d in godot.platforms.values() if d.exe and (godot_dir / d.exe).exists()), None)
    if exe_rel is None:
        raise FetchError(f"{tool.name}: install {godot.name} first")
    target = (godot_dir / exe_rel).parent / "editor_data" / "export_templates" / f"{tool.version}.stable"
    shutil.rmtree(target, ignore_errors=True)
    target.mkdir(parents=True)
    _unzip(archive, target, strip="templates")
    marker = install_dir(tools_root, tool)
    marker.mkdir(parents=True, exist_ok=True)
    (marker / STAMP).write_text(f"{item.algorithm}:{item.digest}\n", encoding="utf-8")
    (marker / "LOCATION.txt").write_text(f"{target}\n", encoding="utf-8")
    return target

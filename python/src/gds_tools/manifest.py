"""Reads the kit's manifests: `tools.toml` (pinned tools) and `workspace.toml` (folders and repositories).

Both live at the root of the gdstudio checkout. Everything here is pure data handling, so it is tested without the
network or a real workspace.
"""

from __future__ import annotations

import platform
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

#: Hash algorithms a platform entry may carry, strongest first; the first one present is checked.
HASH_KEYS: tuple[str, ...] = ("sha512", "sha256")


class ManifestError(Exception):
    """A manifest is missing, unreadable or names something it does not define."""


@dataclass(frozen=True)
class Download:
    """One file to fetch for one platform, with the hash it must have."""

    url: str
    algorithm: str
    digest: str
    mirrors: tuple[str, ...] = ()
    exe: str | None = None

    @property
    def filename(self) -> str:
        """The file's name in the download cache, taken from the URL."""
        return self.url.rsplit("/", 1)[-1]


@dataclass(frozen=True)
class Tool:
    """A pinned tool of tools.toml."""

    name: str
    version: str
    kind: str
    default: bool
    requires: str | None
    platforms: dict[str, Download] = field(default_factory=dict)
    #: Keys a kind uses beyond the common ones (a Godot addon's `addon` folder and `source` path in its archive).
    extra: dict = field(default_factory=dict)

    @property
    def folder(self) -> str:
        """Its folder under <workspace>/tools/."""
        return f"{self.name}-{self.version}"

    def download_for(self, platform_key: str) -> Download:
        """The download for `platform_key`, or the platform-neutral one; ManifestError when neither exists."""
        found = self.platforms.get(platform_key) or self.platforms.get("any")
        if found is None:
            raise ManifestError(f"{self.name} {self.version} has no build for {platform_key}")
        return found


@dataclass(frozen=True)
class RepoEntry:
    """A repository of workspace.toml, cloned to <workspace>/repos/<name>/."""

    name: str
    url: str
    role: str


@dataclass(frozen=True)
class WorkspaceSpec:
    """The workspace's folders and repositories."""

    folders: tuple[str, ...]
    repos: dict[str, RepoEntry]


def platform_key(system: str | None = None, machine: str | None = None) -> str:
    """This machine as a tools.toml platform key, such as `windows-x64` or `macos-arm64`."""
    system = (system or platform.system()).lower()
    machine = (machine or platform.machine()).lower()
    os_name = {"windows": "windows", "linux": "linux", "darwin": "macos"}.get(system)
    if os_name is None:
        raise ManifestError(f"unsupported operating system: {system}")
    if machine in ("amd64", "x86_64", "x64"):
        arch = "x64"
    elif machine in ("arm64", "aarch64"):
        arch = "arm64"
    else:
        raise ManifestError(f"unsupported processor: {machine}")
    return f"{os_name}-{arch}"


def _read(path: Path) -> dict:
    """A TOML file as a dict; ManifestError when it is missing or malformed."""
    try:
        return tomllib.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ManifestError(f"missing manifest: {path}") from error
    except tomllib.TOMLDecodeError as error:
        raise ManifestError(f"{path}: {error}") from error


def _download(name: str, key: str, entry: dict) -> Download:
    """One platform entry of a tool, checked to carry a URL and a hash."""
    algorithm = next((a for a in HASH_KEYS if a in entry), None)
    if "url" not in entry or algorithm is None:
        raise ManifestError(f"tools.{name}.platforms.{key} needs a url and one of {', '.join(HASH_KEYS)}")
    return Download(
        url=entry["url"],
        algorithm=algorithm,
        digest=entry[algorithm].lower(),
        mirrors=tuple(entry.get("mirrors", ())),
        exe=entry.get("exe"),
    )


def load_tools(path: Path) -> dict[str, Tool]:
    """Every tool of a tools.toml, by name."""
    tools: dict[str, Tool] = {}
    for name, body in _read(path).get("tools", {}).items():
        if "version" not in body or "kind" not in body:
            raise ManifestError(f"tools.{name} needs a version and a kind")
        platforms = {key: _download(name, key, entry) for key, entry in body.get("platforms", {}).items()}
        tools[name] = Tool(
            name=name,
            version=str(body["version"]),
            kind=body["kind"],
            default=bool(body.get("default", False)),
            requires=body.get("requires"),
            platforms=platforms,
            extra={k: v for k, v in body.items() if k in ("addon", "source")},
        )
    for tool in tools.values():
        if tool.requires and tool.requires not in tools:
            raise ManifestError(f"tools.{tool.name} requires unknown tool {tool.requires}")
    return tools


def load_workspace(path: Path) -> WorkspaceSpec:
    """The folders and repositories of a workspace.toml."""
    data = _read(path)
    folders = tuple(data.get("folders", ()))
    if "repos" not in folders:
        raise ManifestError(f"{path}: folders must include 'repos'")
    repos = {
        name: RepoEntry(name=name, url=body["url"], role=body.get("role", "game"))
        for name, body in data.get("repos", {}).items()
    }
    return WorkspaceSpec(folders=folders, repos=repos)


def resolve_fetch(tools: dict[str, Tool], requested: list[str] | None) -> list[Tool]:
    """The tools to fetch, dependencies first.

    `requested` None means the default ones; `["all"]` every tool; `["none"]` nothing; otherwise those names.
    """
    if requested is None:
        names = [t.name for t in tools.values() if t.default]
    elif requested == ["none"]:
        return []
    elif "all" in requested:
        names = list(tools)
    else:
        unknown = [n for n in requested if n not in tools]
        if unknown:
            raise ManifestError(f"unknown tool(s): {', '.join(unknown)}; known: {', '.join(tools)}")
        names = list(requested)
    ordered: list[Tool] = []

    def add(name: str) -> None:
        tool = tools[name]
        if tool.requires:
            add(tool.requires)
        if tool not in ordered:
            ordered.append(tool)

    for name in names:
        add(name)
    return ordered


def load_mcp(path: Path) -> dict[str, list[str]]:
    """The MCP servers of tools.toml's [mcp] table: name -> command words (`{tool:<name>}` not yet resolved)."""
    servers = {}
    for name, body in _read(path).get("mcp", {}).items():
        command = body.get("command")
        if not isinstance(command, list) or not command or not all(isinstance(w, str) for w in command):
            raise ManifestError(f"mcp.{name}.command must be a non-empty list of strings")
        servers[name] = command
    return servers

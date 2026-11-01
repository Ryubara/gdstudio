"""Fetching: hash checks, cached copies, safe unpacking and install stamps, all without the network."""

import hashlib
import zipfile

import pytest

from gds_tools import fetch
from gds_tools.manifest import Download, Tool


def _zip(path, files):
    with zipfile.ZipFile(path, "w") as zf:
        for name, data in files.items():
            zf.writestr(name, data)
    return path


def _sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_cached_verified_copy_is_reused_without_network(tmp_path, monkeypatch):
    cache = tmp_path / "cache"
    cache.mkdir()
    archive = _zip(cache / "t.zip", {"a.txt": "x"})
    item = Download(url="https://example.invalid/t.zip", algorithm="sha256", digest=_sha(archive))
    monkeypatch.setattr(fetch, "_stream", lambda *a: pytest.fail("must not download"))
    assert fetch.download(item, cache, lambda _: None) == archive


def test_hash_mismatch_tries_mirror_then_fails(tmp_path, monkeypatch):
    calls = []

    def fake_stream(url, target, algorithm, log):
        calls.append(url)
        target.write_bytes(b"wrong")
        return "0" * 64

    monkeypatch.setattr(fetch, "_stream", fake_stream)
    item = Download(url="https://a/t.zip", algorithm="sha256", digest="f" * 64, mirrors=("https://b/t.zip",))
    with pytest.raises(fetch.FetchError, match="mismatch"):
        fetch.download(item, tmp_path, lambda _: None)
    assert calls == ["https://a/t.zip", "https://b/t.zip"]
    assert not list(tmp_path.iterdir())  # nothing unverified is left behind


def test_zip_slip_is_refused(tmp_path):
    archive = _zip(tmp_path / "evil.zip", {"../outside.txt": "x"})
    with pytest.raises(fetch.FetchError, match="unsafe"):
        fetch._unzip(archive, tmp_path / "out")


def test_godot_install_marks_self_contained_and_stamps(tmp_path):
    archive = _zip(tmp_path / "godot.zip", {"Godot.exe": "bin"})
    item = Download(url="https://e/godot.zip", algorithm="sha256", digest=_sha(archive), exe="Godot.exe")
    tool = Tool("godot", "9.9", "godot", True, None, {"any": item})
    root = tmp_path / "tools"
    target = fetch.install(tool, item, archive, root, {"godot": tool})
    assert (target / "Godot.exe").exists() and (target / fetch.SELF_CONTAINED).exists()
    assert fetch.is_installed(root, tool, item)
    changed = Download(url=item.url, algorithm="sha256", digest="e" * 64, exe="Godot.exe")
    assert not fetch.is_installed(root, tool, changed)


def test_templates_install_into_godot_editor_data(tmp_path):
    root = tmp_path / "tools"
    g_zip = _zip(tmp_path / "g.zip", {"bin/Godot.exe": "bin"})
    g_item = Download(url="https://e/g.zip", algorithm="sha256", digest=_sha(g_zip), exe="bin/Godot.exe")
    godot = Tool("godot", "9.9", "godot", True, None, {"any": g_item})
    t_zip = _zip(tmp_path / "t.tpz", {"templates/version.txt": "9.9.stable", "templates/web_release.zip": "w"})
    t_item = Download(url="https://e/t.tpz", algorithm="sha256", digest=_sha(t_zip))
    templates = Tool("godot-templates", "9.9", "godot-templates", False, "godot", {"any": t_item})
    tools = {"godot": godot, "godot-templates": templates}
    fetch.install(godot, g_item, g_zip, root, tools)
    target = fetch.install(templates, t_item, t_zip, root, tools)
    assert target == root / "godot-9.9" / "bin" / "editor_data" / "export_templates" / "9.9.stable"
    assert (target / "web_release.zip").exists()
    assert fetch.is_installed(root, templates, t_item)

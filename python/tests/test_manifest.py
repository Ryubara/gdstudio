"""The manifests: the kit's own files parse, and resolution, platforms and errors behave."""

from pathlib import Path

import pytest

from gds_tools.manifest import ManifestError, load_tools, load_workspace, platform_key, resolve_fetch

KIT = Path(__file__).resolve().parents[2]


def test_kit_manifests_parse_and_cover_main_platforms():
    tools = load_tools(KIT / "tools.toml")
    assert {"godot", "blender", "godot-templates"} <= set(tools)
    for key in ("windows-x64", "linux-x64", "macos-arm64"):
        assert tools["godot"].download_for(key).exe
        assert tools["blender"].download_for(key).exe
    assert tools["godot-templates"].download_for("linux-x64").algorithm == "sha512"
    spec = load_workspace(KIT / "workspace.toml")
    assert "gdstudio" in spec.repos and "vault" in spec.folders


@pytest.mark.parametrize(
    ("system", "machine", "key"),
    [("Windows", "AMD64", "windows-x64"), ("Linux", "aarch64", "linux-arm64"), ("Darwin", "arm64", "macos-arm64")],
)
def test_platform_key(system, machine, key):
    assert platform_key(system, machine) == key


def test_platform_key_rejects_unknown():
    with pytest.raises(ManifestError):
        platform_key("Plan9", "x86_64")


def test_resolve_defaults_all_none_and_dependencies():
    tools = load_tools(KIT / "tools.toml")
    assert [t.name for t in resolve_fetch(tools, None)] == [
        "godot",
        "blender",
        "ffmpeg",
        "godot-mcp-addon",
        "blender-mcp-addon",
        "blender-mcp-server",
    ]
    assert resolve_fetch(tools, ["none"]) == []
    assert [t.name for t in resolve_fetch(tools, ["godot-templates"])] == ["godot", "godot-templates"]
    with pytest.raises(ManifestError):
        resolve_fetch(tools, ["photoshop"])


def test_entry_without_hash_is_refused(tmp_path):
    bad = tmp_path / "tools.toml"
    bad.write_text('[tools.x]\nversion="1"\nkind="godot"\n[tools.x.platforms.any]\nurl="https://e/x.zip"\n')
    with pytest.raises(ManifestError, match="needs a url"):
        load_tools(bad)

"""The game server images of the templates download the Godot that tools.toml pins, with its hash."""

import re
from pathlib import Path

import pytest

from gds_tools.manifest import load_tools

KIT = Path(__file__).resolve().parents[2]
DOCKERFILES = sorted((KIT / "templates").glob("*/server/Dockerfile"))


def _args(dockerfile: Path) -> dict[str, str]:
    return dict(re.findall(r"^ARG (\w+)=(\S+)$", dockerfile.read_text(encoding="utf-8"), re.MULTILINE))


def test_a_template_has_a_server_image():
    assert KIT / "templates" / "3d-third-person" / "server" / "Dockerfile" in DOCKERFILES


@pytest.mark.parametrize("dockerfile", DOCKERFILES, ids=lambda path: path.parts[-3])
def test_the_image_downloads_the_pinned_godot(dockerfile):
    godot = load_tools(KIT / "tools.toml")["godot"]
    linux = godot.download_for("linux-x64")
    args = _args(dockerfile)
    assert args["GODOT_VERSION"] == godot.version
    assert linux.algorithm == "sha512"
    assert args["GODOT_SHA512"] == linux.digest
    # The URL the image builds from the version is the one the kit pins.
    text = dockerfile.read_text(encoding="utf-8")
    built = re.search(r'"(https://github\.com/godotengine/godot/releases/download/[^"]+)"', text).group(1)
    assert built.replace("${GODOT_VERSION}", godot.version) == linux.url


@pytest.mark.parametrize("dockerfile", DOCKERFILES, ids=lambda path: path.parts[-3])
def test_the_server_runs_as_a_user_under_tini(dockerfile):
    text = dockerfile.read_text(encoding="utf-8")
    assert re.search(r"^USER game$", text, re.MULTILINE)
    assert 'ENTRYPOINT ["/usr/bin/tini", "--"]' in text
    assert re.search(r'^CMD \["godot", "--headless", "--path", "/app", "--", "--server"\]$', text, re.MULTILINE)

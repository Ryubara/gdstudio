r"""The page script of `ShaderPrelink` (`godot/addons/gds_game/shader_prelink/shader_prelink.gd`, kit issue #1183)
is JavaScript the browser runs from a GDScript string: once GDScript's escapes are read, it must parse. A `\\n` written
as `\n` there ends a JavaScript string at a line break, and the page then starts nothing, with no error in Godot."""

import re
import shutil
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[2] / "godot" / "addons" / "gds_game" / "shader_prelink" / "shader_prelink.gd"
ESCAPES = {"n": "\n", "t": "\t", "\\": "\\", '"': '"', "'": "'"}


def page_script() -> str:
    """The `PAGE_SCRIPT` constant as GDScript reads it (its escapes turned into characters)."""
    text = SCRIPT.read_text(encoding="utf-8")
    found = re.search(r'const PAGE_SCRIPT := """\n(.*?)"""\n', text, re.DOTALL)
    assert found, "no PAGE_SCRIPT constant"
    return re.sub(r"\\(.)", lambda m: ESCAPES.get(m.group(1), m.group(0)), found.group(1))


def test_the_page_script_keeps_its_line_join_on_one_line() -> None:
    assert r"join('\n')" in page_script()


@pytest.mark.skipif(shutil.which("node") is None, reason="needs Node.js to parse the script")
def test_the_page_script_parses_as_javascript(tmp_path: Path) -> None:
    path = tmp_path / "page.js"
    path.write_text(page_script(), encoding="utf-8")
    result = subprocess.run(["node", "--check", str(path)], capture_output=True, text=True, check=False)
    assert result.returncode == 0, result.stderr

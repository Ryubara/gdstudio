"""3D Third Person's limb overlap reports name the measure that made them (`assets/animation/measure_hash.py`, kit
issue #1479): the hash of `limb_overlap.py`'s code ignores comments, docstrings and layout and nothing else, and
every committed report was made by the script and the bodies in the template now."""

import ast
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

import pytest

GAME = Path(__file__).resolve().parents[2] / "templates" / "3d-third-person" / "game"
ANIMATION = GAME / "assets" / "animation"
BODIES = [GAME / "assets" / "characters" / folder for folder in ("prototype", "mannequin")]
REPORTS = sorted(ANIMATION.glob("*/*_overlap.json"))


def _load():
    # No `__pycache__` in the template: a made game's layout check refuses the folder (test_layout.py).
    was, sys.dont_write_bytecode = sys.dont_write_bytecode, True
    try:
        spec = importlib.util.spec_from_file_location("measure_hash", ANIMATION / "measure_hash.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    finally:
        sys.dont_write_bytecode = was
    return module


tool = _load()
SOURCE = (ANIMATION / "limb_overlap.py").read_text(encoding="utf-8")


def _program(text):
    """A source's syntax tree without its docstrings."""
    tree = ast.parse(text)
    for node in ast.walk(tree):
        body = getattr(node, "body", None)
        if isinstance(body, list) and body and isinstance(body[0], ast.Expr):
            value = body[0].value
            if isinstance(value, ast.Constant) and isinstance(value.value, str):
                node.body = body[1:] or [ast.Pass()]
    return ast.dump(tree)


def test_the_cases_have_the_hashes_godot_is_held_to():
    for name, (text, expected) in tool.CASES.items():
        assert tool.text_sha256(text) == expected, name


def test_the_normal_form_is_still_the_measure_s_program():
    assert _program(tool.normal_form(SOURCE)) == _program(SOURCE)


def test_a_comment_a_docstring_or_a_wrapped_call_keeps_the_hash():
    changed = SOURCE.replace("LIMIT_MM = 5.0", "LIMIT_MM = 5.0  # millimetres\n\n# and a note")
    changed = changed.replace('"""Measure limbs passing', '"""Reworded. Measure limbs passing')
    changed = changed.replace("parser.add_argument(", "parser.add_argument(\n        ")
    assert changed != SOURCE
    assert tool.text_sha256(changed) == tool.text_sha256(SOURCE)


@pytest.mark.parametrize(
    ("was", "now"),
    [
        ("LIMIT_MM = 5.0", "LIMIT_MM = 6.0"),
        ("RATES = (24, 25, 30,", "RATES = (25, 30,"),
        ('            report["frames"].append(worst)', '        report["frames"].append(worst)'),
        ('"lowerarm_l": "lowerarm_l"', '"lowerarm_l": "upperarm_l"'),
    ],
)
def test_a_change_to_the_code_changes_the_hash(was, now):
    assert was in SOURCE
    assert tool.text_sha256(SOURCE.replace(was, now)) != tool.text_sha256(SOURCE)


def test_there_are_reports():
    assert len(REPORTS) >= 6, [path.name for path in REPORTS]


@pytest.mark.parametrize("report", REPORTS, ids=lambda path: f"{path.parent.name}/{path.name}")
def test_a_report_was_made_by_the_script_and_the_bodies_here(report):
    data = json.loads(report.read_text(encoding="utf-8"))
    assert data.get("measure_sha256") == tool.script_sha256(), (
        f"{report.name} was not measured by this limb_overlap.py: measure it again"
    )
    measured = {body for on in data["clips"].values() for body in on}
    assert measured == set(data.get("bodies_sha256", {})), f"{report.name} does not name every body it measured"
    for body, digest in data["bodies_sha256"].items():
        path = next((folder / f"{body}.glb" for folder in BODIES if (folder / f"{body}.glb").exists()), None)
        assert path, f"{report.name} names {body}, which is no body of the template"
        content = path.read_bytes()
        if content.startswith(b"version https://git-lfs"):
            continue  # a checkout without the Git LFS files: the Godot suite holds the body's hash
        assert hashlib.sha256(content).hexdigest() == digest, (
            f"{body}.glb is not the body {report.name} measured: measure it again"
        )

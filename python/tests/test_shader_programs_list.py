"""3D Third Person's list of web GL programs (`tools/web_smoke/shader_programs.py`, kit issue #1164): the encoder
writes each shader once with runs of earlier lines, the decoder (the page's, in Python) gives back the same programs,
and the template's committed list decodes to programs with two stages each."""

import importlib.util
import json
import sys
from pathlib import Path

GAME = Path(__file__).resolve().parents[2] / "templates" / "3d-third-person" / "game"


def _load():
    # No `__pycache__` in the template: a made game's layout check refuses the folder (test_layout.py).
    was, sys.dont_write_bytecode = sys.dont_write_bytecode, True
    try:
        spec = importlib.util.spec_from_file_location(
            "shader_programs", GAME / "tools" / "web_smoke" / "shader_programs.py"
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    finally:
        sys.dont_write_bytecode = was
    return module


tool = _load()

HEAD = "#version 300 es\nprecision highp float;\n"
BODY = "\n".join(f"float f{i}() {{ return {i}.0; }}" for i in range(40))


def _program(defines: str, attributes: list | None = None, feedback: list | None = None) -> dict:
    vertex = HEAD + defines + BODY + "\nvoid main() { gl_Position = vec4(f1()); }"
    fragment = HEAD + defines + BODY + "\nout vec4 c;\nvoid main() { c = vec4(f2()); }"
    return {"stages": [[35633, vertex], [35632, fragment]], "attributes": attributes or [], "feedback": feedback}


def test_a_list_decodes_to_the_programs_it_was_made_from() -> None:
    programs = [
        _program("#define A\n"),
        _program("#define A\n#define B\n", [[0, "pos"]]),
        _program("#define C\n", feedback=[["out_a", "out_b"], 35980]),
    ]
    data = tool.encode(programs, "4.7.2-stable (official)")
    assert data["format"] == tool.FORMAT
    assert data["godot"] == "4.7.2-stable (official)"
    assert tool.decode(json.loads(json.dumps(data))) == programs


def test_shared_lines_are_written_once() -> None:
    programs = [_program(f"#define V{i}\n") for i in range(10)]
    size = len(json.dumps(tool.encode(programs, "x")))
    plain = sum(len(text) for p in programs for _, text in p["stages"])
    assert size < plain / 5


def test_a_program_seen_twice_is_kept_once() -> None:
    programs = [_program("#define A\n"), _program("#define B\n"), _program("#define A\n")]
    assert tool.unique(programs) == programs[:2]


def test_the_template_list_decodes() -> None:
    data = json.loads((GAME / "assets" / "shaders" / "web" / "shader_programs.json").read_text(encoding="utf-8"))
    programs = tool.decode(data)
    assert len(programs) >= 100
    assert all(len(p["stages"]) == 2 for p in programs)
    assert all(text.startswith("#version 300 es") or "void main" in text for p in programs for _, text in p["stages"])


def _run(missed: int, mismatch: str = "") -> dict:
    return {"missed": missed, "prelink": {"from": "page", "mismatch": mismatch}}


def test_a_run_that_lacks_more_than_the_limit_says_the_list_is_stale(capsys) -> None:
    assert tool.stale(_run(9), 8)
    assert "record it again" in capsys.readouterr().out
    assert not tool.stale(_run(8), 8)
    assert not tool.stale(_run(40), -1)


def test_a_page_that_made_the_context_with_other_attributes_fails(capsys) -> None:
    assert tool.stale(_run(0, "alpha"), 8)
    assert "alpha" in capsys.readouterr().out
    assert not tool.stale({"missed": 0, "prelink": None}, 8)

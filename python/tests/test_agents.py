"""The agent roster: every definition's frontmatter loads, or Claude Code silently drops the agent."""

import re
from pathlib import Path

import pytest

AGENTS = Path(__file__).resolve().parents[2] / ".claude" / "agents"
KEY = re.compile(r"^[a-z][a-z_-]*: \S")


@pytest.mark.parametrize("path", sorted(AGENTS.glob("*.md")), ids=lambda p: p.stem)
def test_frontmatter_is_one_key_per_line(path):
    lines = path.read_text(encoding="utf-8").splitlines()
    assert lines[0] == "---", "frontmatter must open the file"
    end = lines.index("---", 1)
    for line in lines[1:end]:
        # A wrapped value (a description broken over lines to fit 120 columns) is invalid YAML.
        assert KEY.match(line), f"{path.name}: not a `key: value` line: {line!r}"
    keys = [line.split(":", 1)[0] for line in lines[1:end]]
    assert {"name", "description"} <= set(keys)
    assert dict(line.split(": ", 1) for line in lines[1:end])["name"] == path.stem


def test_roster_is_not_empty():
    assert len(list(AGENTS.glob("*.md"))) >= 4

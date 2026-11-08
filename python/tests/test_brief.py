"""`gds brief <owner/repo>#N` (gdstudio #771): the issue or pull request read through `gh api` (recorded answers,
never the network), its labels with their descriptions and a pull request's changed files, and the `Read:` lines
printed for the task agent's prompt."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from gds_tools import brief, cli, lessons
from gds_tools.issues import IssueError

KIT = Path(__file__).resolve().parents[2]

ISSUE = {
    "number": 771,
    "title": "agents: Add gds brief and require Read lines in task prompts",
    "body": "The PreToolUse guard in .claude/hooks/guards.py already requires `Issue:`; see studio/hooks.md#docs.",
    "labels": [{"name": "A-agents", "description": "Agents and their instructions"}, {"name": "task"}],
}


class FakeGh:
    def __init__(self, data: dict, files: list[str] | None = None) -> None:
        self.data, self.files, self.calls = data, files or [], []

    def __call__(self, args: list[str]) -> str:
        self.calls.append(args)
        if args[-1].endswith("/files") or "--jq" in args:
            return "\n".join(self.files) + "\n"
        return json.dumps(self.data)


def test_fetch_reads_an_issue_with_its_label_descriptions():
    gh = FakeGh(ISSUE)
    subject = brief.fetch("Ryubara/gdstudio", 771, gh)
    assert gh.calls == [["api", "repos/Ryubara/gdstudio/issues/771"]]
    assert subject.labels == {"A-agents": "Agents and their instructions", "task": ""}
    assert not subject.pull and subject.files == ()


def test_fetch_reads_a_pull_requests_changed_files():
    gh = FakeGh({**ISSUE, "pull_request": {"url": "x"}}, [".claude/hooks/guards.py", "docs/studio/hooks.md"])
    subject = brief.fetch("Ryubara/gdstudio", 800, gh)
    assert subject.pull and subject.files == (".claude/hooks/guards.py", "docs/studio/hooks.md")
    assert gh.calls[1][:3] == ["api", "--paginate", "repos/Ryubara/gdstudio/pulls/800/files"]


def test_a_bad_ref_or_answer_is_an_error():
    with pytest.raises(IssueError, match="not owner/repo#N"):
        brief.parse_ref("#771")
    assert brief.parse_ref("Ryubara/gdstudio#771") == ("Ryubara/gdstudio", 771)

    with pytest.raises(IssueError, match="could not be read"):
        brief.fetch("Ryubara/gdstudio", 1, lambda args: "not json")


def test_text_prints_read_lines_that_exist_in_the_kit():
    subject = brief.fetch("Ryubara/gdstudio", 771, FakeGh(ISSUE))
    out = brief.text(KIT, subject)
    lines = out.splitlines()
    assert lines[0] == "Read: studio/hooks.md#docs"  # named in the issue comes first
    assert all(line.startswith("Read: ") for line in lines) and len(lines) == 6
    assert lessons.missing_refs(KIT, out) == []
    assert "(named in the issue)" in brief.text(KIT, subject, why=True).splitlines()[0]
    empty = brief.Subject("Ryubara/gdstudio", 1, "zzz qqq")
    assert brief.text(KIT, empty).startswith("No section of the docs fits Ryubara/gdstudio#1")


def test_the_command_prints_the_lines(monkeypatch, capsys):
    monkeypatch.setattr(cli.issues, "run_gh", FakeGh(ISSUE))
    assert cli.main(["brief", "Ryubara/gdstudio#771", "--limit", "2", "--kit", str(KIT)]) == 0
    out = capsys.readouterr().out.splitlines()
    assert out[0] == "Read: studio/hooks.md#docs" and len(out) == 2
    assert cli.main(["brief", "771", "--kit", str(KIT)]) == 2  # not owner/repo#N

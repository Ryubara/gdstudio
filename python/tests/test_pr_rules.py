"""Docs ship with the change: the `Lessons:`, `Kit docs:` and `Read first:` rules of .github/scripts/groundwork.py,
judged from a title, a description and a pull request's history (recorded `gh` answers, never the network)."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

yaml = pytest.importorskip("yaml")

KIT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location("groundwork", KIT / ".github" / "scripts" / "groundwork.py")
groundwork = importlib.util.module_from_spec(_spec)
sys.modules["groundwork"] = groundwork
_spec.loader.exec_module(groundwork)


def conv(**rules) -> dict:
    return {"pull_requests": {"placeholders": ["...", "<reason>"], **rules}, "merge": {"required_checks": ["build-ok"]}}


LESSONS = {"section": "Summary", "label": "Lessons:", "verbs": ["Fix", "Rework"], "bug_labels": ["bug"]}
KITDOCS = {"section": "Summary", "label": "Kit docs:", "verbs": ["Fix", "Rework"], "repo": "gdstudio"}


def body(*lines: str) -> str:
    return "## Summary\n\nWhat it does.\n" + "".join(f"\n{ln}" for ln in lines) + "\n\n## Testing\n\n- ran\n"


FAILED = {"failed_earlier": ["build-ok"], "closes": []}
BUG = {"failed_earlier": [], "closes": [{"number": 12, "labels": ["bug", "A-net"]}]}
CLEAN = {"failed_earlier": [], "closes": [{"number": 12, "labels": ["enhancement"]}]}
LESSON = "Lessons: docs/lessons/2026-11-02-a-gzip-decoded-twice.md"


def problems(rules, title, text, history=None):
    return groundwork.lessons_problems(conv(**rules), title, text, history)


def test_a_fix_title_needs_a_lesson_and_refuses_none():
    out = problems({"lessons": LESSONS}, "net: Fix the lag", body())
    assert len(out) == 1 and "its title says Fix" in out[0] and "'Lessons: none' is refused here" in out[0]
    out = problems({"lessons": LESSONS}, "net: Fix the lag", body("Lessons: none (nothing went wrong)"))
    assert out and "refused" in out[0]
    assert problems({"lessons": LESSONS}, "net: Fix the lag", body(LESSON)) == []
    assert problems({"lessons": LESSONS}, "net: Rework the lag", body()) != []


def test_a_failed_earlier_check_or_a_bug_issue_makes_any_title_a_correction():
    out = problems({"lessons": LESSONS}, "net: Add a packet", body(), FAILED)
    assert out and "build-ok failed on an earlier commit" in out[0]
    out = problems({"lessons": LESSONS}, "net: Add a packet", body("Lessons: none (reason)"), BUG)
    assert out and "closes #12, labelled bug" in out[0]
    assert problems({"lessons": LESSONS}, "net: Add a packet", body(LESSON), FAILED) == []


def test_elsewhere_the_line_is_optional_and_none_with_a_reason_is_allowed():
    assert problems({"lessons": LESSONS}, "net: Add a packet", body(), CLEAN) == []
    assert problems({"lessons": LESSONS}, "net: Add a packet", body("Lessons: none (a pure addition)"), CLEAN) == []
    out = problems({"lessons": LESSONS}, "net: Add a packet", body("Lessons: none"), CLEAN)
    assert out and "needs a reason in parentheses" in out[0]


def test_a_lessons_line_must_link_a_lesson_or_a_correction_row():
    bad = problems({"lessons": LESSONS}, "net: Add a packet", body("Lessons: I learned a lot"), CLEAN)
    assert bad and "links a lesson" in bad[0]
    for ok in (
        "Lessons: https://github.com/Ryubara/gdstudio/blob/main/docs/lessons/2026-11-02-a-b.md",
        "Lessons: [row](docs/studio/maintainer-corrections.md#found-by-playing)",
    ):
        assert problems({"lessons": LESSONS}, "net: Add a packet", body(ok), CLEAN) == []


def test_a_placeholder_line_counts_as_missing():
    out = problems({"lessons": LESSONS}, "net: Fix the lag", body("Lessons: ..."))
    assert out and "corrects earlier work" in out[0]


def test_kit_docs_is_required_on_a_fix_a_rework_and_a_bug_issue():
    for title, history in (("net: Fix a lag", None), ("net: Rework a lag", None), ("net: Add a lag", BUG)):
        out = problems({"kit_docs": KITDOCS}, title, body(), history)
        assert out and "Kit docs:" in out[0] and "in the same task" in out[0], title
    assert problems({"kit_docs": KITDOCS}, "net: Add a lag", body(), CLEAN) == []


@pytest.mark.parametrize(
    "line",
    [
        "Kit docs: https://github.com/Ryubara/gdstudio/pull/123",
        "Kit docs: Ryubara/gdstudio#123",
        "Kit docs: gdstudio#123 (the hand grips how-to)",
        "Kit docs: none (a one-line typo)",
    ],
)
def test_kit_docs_values_that_pass(line):
    assert problems({"kit_docs": KITDOCS}, "net: Fix a lag", body(line)) == []


@pytest.mark.parametrize("line", ["Kit docs: none", "Kit docs: later", "Kit docs: https://example.com/pull/1"])
def test_kit_docs_values_that_are_refused(line):
    assert problems({"kit_docs": KITDOCS}, "net: Fix a lag", body(line)) != []


def test_kit_docs_when_not_needed_is_still_checked_if_present():
    assert problems({"kit_docs": KITDOCS}, "net: Add a lag", body("Kit docs: soon"), CLEAN) != []


def test_read_first_names_sections_that_exist(tmp_path):
    (tmp_path / "studio").mkdir()
    (tmp_path / "studio" / "hooks.md").write_text("# Hooks\n\n## Docs {#docs}\n\n## Agent stalls\n", "utf-8")
    rule = {"read_first": {"section": "Summary", "label": "Read first:", "docs": str(tmp_path)}}
    history = {"closes": [{"number": 5, "labels": ["bug", "A-net"]}]}
    out = problems(rule, "net: Add a packet", body(), history)
    assert out and "names the sections of the docs its author read first" in out[0] and "gds brief" in out[0]
    out = problems(rule, "net: Add a packet", body("Read first: net, web"), history)
    assert out and "not areas or words" in out[0]
    out = problems(rule, "net: Add a packet", body("Read first: studio/hooks.md#docs, studio/hooks.md#nope"), history)
    assert out and "do not exist" in out[0] and "studio/hooks.md#nope" in out[0] and "#docs," not in out[0]
    good = "Read first: docs/studio/hooks.md#docs, [stalls](../studio/hooks.md#agent-stalls)"
    assert problems(rule, "net: Add a packet", body(good), history) == []
    assert problems(rule, "net: Add a packet", body(), {"closes": []}) == []  # closes nothing: nothing to read first
    assert problems(rule, "net: Add a packet", body(), None) == []  # history unavailable: judged from the text only


def test_read_first_without_a_docs_folder_checks_only_the_form(tmp_path):
    rule = {"read_first": {"section": "Summary", "label": "Read first:"}}  # a game: the kit's docs are not here
    history = {"closes": [{"number": 5, "labels": ["A-net"]}]}
    assert problems(rule, "net: Add a packet", body(), history) != []
    assert problems(rule, "net: Add a packet", body("Read first: net"), history) != []
    assert problems(rule, "net: Add a packet", body("Read first: studio/nowhere.md#x"), history) == []
    gone = {"read_first": {"section": "Summary", "label": "Read first:", "docs": str(tmp_path / "none")}}
    assert problems(gone, "net: Add a packet", body("Read first: studio/nowhere.md#x"), history) == []


def test_page_anchors_agree_with_the_tools():
    from gds_tools import lessons

    page = KIT / "docs" / "studio" / "hooks.md"
    assert groundwork.page_anchors(page) == lessons.anchors(page)
    page = KIT / "docs" / "engines" / "godot" / "web-export.md"
    assert groundwork.page_anchors(page) == lessons.anchors(page)


@pytest.mark.parametrize("value", ["(documentation only)", "(documentation only).", "  (documentation only).  "])
def test_a_reason_in_parentheses_may_end_with_one_full_stop(value):
    assert groundwork._reasoned(value)


@pytest.mark.parametrize("value", ["", "()", "().", "(why) extra", "(why)..", "(why).)x", "why", "why.", "(why"])
def test_text_after_the_parenthesis_or_no_reason_is_refused(value):
    assert not groundwork._reasoned(value)


@pytest.mark.parametrize("end", ["", "."])
def test_every_none_line_takes_the_trailing_period_or_not(end):
    lessons = body(f"Lessons: none (a pure addition){end}")
    assert problems({"lessons": LESSONS}, "net: Add a packet", lessons, CLEAN) == []
    assert problems({"kit_docs": KITDOCS}, "net: Add a packet", body(f"Kit docs: none (a typo){end}"), CLEAN) == []
    full = conv(failed_first={"label": "Failed first:", "section": "Testing", "verbs": ["Fix"]})
    text = f"## Testing\n\n- Failed first: none (documentation only){end}\n"
    assert groundwork.failed_first_problems(full, "docs: Fix a page", text) == []
    full = conv(issues_affected={"section": "Issues affected", "none": "None"}, sections=["Issues affected"])
    text = f"## Issues affected\n\nNone (one new lesson page){end}\n"
    assert groundwork.issues_affected_problems(full, text) == []
    shots = {"section": "Screenshots", "areas": ["docs"], "none": "Screenshots: none"}
    text = f"## Screenshots\n\nScreenshots: none (docs only){end}\n"
    assert groundwork.screenshot_problems(conv(screenshots=shots), "docs: Add a page", text) == []


def test_text_after_the_reason_is_still_refused_on_every_none_line():
    assert problems({"lessons": LESSONS}, "net: Add a packet", body("Lessons: none (a pure addition) extra"), CLEAN)
    full = conv(failed_first={"label": "Failed first:", "section": "Testing", "verbs": ["Fix"]})
    text = "## Testing\n\n- Failed first: none (documentation only) extra\n"
    assert groundwork.failed_first_problems(full, "docs: Fix a page", text)
    full = conv(issues_affected={"section": "Issues affected", "none": "None"}, sections=["Issues affected"])
    assert groundwork.issues_affected_problems(full, "## Issues affected\n\nNone (one page) extra\n")


class FakeGh:
    """Recorded `gh` answers for pull request 7 of Ryubara/gdstudio: three commits, the first two with check runs."""

    def __init__(self):
        self.calls = []

    def __call__(self, *args):
        self.calls.append(args)
        text = " ".join(args)
        if "pulls/7/commits" in text:
            return "aaa\nbbb\nccc\n"
        if "commits/aaa/check-runs" in text:
            return "build-ok\tfailure\t11\ntitle\tfailure\t12\ntest (ubuntu)\tsuccess\t11\n"
        if "commits/bbb/check-runs" in text:
            return "build-ok\tsuccess\t21\nmkdocs\ttimed_out\t22\n"
        if "commits/ccc" in text:
            raise AssertionError("the head commit is the one being judged")
        if "closingIssuesReferences" in text:
            return "99\n"
        if "issues/99" in text:
            return "bug,A-hooks\n"
        raise AssertionError(text)


def test_history_lists_watched_checks_that_failed_before_the_head_and_the_closed_issues():
    full = conv(lessons={**LESSONS, "history_checks": ["build-ok", "mkdocs"]})
    got = groundwork.collect_history(full, "Ryubara/gdstudio", 7, FakeGh())
    assert got == {"failed_earlier": ["build-ok", "mkdocs"], "closes": [{"number": 99, "labels": ["bug", "A-hooks"]}]}
    default = conv(lessons=LESSONS)  # no history_checks: the required checks (build-ok)
    assert groundwork.collect_history(default, "Ryubara/gdstudio", 7, FakeGh())["failed_earlier"] == ["build-ok"]


WATCHED = {"build-ok", "mkdocs"}


def test_a_run_cancelled_by_a_newer_push_is_not_a_failed_earlier_commit():
    # kit #244: build-ok failed only because its `test` jobs were cancelled by the next push (RESULTS: cancelled)
    listing = "build-ok\tfailure\t11\ntest (ubuntu)\tcancelled\t11\ntest (windows)\tsuccess\t11\n"
    assert groundwork.failed_checks(listing, WATCHED) == set()


def test_a_real_failure_still_counts_even_when_another_job_was_cancelled():
    listing = "build-ok\tfailure\t11\ntest (ubuntu)\tfailure\t11\ntest (windows)\tcancelled\t11\n"
    assert groundwork.failed_checks(listing, WATCHED) == {"build-ok"}
    assert groundwork.failed_checks("build-ok\tfailure\t11\ntest (ubuntu)\tsuccess\t11\n", WATCHED) == {"build-ok"}
    # nothing cancelled to excuse it
    assert groundwork.failed_checks("build-ok\tfailure\t11\n", WATCHED) == {"build-ok"}


def test_a_cancellation_in_another_run_does_not_excuse_a_failure():
    listing = "build-ok\tfailure\t11\ntest (ubuntu)\tsuccess\t11\ntest (other)\tcancelled\t12\n"
    assert groundwork.failed_checks(listing, WATCHED) == {"build-ok"}
    assert groundwork.failed_checks("build-ok\tfailure\ntest\tcancelled\n", WATCHED) == {"build-ok"}  # no suite id


def test_history_skips_the_earlier_commit_whose_run_was_cancelled_and_keeps_a_failed_one():
    class Gh(FakeGh):
        real = False

        def __call__(self, *args):
            text = " ".join(args)
            if "commits/aaa/check-runs" in text:  # cancelled by the push of bbb
                return "build-ok\tfailure\t11\ntest (ubuntu)\tcancelled\t11\n"
            if "commits/bbb/check-runs" in text:
                if self.real:
                    return "build-ok\tfailure\t21\ntest (ubuntu)\tfailure\t21\n"
                return "build-ok\tsuccess\t21\n"
            return super().__call__(*args)

    full = conv(lessons=LESSONS)
    gh = Gh()
    cancelled = groundwork.collect_history(full, "Ryubara/gdstudio", 7, gh)
    assert cancelled["failed_earlier"] == []
    assert problems({"lessons": LESSONS}, "ci: Add a job", body(), {**cancelled, "closes": []}) == []
    gh.real = True
    failed = groundwork.collect_history(full, "Ryubara/gdstudio", 7, gh)
    assert failed["failed_earlier"] == ["build-ok"]
    assert problems({"lessons": LESSONS}, "ci: Add a job", body(), {**failed, "closes": []})


def test_check_body_with_a_history_file(tmp_path, capsys):
    (tmp_path / "body.md").write_text(body(), encoding="utf-8")
    (tmp_path / "title.txt").write_text("net: Add a packet\n", encoding="utf-8")
    (tmp_path / "h.json").write_text(json.dumps(FAILED), encoding="utf-8")
    full = {
        "pull_requests": {
            "sections": ["Summary", "Testing"],
            "filled": ["Summary", "Testing"],
            "placeholders": ["..."],
            "local_paths": True,
            "lessons": LESSONS,
        },
        "merge": {"required_checks": ["build-ok"]},
    }
    args = type("A", (), {"body": str(tmp_path / "body.md"), "title": str(tmp_path / "title.txt")})
    args.history = str(tmp_path / "h.json")
    assert groundwork.cmd_check_body(full, args) == 1
    assert "build-ok failed on an earlier commit" in capsys.readouterr().err
    args.history = None
    assert groundwork.cmd_check_body(full, args) == 0


def test_the_kits_own_conventions_load_with_the_new_rules():
    loaded = groundwork.load(KIT / ".github" / "conventions.yml")
    rules = loaded["pull_requests"]
    assert rules["lessons"]["label"] == "Lessons:" and rules["read_first"]["label"] == "Read first:"
    assert (KIT / rules["read_first"]["docs"]).is_dir() and "areas_file" not in rules["read_first"]


SECTIONS = {**LESSONS, "names": "section", "edited": True}


def test_names_section_takes_a_topic_section_and_refuses_the_old_forms():
    """gdstudio #769: a learning updates a topic section, so `Lessons:` names it as page.md#anchor."""
    ok = body("Lessons: docs/engines/godot/web-export.md#threads")
    assert problems({"lessons": SECTIONS}, "net: Fix the lag", ok) == []
    for old in (LESSON, "Lessons: [row](docs/studio/maintainer-corrections.md#found-by-playing)"):
        out = problems({"lessons": SECTIONS}, "net: Fix the lag", body(old))
        assert out and "names the section of the rule as page.md#anchor" in out[0]
    out = problems({"lessons": SECTIONS}, "net: Fix the lag", body())
    assert "'Lessons: <page.md#anchor>'" in out[0]


def test_edited_needs_the_sections_page_among_the_changed_files():
    text = body("Lessons: docs/engines/godot/web-export.md#threads")
    rules = {"lessons": SECTIONS}
    assert (
        groundwork.lessons_problems(conv(**rules), "net: Fix it", text, CLEAN, ["docs/engines/godot/web-export.md"])
        == []
    )
    out = groundwork.lessons_problems(conv(**rules), "net: Fix it", text, CLEAN, ["python/x.py"])
    assert out and "does not change that page" in out[0]
    assert (
        groundwork.lessons_problems(conv(**rules), "net: Fix it", text, CLEAN, None) == []
    )  # no file list: not judged

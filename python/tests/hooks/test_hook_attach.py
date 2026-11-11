"""`gh pr create|edit --attach`: the images sit inside Screenshots, and a pull request that reached GitHub with local
image references is named at once (docs/studio/hooks.md#attach-paths)."""

from __future__ import annotations

from pathlib import Path

from hook_support import CONFIG, denied, dispatch, guards, patch, shell

GOOD_BODY = """## Summary

- ran

## Screenshots

- **Before:** ![before](./before.png)
- **After:** ![after](./after.png)

## AI use

- **Commits written by:** an AI
"""


def body_file(tmp_path: Path, text: str) -> Path:
    path = tmp_path / "body.md"
    path.write_text(text, encoding="utf-8")
    return path


ATTACH = "--attach {d}/before.png --attach {d}/after.png"


def test_attach_with_references_inside_screenshots_is_allowed(tmp_path):
    body_file(tmp_path, GOOD_BODY)
    flags = ATTACH.format(d=tmp_path)
    assert denied(shell(f"gh pr create --title x --body-file body.md {flags}", tmp_path)) == ""
    assert denied(shell(f"gh pr edit 7 -F {tmp_path}/body.md {flags}", tmp_path)) == ""
    assert (
        denied(shell(f"gh pr edit 7 --body-file={tmp_path}/body.md --attach '{tmp_path}/before.png#Before'", tmp_path))
        == ""
    )


def test_a_new_thing_may_say_before_none_and_attach_only_the_after(tmp_path):
    body_file(tmp_path, GOOD_BODY.replace("![before](./before.png)", "none (new screen)"))
    assert denied(shell(f"gh pr create --body-file body.md --attach {tmp_path}/after.png", tmp_path)) == ""


def test_attach_without_a_reference_names_the_missing_files_and_the_line_to_write(tmp_path):
    body_file(tmp_path, GOOD_BODY.replace("![after](./after.png)", "after.png"))
    reason = denied(shell(f"gh pr create --body-file body.md {ATTACH.format(d=tmp_path)}", tmp_path))
    assert "after.png" in reason and "before.png" not in reason.split("no reference for")[1].split(".")[0]
    assert "`![after](./after.png)`" in reason and "After: line" in reason and "after `## AI use`" in reason
    assert "Read the body back" in reason


def test_a_reference_outside_screenshots_does_not_count(tmp_path):
    outside = GOOD_BODY.replace("![after](./after.png)", "nothing") + "\n![after](./after.png)\n"
    body_file(tmp_path, outside)
    reason = denied(shell(f"gh pr create --body-file body.md {ATTACH.format(d=tmp_path)}", tmp_path))
    assert "no reference for after.png" in reason


def test_a_reference_in_the_template_comment_does_not_count(tmp_path):
    body_file(tmp_path, "## Screenshots\n\n<!-- write ![after](./after.png) here -->\n\n- **After:** ...\n")
    assert "no reference for after.png" in denied(
        shell(f"gh pr edit 3 --body-file body.md --attach {tmp_path}/after.png", tmp_path)
    )


def test_the_before_image_must_sit_between_before_and_after(tmp_path):
    swapped = GOOD_BODY.replace(
        "- **Before:** ![before](./before.png)\n- **After:** ![after](./after.png)",
        "- **Before:**\n- **After:** ![before](./before.png) ![after](./after.png)",
    )
    body_file(tmp_path, swapped)
    reason = denied(shell(f"gh pr create --body-file body.md {ATTACH.format(d=tmp_path)}", tmp_path))
    assert "Before: line" in reason and "between it and the After: line" in reason


def test_an_after_line_without_an_image_below_it_is_refused(tmp_path):
    body_file(tmp_path, GOOD_BODY.replace("![after](./after.png)", ""))
    reason = denied(shell(f"gh pr create --body-file body.md --attach {tmp_path}/before.png", tmp_path))
    assert "no image comes after the After: line" in reason


def test_attach_without_a_readable_body_file_is_refused(tmp_path):
    for command in (
        f"gh pr create --title x --attach {tmp_path}/after.png",
        f"gh pr edit 4 --attach {tmp_path}/after.png",
        f"gh pr create --body-file missing.md --attach {tmp_path}/after.png",
        f"gh pr create --body-file - --attach {tmp_path}/after.png",
        f'gh pr create --body "$(cat body.md)" --attach {tmp_path}/after.png',
    ):
        reason = denied(shell(command, tmp_path))
        assert "after `## AI use`" in reason and "--body-file" in reason, command


def test_a_literal_body_is_read_too(tmp_path):
    ok = "gh pr create --body '## Screenshots\n\n- **After:** ![a](./after.png)\n' --attach after.png"
    assert denied(shell(ok, tmp_path)) == ""
    bad = "gh pr create --body '## Screenshots\n\nsee after.png\n' --attach after.png"
    assert "no reference for after.png" in denied(shell(bad, tmp_path))


def test_other_gh_commands_and_no_attach_are_not_checked(tmp_path):
    assert denied(shell("gh pr create --title x --body-file missing.md", tmp_path)) == ""
    assert denied(shell("gh pr edit 3 --title y", tmp_path)) == ""
    assert denied(shell(f"gh issue create --title x --body y --attach {tmp_path}/a.png", tmp_path)) == ""
    assert denied(shell("gh pr view 3 --json body", tmp_path)) == ""


def test_the_attach_check_follows_cd_and_can_be_turned_off(tmp_path):
    sub = tmp_path / "sub"
    sub.mkdir()
    (sub / "body.md").write_text(GOOD_BODY, encoding="utf-8")
    flags = ATTACH.format(d=sub)  # the images are in the folder the `cd` moves to: `gh` finds `./before.png` there
    assert denied(shell(f"cd sub && gh pr create --body-file body.md {flags}", tmp_path)) == ""
    assert "does not exist yet" in denied(shell(f"gh pr create --body-file body.md {flags}", tmp_path))
    off = {**CONFIG, "attach": {"enforce": False}}
    assert dispatch.answer(shell(f"gh pr create --attach {tmp_path}/after.png", tmp_path), off) is None


PR_URL = "https://github.com/Ryubara/deadnight/pull/637"


def after(command: str, output: str, tool: str = "Bash") -> dict:
    return {
        "hook_event_name": "PostToolUse",
        "tool_name": tool,
        "tool_input": {"command": command},
        "tool_response": {"stdout": output, "stderr": ""},
        "cwd": ".",
    }


def test_local_image_references_are_told_from_uploads():
    body = "![a](./a.png) ![b](https://github.com/user-attachments/assets/1) <!-- ![c](./c.png) --> ![d](../x/d.JPG)"
    assert guards.local_images(body) == ["![a](./a.png)", "![d](../x/d.JPG)"]
    assert guards.local_images("see [the docs](./docs/x.md) and ![u](https://example.com/u.png)") == []


def test_a_pull_request_opened_with_local_images_is_named_at_once(monkeypatch):
    """The path the guard before the command cannot see: the body that reached GitHub is read back."""
    patch(monkeypatch, "local_images_in", lambda url: ["![before](./before.png)"])
    commands = [
        "gh pr create --repo Ryubara/deadnight --body-file b.md --attach a.png 2>&1 | tail -5",
        "gh pr edit 637 --body-file b.md",
        "python open_pr.py",  # a script that runs gh itself: only its output says a pull request was made
    ]
    for command in commands:
        out = dispatch.answer(after(command, f"\n{PR_URL}\n"), CONFIG)
        text = out["hookSpecificOutput"]["additionalContext"]
        assert PR_URL in text and "![before](./before.png)" in text and "pr edit N --body-file" in text, command
    powershell = dispatch.answer(after("gh pr create --attach a.png", PR_URL, tool="PowerShell"), CONFIG)
    assert "local image references" in powershell["hookSpecificOutput"]["additionalContext"]


def test_a_clean_description_or_an_unrelated_command_says_nothing(monkeypatch):
    asked = []
    patch(monkeypatch, "local_images_in", lambda url: asked.append(url) or [])
    assert dispatch.answer(after("gh pr create --attach a.png", PR_URL), CONFIG) is None
    assert asked == [PR_URL]
    patch(monkeypatch, "local_images_in", lambda url: ["![x](./x.png)"])
    assert dispatch.answer(after("gh pr view 637", PR_URL), CONFIG) is None  # a read prints the address too
    assert dispatch.answer(after("gh pr create --attach a.png", "no address printed"), CONFIG) is None
    off = {**CONFIG, "attach": {"readback": False}}
    assert dispatch.answer(after("gh pr create --attach a.png", PR_URL), off) is None

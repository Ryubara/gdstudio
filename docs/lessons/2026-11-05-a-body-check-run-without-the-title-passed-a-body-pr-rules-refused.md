---
areas: [tools, ci]
---
# A body check run without the title passed a body `pr-rules` refused

2026-11-05

- **Saw:** Deadnight #1233 (a `gameplay` change, nothing visible) had `Screenshots: none (reason)` in its description;
  the author reported `gds pr check-body` as passing, and `pr-rules` then failed with "a `gameplay` pull request
  shows what changed in ## Screenshots ... the 'After:' capture is missing".
- **Cause:** the screenshots, failed-first and lessons rules judge the title, so they run only when `--title` is given.
  The same body with `--title`: refused; without it: `description: ok`. The guard on `gh pr edit -F <body>` has the
  same hole: it passes a title to the check only when the command itself carries `--title` (`check_body` in
  `.claude/hooks/guards.py`), and an edit of a description seldom does.
- **Fix:** always pass `--title <file>` (the pull request's real title, one line) and `--repo <worktree>`; for an
  open pull request write the title with `gh pr view N -R <repo> --json title -q .title`. Do not report "check-body
  passed" for a run without `--title`. The history rules (a failed earlier check, a `bug` issue) are not run locally
  at all: `pr-history` is read by CI only, so `Lessons:` can still be required after the push.
- **Check for next time:** a local check that takes optional inputs is run with all of them; `description: ok` from a
  run without `--title` says nothing about the three title rules. Open follow-up: the edit guard should read the live
  title of the pull request it edits (a change to `.claude/hooks/`, merged by the maintainer).
- **Docs:** [Hooks](../hooks.md#pr-body).

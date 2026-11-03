---
areas: [process, tools]
---
# `pre-commit run --all-files` passed, and the commit then failed gdlint on the new files

2026-11-03

- **Saw:** `uvx pre-commit run --all-files` printed no failure, then `git commit` failed with eight `max-line-length`
  errors and two missing `.gd.uid` files, all in files created in the same task.
- **Cause:** `--all-files` means every file git tracks. A file that was never `git add`ed is not checked, so the new
  scripts, tests and capture scenes (most of the task's code) were skipped until the commit hook ran on them.
- **Fix:** `git add -A` first (or `git add -N .`), then run the full hook once: it checks the new files, and a project
  import writes the missing `.gd.uid` files before the add. Do this before the first commit, not after it fails.
- **Docs:** [Hooks](../hooks.md).

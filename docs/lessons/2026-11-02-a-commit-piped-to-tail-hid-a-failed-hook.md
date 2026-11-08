---
areas: [process, tools]
---
# A commit piped to `tail` hid a failed hook, and the pull request found no commits

2026-11-02

- **Saw:** `gh pr create` failed with "No commits between main and <branch>" right after a `git commit ... | tail -3`
  that printed only the last hook lines (Passed/Skipped).
- **Cause:** the markdownlint hook (table separator style, lines over 120 characters) failed in the middle of the
  output; `tail` cut that part off and the pipe hid git's exit code, so the agent took the commit for done.
- **Fix:** run the commit alone (or check `git log --oneline -1` and `git status --short` after it), read the whole hook
  output, fix the lint (`| --- |` separators, wrap research pages at 120) and commit again before pushing or opening
  the pull request. Run `uvx pre-commit run --all-files` first and read its failures.
- **Docs:** [Hooks](../studio/hooks.md).

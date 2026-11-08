---
areas: [process, tools]
---
# A `gds merge-main --continue` piped to `tail` looked done, and the merge stayed open

2026-11-02

- **Saw:** deadnight #656, second merge of main: `gds merge-main --continue | tail -2` printed two `Skipped` hook lines;
  the agent rebuilt, reimported and found `git log -1` still on the previous merge with `MERGE_HEAD` set.
- **Cause:** `--continue` commits through pre-commit on the resolved files only, so a line added while resolving (a
  licence sentence of 155 characters) met markdownlint's 120 limit there. The failure was printed first; `tail` showed
  only the last hook lines and the pipe hid the exit code.
- **Fix:** run `uvx pre-commit run --files <resolved files>` before `--continue`, run `--continue` without a pipe, and
  check `git log --oneline -1` (the "Merge origin/main" title) before rebuilding or pushing.
- **Docs:** [Hooks](../studio/hooks.md); the same cause for a plain commit in
  [a commit piped to tail](2026-11-02-a-commit-piped-to-tail-hid-a-failed-hook.md).

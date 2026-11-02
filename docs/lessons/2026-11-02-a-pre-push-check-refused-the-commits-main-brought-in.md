---
areas: [tools, process]
---
# A pre-push check refused the commits that a merge of main brought in

2026-11-02

- **Saw:** after `gds merge-main` on `hooks-attach-screenshots`, `git push` failed in the `pushed commits follow the
  conventions` hook: "'hooks: Add a stop check for task agents that end before their report (#155)': 75 characters; at
  most 72", for two commits that were already on `main`.
- **Cause:** `check-push` judges `PRE_COMMIT_FROM_REF..PRE_COMMIT_TO_REF`, the commits the remote branch lacks. After
  a merge of `main` that includes every commit of `main` the branch had not seen. Their titles are the squash titles
  GitHub wrote (the pull request title plus the pull request number in parentheses), which CI never judges as commits
  and which may pass 72 characters. The check was tested with a single branch and never with a merge of `main` in the
  range.
- **Fix:** the range excludes what `origin/main` has (`--not origin/main`, when the ref exists); the branch's own
  commits and the merge commit are still judged. A test merges a 75-character squash title from `main` into a branch
  and pushes it.
- **Check for next time:** a check on the commits of a push is tested with a merge of `main` in the range, not only
  with the branch's own commits.
- **Docs:** [Hooks](../hooks.md).

---
areas: [tools, process]
---
# A failed `cd` let the next commands write and commit in the kit's main checkout

2026-11-03

- **Saw:** a lesson file, `git add -A` and `git commit` ran in `repos/gdstudio` (the main checkout, branch `main`) and the
  commit was made there; only the push failed. The worktree I meant to use was gone: its pull request had auto-merged
  and the workspace removed it.
- **Cause:** `cd <worktree> && ...` was written as `cd <worktree>; cat > file ...; git commit`, so after the failed `cd`
  the rest ran in the shell's start folder, which is the main checkout. The commit hook did not refuse a commit on `main`
  there.
- **Fix:** chain with `&&` after the `cd` (or use `git -C <worktree>`), look at `git branch --show-current` before a
  commit, and make a new worktree for a follow-up to a merged pull request. The stray commit was moved to a branch and
  `main` reset to `origin/main` before anything was pushed.
- **Docs:** [starting work](../starting-work.md).

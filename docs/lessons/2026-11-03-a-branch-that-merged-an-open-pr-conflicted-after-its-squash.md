---
areas: [process, ci]
---
# A branch that merged another open pull request's branch conflicted in 17 files after its squash

2026-11-03

- **Saw:** Deadnight #230 (bot slot filling) built on #643, which was still an open pull request. The agent merged
  #643's branch into its own to have the code. When #643 landed, `gds merge-main` stopped on 17 conflicted files, none of
  them in the agent's own lines.
- **Cause:** a pull request is squash-merged, so `main` holds one new commit with #643's content, and the agent's branch
  held #643's original commits underneath its own. Git sees two histories that made the same edits differently (the
  squash also carried #643's later fixes), so every file both touched conflicts, even where the text is nearly equal.
- **Fix:** keep your own work as a patch of your commits only (`git diff <the merged branch's tip> HEAD > mine.patch`),
  save it outside the worktree, `git reset --hard origin/main` on the unpushed branch, and `git apply --3way mine.patch`:
  it applied cleanly. Better still, when the coordinator says another pull request is about to land, build the parts
  that do not need it, and merge only after it is on `main`; if you must build on it first, never push the merge, and
  expect to rebase your patch this way.
- **Docs:** [Starting work](../starting-work.md#parallel).

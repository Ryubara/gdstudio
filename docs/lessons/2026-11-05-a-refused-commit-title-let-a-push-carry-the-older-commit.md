---
areas: [process, tools]
---
# A refused commit title let the next `git push` carry only the older commit

2026-11-05

- **Saw:** Deadnight #1280: a commit titled 74 characters was refused by the title hook (at most 72), and the command
  that followed in the same line, `gds merge-main; git push`, ran anyway: `gds` said "the worktree has uncommitted
  changes" and the push sent the previous commit, so the branch lacked the last change until it was noticed.
- **Cause:** the commit, the merge and the push were chained with `;` instead of `&&`, and nothing read the hook's
  verdict before the push.
- **Fix:** recommitted with a shorter title and pushed again. Count a title before it is written (`wc -c` on the title
  file), chain a commit and its push with `&&`, and read `git log -1` and `git status` before pushing.
- **Docs:** [Hooks](../studio/hooks.md).

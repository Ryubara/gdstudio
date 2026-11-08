---
areas: [process, tools]
---
# A commit the hooks refused went unseen behind `tail`, and the pull request opened empty

2026-11-04

- **Saw:** Deadnight #1003 was pushed, opened and set to auto-merge, and its diff held only the base branch's merge:
  none of the change. `git commit ... | tail -3` showed three "Skipped" hook lines; the commit had been refused twice (the
  title's verb `Stop` is not in the list, and `gdformat` reformatted two files and rolled the commit back).
- **Cause:** the output was cut to its last lines, the commit's exit code went with the pipe, and `git push` and
  `gh pr create` followed in the same command. The issue's own title used a verb the commit rules do not allow.
- **Fix:** run a commit alone and read all of it (`git log --oneline -1` after), push only when it shows the new commit;
  `gh pr diff N --name-only` after opening a pull request names what it holds; turn auto-merge on after that.
- **Docs:** [hooks](../studio/hooks.md).

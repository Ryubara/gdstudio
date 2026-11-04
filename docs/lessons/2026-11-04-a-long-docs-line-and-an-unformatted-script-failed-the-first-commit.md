---
areas: [process, tools]
---
# A 163-character docs line and an unformatted script failed the first commit

2026-11-04

- **Saw:** the first commit of Deadnight #987 was refused by pre-commit: a line of 163 characters in
  `docs/design/animation.md` (the markdown line limit is 120) and `clip_arms_tour.gd` not in gdformat's layout.
- **Cause:** both were written in one long edit session and the hooks ran for the first time at the commit, with the
  other changes of the task around them.
- **Fix:** run `uvx pre-commit run --files <the files just edited>` after each docs or script edit, not at the end, and
  wrap by hand as you write (a table row is the only line that may pass 120). Add new files first
  (`git add -N .`), see [pre-commit skipped the new files](2026-11-03-pre-commit-all-files-skipped-the-new-files.md).
- **Docs:** [Hooks](../hooks.md).

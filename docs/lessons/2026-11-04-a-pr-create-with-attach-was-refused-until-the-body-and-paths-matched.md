---
areas: [tools, ci]
---
# A `gh pr create --attach` was refused four times: the body was edited in the same command, and `$S` was not expanded

2026-11-04

- **Saw:** the hook refused `gh pr create --attach` with "the body has no reference for <file>" and then with "a different
  file from `./<file>`", though the body had been fixed; a worktree beside the game also had no gdUnit4 (`File not found`
  for `GdUnitCmdTool.gd`) when a test was run in it.
- **Cause:** the hook reads the body file and the command text before the command runs, so a body edited by a script in
  the same command, or a path written as a shell variable (`$S/x.png`), is read as it was. The `![alt](./file)` reference
  must name the same file as `--attach`, a relative path from the folder the command runs in. The gdUnit4 addon is in the
  repository's `.git/info/exclude`, so a new worktree does not have it.
- **Fix:** edit the body in a command of its own; `cd` into the folder that holds the images and write `--attach ./<file>`
  with `![alt](./<file>)` in the body (or the same absolute path in both, never a variable); copy
  `game/addons/gdUnit4` from another worktree before running tests in a fresh one.
- **Docs:** none beyond this lesson (the hook's own message names each case).

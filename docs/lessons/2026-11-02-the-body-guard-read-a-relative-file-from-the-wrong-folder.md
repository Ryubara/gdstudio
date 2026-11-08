---
areas: [tools, process]
---
# The body guard said a body file "does not exist yet" after a cd it could not follow

2026-11-02

- **Saw:** on deadnight #611 `cd C:/Repositories/GDStudio/scratch/deadnight/crosshair-hit && gh pr edit 611
  --body-file body611.md --attach ./before.png ...` was refused with "the body file body611.md does not exist yet",
  although the file was there. The same command with an absolute `--body-file` passed.
- **Cause:** the guard resolves a relative `--body-file` against the folder the shell is in after the command's own
  `cd`. The plain `cd C:/dir` and `cd dir` forms were followed, but a `cd` it could not place was not: Git Bash's
  `/c/dir`, `cd /d dir`, `~`, `cd -`, `cd $DIR`. Those left the folder at the session's, so the file was looked for in
  the wrong place and the message ("does not exist yet") blamed the file, not the guard. The issue named only the case
  that was reproducible by reading the code; the first thing to do was to run the guard on every form of the line.
- **Fix:** `change_dir` in `.claude/hooks/guards.py` follows `cd`, `pushd`, `Set-Location [-Path]`, `cd /d` (quoted
  paths with spaces too), `~` and `/c/dir` on Windows. A `cd` it cannot follow marks the folder unknown for the rest of
  the line, and a relative body file then gets "use an absolute path" instead of a guess. The "does not exist yet"
  message says which path it looked in. `--attach` paths are never opened by the guard (only their names are read), so
  they needed no change.
- **Check for next time:** a guard that reads a relative path must say where it looked, and when it cannot know the
  folder it says so and asks for an absolute path; it never reports a missing file from a guess. Run a new path guard
  on every spelling of the folder change (`cd`, `;`, quotes, `/c/`, `~`, `$VAR`) before calling it right.
- **Docs:** [Hooks](../studio/hooks.md#pr-body).

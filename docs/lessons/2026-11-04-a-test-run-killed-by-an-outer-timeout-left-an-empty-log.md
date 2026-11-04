---
areas: [tests, tools]
---
# A full GdUnit run killed by an outer timeout left an empty log, and its log landed in the worktree

2026-11-04

- **Saw:** a long headless GdUnit run, piped through `grep | head`, ended with an empty log and exit code 0, so it
  looked finished with nothing to show; the rerun with a log file named `s_a.log` put that file into the worktree
  (untracked) while the wait loop watched the same name under the scratch folder and never saw it end.
- **Cause:** an outer `timeout 590` killed Godot before the filters had anything to print (the pipe hides the kill: the
  last stage exits 0), and the script `cd`ed into the worktree, so a relative log name was written there, not where
  the waiting loop looked.
- **Fix:** no outer timeout shorter than the run (the script's own `timeout 1500` is the limit); write the raw output to
  an absolute log path in the scratch folder, end it with a `FINISHED` line, and wait on that same absolute path;
  read `Overall Summary` from the raw log instead of filtering while it runs. Check `git status` for strays.
- **Docs:** none yet beyond this lesson (a headless test-run helper in `gds` would hold the pattern).

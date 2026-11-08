---
areas: [tools, process]
---
# A kill by command-line pattern stopped other engineers' test runs

2026-11-06

- **Saw:** a GdUnit probe of mine wrote a log that filled with `Debugger Break` lines after I had stopped its task, so
  I ended every process whose command line held `GdUnitCmdTool`. The list I printed first held a dozen: runs of
  other engineers' suites on the same machine (`--path game ... -a res://tests/night`) and a pre-commit `gdlint`,
  and I killed them with mine.
- **Cause:** the task stop of the harness does not end the Godot child of a shell command, and I looked for it by
  a pattern that is the same for everyone (the runner's name) instead of by what only I started. The brief for the
  task says the opposite: stop a process by its PID, the one you started.
- **Fix:** start a long Godot through a script that writes its own PID (`echo $! > pid`) or find it by the path of
  the worktree that is yours (`--path C:/.../worktrees/<repo>/<branch>/game`, which no one else has) and by the
  parent chain of the `timeout` you started; print the candidates and check each has your path before the first
  `Stop-Process`. A parse error under `-d` hangs the run (see
  [GdUnit tests](../engines/godot/gdunit-tests.md#command-line)): give every run a short
  `timeout` and read the log after it, so there is nothing left to hunt for.
- **Docs:** the shared-machine rules of the agents' brief (kit `docs/studio/starting-work.md`); nothing else changes.

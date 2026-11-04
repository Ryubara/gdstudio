---
areas: [tests, tools]
---
# A hand-over was green only on the folders it had run, and the old runner kept running

2026-11-04

- **Saw:** a helicopter-drop branch (Deadnight #1057) came with "tests passing" and a `final.txt`, yet the whole suite on
  the merged branch failed in two folders nobody had listed (`tests/world` light cap, `tests/tuning` sound tables) and one
  headless `ERROR: Parameter "material" is null`. The previous agent's test runner script and its Godot processes were
  still running in the worktree and writing logs.
- **Cause:** the previous agent ran the new suites and the folders it guessed; suites that read the project for every
  light, sound or export and pin it live in other folders. Its summary file was overwritten by a loop still running. The
  runner script outlived the agent, so killing its Godot only moved it on to the next shard.
- **Fix:** run every folder of `game/tests` on the merged branch (four loops at most, one log folder per run, counts read
  from the logs), read the logs for `ERROR`, and ignore an earlier summary. Before rerunning, list the processes whose
  command line names the worktree, stop the runner script first, then its `timeout` and Godot children, by PID, and check
  that the logs stop growing. A new light, sound, export or tuning field is followed by `tests/world` and `tests/tuning`.
- **Docs:** [Lessons](index.md): no page covers it yet; this file is the record (the game side is
  `docs/lessons/2026-11-04-pinning-tests-in-other-folders-failed-for-a-new-light-and-a-new-sound-field.md` in Deadnight).

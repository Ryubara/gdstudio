---
areas: [tests, ci]
---
# A GdUnit wrapper printed the usage and parallel shard runs stalled for 25 minutes

2026-11-05

- **Saw:** Deadnight #1231. (1) A wrapper around `GdUnitCmdTool.gd` named `gdunit_run.gd` printed GdUnit's usage and ran
  no suite. (2) Two full-shard runs started at once, and later one more beside another agent's, printed nothing for 25
  minutes and were killed by `timeout`; the same list alone took 8 minutes. (3) A first guess, a type cycle between
  two classes, was "fixed" in the game's scripts and changed nothing.
- **Cause:** (1) GdUnit finds its own arguments after the command-line argument that contains `GdUnitCmdTool.gd`; a
  wrapper named otherwise leaves it with none. (2) The net suites take fixed ports and the machine is shared, and a
  `| sed | grep` summary hid whether anything ran. (3) The cycle was a guess from one probe, not a measured cause.
- **Fix:** keep `GdUnitCmdTool.gd` at the end of the wrapper's name (`warm_GdUnitCmdTool.gd`); run one shard at a time
  with the log in a file and look at its last `Run Test Suite` line; before editing the game for a guess, run the
  suite alone with and without the edit (the counts did not move, so it was reverted).
- **Docs:** [Leaks at exit in a GdUnit run](../engines/godot/test-exit-leaks.md#a-suite-that-only-names-a-class).

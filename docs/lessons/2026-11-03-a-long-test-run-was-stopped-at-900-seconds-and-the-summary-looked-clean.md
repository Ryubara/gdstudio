---
areas: [tests, tools]
---
# A long test run was stopped at 900 seconds and its summary looked clean

2026-11-03

- **Saw:** a run of five test folders through `gds godot` (deadnight #690) ended with a short summary of only
  `PASSED` lines and two failures. The folder `tests/night` had barely started: the last line of the log, `gds: godot did
  not finish within 900 s and was stopped`, was the only trace, and a `grep` for `FAILED|Statistics|Overall` did not
  show it. A hundred and fifty suites had not run.
- **Cause:** `gds godot` stops Godot after `--timeout`, default 900 s (`docs/godot/no-focus.md`). A helper that
  filters a log down to its failures cannot tell "all passed" from "stopped half way".
- **Fix:** give a long run `--timeout`, or split the suites into chunks that each fit and run three at a time; have the
  helper print the stop line, and compare the number of `Run Test Suite` lines with the number of `test_*.gd` files
  asked for before reading the summary as complete.

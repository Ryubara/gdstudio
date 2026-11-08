---
areas: [tests, gameplay]
---
# A benchmark printed numbers from a run full of script errors

2026-11-01

- **Saw:** two rows of a frame-time table were absurd (23 to 39 ms for 10 zombies, against 2 ms for the rest) and the
  log held thousands of `SCRIPT ERROR` lines beside the normal result lines.
- **Cause:** a misspelled property (`visible_range_end` for `visibility_range_end`) on an untyped path is a runtime
  error, not a parse error: the zombie's setup stopped halfway and the run went on, then printed its result.
- **Fix:** the runner logs every `ERROR` line next to the results and the log is read for them before any number is
  trusted; the property name was corrected and the whole matrix rerun.
- **Docs:** [Zombie crowds](../engines/godot/crowds.md#gotchas-found-while-building-it).

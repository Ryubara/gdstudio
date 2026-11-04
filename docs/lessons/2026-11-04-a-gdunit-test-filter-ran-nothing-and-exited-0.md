---
areas: [tests, godot]
---
# A GdUnit test filter ran nothing and exited 0

2026-11-04

- **Saw:** `-a res://tests/x.gd::test_y` printed nothing and exited 0 in 2 s, which reads as a pass.
- **Cause:** `::` is not GdUnit's form of a filter here: no test ran, and no failure is a success.
- **Fix:** run the whole suite, and read the summary's count of test cases, not the exit code alone.
- **Docs:** none.

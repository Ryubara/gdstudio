---
areas: [tests, tools]
---
# GdUnit exit 105 was read as a crash of the game

2026-11-05

- **Saw:** a windowed run of a suite ended with `exit 105` and was filed as "a crash or a stop, not measured further".
- **Cause:** GdUnit4's `RETURN_ERROR_SCRIPT_ERRORS_DETECTED` is 105: a script error was printed while it discovered the
  tests (a test file, or a script it loads, that does not parse). 100 is "tests failed", 101 "warnings", 103 "headless
  not supported", 104 "Godot version not supported". None is the game stopping.
- **Fix:** read the log above `Abnormal exit with 105`, it lists the errors; run the same suite again after fixing
  the script. The suite on `main` exited 100 with the real failures.
- **Docs:** Deadnight `docs/research/windowed-night-ui-suites.md`.

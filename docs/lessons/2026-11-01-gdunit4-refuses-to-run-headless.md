---
areas: [godot, tests]
---
# GdUnit4 refuses to run headless

2026-11-01

- **Saw:** "Headless mode is not supported", exit code 103.
- **Cause:** GdUnit4 blocks headless runs unless told otherwise.
- **Fix:** pass `--ignoreHeadlessMode`; the port 0 remote-debug error line is harmless. A failing suite stops at its
  first failure: fix and rerun to see the rest.
- **Docs:** each game's `AGENTS.md` (Build and test).

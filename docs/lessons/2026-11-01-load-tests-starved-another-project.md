---
areas: [tests, process]
---
# Load tests starved another project on the same machine

2026-11-01

- **Saw:** to reproduce flaky tests under load, agents started dozens of busy-loop headless Godots plus parallel full
  suites; one run left 80 busy loops for an hour, and another project's builds stalled behind 100% CPU.
- **Cause:** "reproduce under load" had no limit, and nothing stopped the load when the measurement ended.
- **Fix:** at most four parallel suites and no busy-loop processes; stop every process you start, by PID, the moment its
  measurement ends; give long commands a timeout; prefer a deterministic reproduction (step frames by hand, inject the
  delay). Now in the engineer agent definitions.
- **Docs:** [Building games with agents](../studio/building-games-with-agents.md).

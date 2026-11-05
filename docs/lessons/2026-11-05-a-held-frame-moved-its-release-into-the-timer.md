---
areas: [godot, gameplay, tests]
---
# Keeping the last event by reference put its release inside a timed region and failed a budget

2026-11-05

- **Saw:** Deadnight #1172 failed the late-round budget on CI (`server.challenges is 0.0135 times the calibration, over
  its limit 0.012`) after a per-frame check was added to the challenge tracker; a 4 us micro-benchmark of the check
  alone had read as harmless. Cutting the check to the minimum (store the frame, test a flag) still read 0.0116 to
  0.0125 locally against 0.0085 to 0.0098 with the calls switched off.
- **Cause:** the tracker kept the last frame event by reference to read positions from it later. The next frame
  replaced it, and the old frame's whole tree of dictionaries and arrays was freed inside `PerfProbe.begin()` /
  `end()`, where before the caller had freed it outside the timer. The work did not grow, it moved into the label.
  Single-run ratios also move 0.0085 to 0.0125 on a busy machine, so one run says nothing.
- **Fix:** keep no event: do the work in the frame it needs (the first frame of a break, a tick later than the
  event) and read shared state the tracker already keeps (a dictionary of doors) instead of the event. Measured as
  six interleaved pairs, code on against its calls switched off, the same ratios within noise (0.0093 to 0.0106
  against 0.0092 to 0.0099). A per-event `OtherClass.CONST.has(type)` check was also removed from the hot path.
- **Check:** before reporting a change to a timed system, run the budget's own case (`tools/perf/check_budget.py`
  over an `--autopilot --sample=1` run, the CI command) at least three times interleaved with the change switched
  off, not a micro-benchmark; never hold an event or a frame between calls of a timed function.
- **Docs:** [Performance budgets](../godot/performance-budgets.md#a-timed-function-must-not-hold-what-it-is-handed).

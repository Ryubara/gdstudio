---
areas: [web, ci]
---
# A ratio gate on the web load cannot see a cost of a tenth

2026-11-03

- **Saw:** Deadnight #873 gated the night's load on its ratio to the same run's menu load (a flat 72 s had failed four
  times on a slow runner). The brief also asked that a build with the sound decode back behind the bar would fail it.
- **Cause:** the 28 runs the limit was set from are themselves builds with that decode, so a limit above their worst
  (4.56) cannot fail them; and the decode is about 4 s of 40 (a ratio 0.3 to 0.5 higher) against a run-to-run spread of
  2.2 to 4.6. A ratio absorbs the runner's speed, not a small real cost.
- **Fix:** the ratio gate (limit 5.5, backstop 150 s) catches a large growth (about 80 % over the median); a known small
  cost is held by a count in a test (seconds of sound decoded behind the bar, `test_load_cost.gd`), which does not move
  with the runner.
- **Docs:** Deadnight `docs/research/web-export.md`, "Loading a night". Check: before promising that a gate catches a
  regression, replay the gate on runs of the regressed build (here the 28 runs); if they pass, the gate cannot, and the
  regression needs a count test.

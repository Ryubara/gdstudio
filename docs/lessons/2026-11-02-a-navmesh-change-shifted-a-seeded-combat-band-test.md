---
areas: [gameplay, tests]
---
# A navigation mesh change shifted a seeded combat-band test that reads a rate from few samples

2026-11-02

- **Saw:** after a tighter navmesh contour, `test_bot_bands.gd` failed in CI for the Veteran: "blows due 19" (needs more
  than 25) and dodge 0.68 against the level's 0.50 (band 0.35 to 0.65). The agent had run the bots and zombies suites
  but not the night suite.
- **Cause:** the zombies in that fight walk the shared mesh, so any mesh change moves every blow. The fight is
  bit-identical from run to run, so the few dozen blows a four-seed run reads are one draw: on `main`, four seeds read
  dodge 0.50 and ten seeds read 0.67 (outside the band); with the change four read 0.68 and ten read 0.60.
- **Fix:** run the test on `main` and on the branch (same numbers each time shows it is the change, not flakiness), then
  run both with more seeds (`BOTS_BANDS_SEEDS=10`) before judging; raise the seeds until the rate rests on enough
  events and keep the band. Run `tests/night` as well as the suites of the code you edited when the change is to a
  shared asset (navmesh, collision, spawn points).
- **Docs:** [Bots research, tuning the follow soak](../research/bots.md).

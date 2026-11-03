---
areas: [tests, gameplay]
---
# A band test that reads near its edge fails on the next change that redraws the run

2026-11-03

- **Saw:** after the cooldown fix in Deadnight (#708) the bot bands test failed twice: the Veteran's dodge read 0.67
  (band 0.50 +- 0.15) on a local run, and after the tolerance was widened to 0.20 its head share read 0.22 (band 0.30
  +- 0.07) on the CI runner.
- **Cause:** eight seeds give about 215 hits and 45 blows, a standard error of 0.03 on a head share and 0.06 on a
  dodge, so a half-band of 0.07 or 0.15 is only about two standard errors, and a fight of bots is chaotic: any change
  to when the guns fire draws every seed again (the change moved the pistol's rate by 1%). But sixteen seeds did not
  cure it: on a Windows machine they read the head share at 0.30 before and 0.28 after, on the CI runner at 0.22
  after (and 0.26 for `main` over eight). The runner's number sits near the floor of the band on any build, so the
  band was a poor fit, which the hit-zone rework (#694) then moved altogether.
- **Fix:** do not widen the tolerance or add seeds on the first red. Run the test on `main` and on the change, on the
  runner and locally (twice the seeds); if `main` already reads near an edge on the runner, recalibrate the band to
  what the bots do, in the pull request that changes what they hit, and wait for that one rather than racing it.
- **General:** a band test that passes on `main` by a few points is a coin flip for the next unrelated change. A
  failure there is a calibration question first (where does `main` read on the runner?), a sample size second.
- **Docs:** Deadnight `docs/research/bots.md` (the bands paragraph) and `game/tests/night/test_bot_bands.gd`.

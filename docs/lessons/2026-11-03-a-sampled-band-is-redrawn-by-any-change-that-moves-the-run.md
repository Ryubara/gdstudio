---
areas: [tests, gameplay]
---
# A band test read from a small sample failed on a change that did not move the number

2026-11-03

- **Saw:** after the cooldown fix in Deadnight (#708) the bot bands test failed twice: the Veteran's dodge read 0.67
  (band 0.50 +- 0.15) on a local run, and after the tolerance was widened to 0.20 its head share read 0.22 (band 0.30
  +- 0.07) on the CI runner.
- **Cause:** eight seeds give about 215 hits and 45 blows, a standard error of 0.03 on a head share and 0.06 on a
  dodge, so a half-band of 0.07 or 0.15 is only about two standard errors. The change moved the pistol's rate by 1%,
  but a fight of bots is chaotic: any change to when the guns fire draws every seed again. Sixteen seeds read the head
  share at 0.30 before and 0.28 after, the dodge at 0.60 and 0.61: the true numbers did not move.
- **Fix:** run the fight over more seeds until the band is at least three standard errors, and say in the comment how
  many hits and blows a run has. Widen a tolerance only for a measured offset of the bot (the Regular's dodge sits
  0.15 under the level's), never to cover a draw.
- **General:** before calling a band failure noise or a regression, run the same test on `main` and on the change
  with twice the seeds; if both read the same, the sample was too small, so enlarge it, not the band.
- **Docs:** Deadnight `docs/research/bots.md` (the bands paragraph) and `game/tests/night/test_bot_bands.gd`.

---
areas: [gameplay, tests]
---
# A bot was fitted to the model by its numbers while it did something the model's player never does

2026-11-04

- **Saw:** two Rookie bots passed the first boss night in 14 of 16 nights where the balance simulator's weak team passes
  27% (Deadnight #767). Aim, reaction, think rate, shopping, ammunition, revives and grenades were each switched
  and measured for days and none moved it; the boss died in 35 s in both, but the bots took three blows to the model's
  six.
- **Cause:** every lever tried was a number of the player the model describes. The bot also had a behaviour the
  model's player does not have: the last bot up with a teammate down and the revive unsafe *kites* (a 5 m retreat
  margin, `BotRevive.SURVIVE`), and a headliner at 0.45 of walking speed never catches a kiter. The model's player
  stands. It showed in the trace of one night (`--watch=SEAT`): the notes `survive` and `retreat` at 7 m/s with the
  boss in chase for 67 of its 85 seconds and in attack for 7.
- **Fix:** list what the bot does that the model's player cannot (move, kite, dodge, revive, throw), switch each off
  for the fitted profile by a profile field (`kites_when_last`), and measure it against the same nights with the field
  on. That one field took the pass rate of two Rookies at the first boss night from 14 of 16 to 9 of 16 and the
  Kolmogorov distance of two bots from 0.58 to 0.27 (24 nights, round cap 16).
- **Docs:** [bots research, Rookie parity](https://github.com/Ryubara/deadnight/blob/main/docs/research/bots.md).

---
areas: [gameplay, tests]
---
# A bot profile took the simulator's number for a different thing, and a lever for the fit moved a band

2026-11-02

- **Saw:** four Rookie bots passed the first boss night in 16 of 16 nights where the balance simulator says 40% of weak
  four-player nights pass it (Deadnight #568). Six attempts at "make the bot worse" in the first fit (a telegraph
  read, no keep-off, a narrower view and shorter memory, a slower reaction, half the ammunition) moved nothing under
  87%.
- **Cause:** the Rookie's `telegraph_read` 0.3 was copied from the simulator's weak `read`, but they are different
  numbers: the simulator's multiplies a blow's chance to land by exp(-1.2 x read) (a quarter of the blows miss) and its
  players stand still; the bot's was the chance to make the blow out at all, and a blow it made out it stepped away
  from whole, from a boss at 0.45 of a walker's speed. A name shared across two models carried two meanings. The first
  lever that worked for the fit then moved a different band: a narrower view (80 degrees) took the Rookie's head share
  from 0.09 to 0.13, the edge of `test_bot_bands.gd`'s tolerance, found only when the suite ran after the boss-night
  numbers were already good.
- **Fix:** read what each side does with the number before copying it (here `NightSim._blow` against `BotDodge`), set
  the Rookie to never make out the telegraph, and fit the rest on 30-night runs over two seed sets. Run the bands test
  with each candidate lever **before** the 30-night runs, since a run is half an hour and the bands take five minutes;
  a lever that only the boss reads (read, weak spot) is free, one that changes what the bot sees or aims at is not (the
  head rate went to 0 to take the share back to 0.08).
- **Docs:** [Rookie and the weak boss night](https://github.com/Ryubara/deadnight/blob/main/docs/research/bots.md) and the
  [balance page's note](https://github.com/Ryubara/deadnight/blob/main/docs/research/balance-simulator.md).

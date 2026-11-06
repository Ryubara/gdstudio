---
areas: [gameplay, tests]
---
# A lone bot held two empty guns and 1 780 points and stood a boss round out for eight minutes

2026-11-06

- **Saw:** the nightly `bots-nightly` run 42205993462 broke "a round that would not end (round 5)" in 2 of 100
  `regular_1` nights (seeds 20 and 56): one bot up, holding the freeze gun and the start pistol, both at `[0, 0, 0]`,
  the headliner the last dead, CHASE for 467 s, 0 or 1 swings, 1 780 and 235 points unspent. The summary guessed that
  the crane change (#1330) emptied the freeze gun and nothing brought the bot to the ammo; the guess was half right
  and checking it by rerunning the seeds did not work (the same seed gave a different night each run).
- **Cause:** two rules of the shopping code, found by reading it against the numbers, then by a test that builds the
  state on the real server. (1) `BotEconomy.useful` feeds only guns worth at least half the best gun's damage a second:
  the freeze gun 77, the start pistol 27, so only the freeze gun was fed; no wall sells a crane prize's rounds and the
  locker "sells for the weapon in hand", which was the empty pistol, so the stand was `INF` and no buy existed. (2) With
  fewer than 150 points (three freeze rounds) the cheap start pistol (30 rounds for 40) was not offered either, so a
  broke bot with nothing to fire never earned a point again (a third stalled night found while watching, seed 55:
  105 points, crowbar in hand). Both are the bot's, not the night's: a person buys the pistol's rounds, or swaps.
- **Fix:** the locker sells for any carried gun when the gun in hand has no round (the bot swaps at the stand,
  `BotErrands._wants_swap`); a bot with no round anywhere and nothing the worthy gun's price lets it buy takes the
  cheapest rounds it can pay for; and while every gun is dry the worthy gun's rounds are bought only if they leave the
  price of the cheapest rounds (a first version without that rule still stalled a bot that spent 930 points on freeze
  rounds and ended at 30). The proof is a forced state, not a rerun: `bots_soak.tscn --give=freeze_gun
  --dry-last=POINTS` leaves each bot with the pistol and the freeze gun, empty, when a boss round is down to the
  headliner. One Regular bot, 20 nights: at 1 500 points `main` stalled 4 of 12 set-up nights and the fix 0 of 11; at
  100 points `main` 12 of 12 and the fix 0 of 11. A test on the real server (`test_bot_errand_buys.gd`) and one on the
  chooser (`test_bot_economy_dry_guns.gd`) fail on `main`.
- **Docs:** Deadnight `docs/research/bots.md` ("The third nightly run (#1346)").

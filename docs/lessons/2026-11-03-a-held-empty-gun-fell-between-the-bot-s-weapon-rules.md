---
areas: [gameplay, tests]
---
# A bot held an empty gun for minutes because no weapon rule covered "nothing here, rounds elsewhere"

2026-11-03

- **Saw:** in forty-minute bot nights on the second map a bot kited a few dead for almost five minutes with
  `shotgun [0, 0]` in hand and `smg [0, 158]` in the pocket: it never reloaded, never swapped, never struck, and the
  round did not close (Deadnight #695). The first guess (a train it never gets the gap to reload under) was wrong:
  a reload is allowed while running, and the plan never asked for one.
- **Cause:** `BotArsenal.plan` branched on the held gun's magazine and reserve and on a loaded gun elsewhere. A held gun
  with magazine 0 and reserve 0 and another gun with magazine 0 and reserve > 0 matched no branch: reload needs
  reserve in the held gun, swap needs a loaded gun or a blade, and `dry` ("no round anywhere") was false because the
  other gun's reserve counts, so the quick melee stayed off too. The suite tested each branch with the other gun
  loaded or the reserve empty everywhere, never this mix.
- **Fix:** swap to a gun that only needs its reload (the next think reloads it) and let the quick melee fill the wait
  (`Plan.unloaded`). A table test lists every held and other-gun state (magazine empty or not, reserve or not) and
  checks each one asks for something; a night test puts a train of dead behind a bot in that state and fails on the
  old plan (0 reloads, 0 kills, the bot falls). Check: a decision table over two or more inputs is tested over their
  whole product, and a stalled bot night is read for the plan's inputs (the `arms` in the trace) before a cause is
  guessed.
- **Docs:** Deadnight `docs/research/bots.md`, `BotArsenal`.

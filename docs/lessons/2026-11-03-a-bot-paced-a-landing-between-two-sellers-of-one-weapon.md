---
areas: [gameplay, tests]
---
# A bot paced a stair landing between two sellers of one weapon and bought none

2026-11-03

- **Saw:** a lone bot on the second map sometimes bought doors and ammo but no weapon in a four-minute night, and a test
  of exactly that flaked (Deadnight #821). With every link open the bot spent 40 s walking to and fro on the stair
  landing, its goal flipping between the shotgun in the side room and the shotgun upstairs every two seconds; the
  machines of #811 (tonic, re-cut) were never reached either.
- **Cause:** the pick was "the nearest seller" by flat metres each think, with no memory of the stand it was heading
  for and no weight for height. The map sells one weapon at two places, which the lot never did, and from the landing
  the two are about the same flat distance, so each step flipped the order. Only rounds had a heading (and asked for
  the walk, which counts stairs); weapons, the box, tonics and the re-cut used the plain `_nearest`. A second fault
  hid behind it: the bot counted itself arrived when it was flat-close to a stand, so under the upstairs re-cut bench it
  waited for a prompt that was a floor above and gave the item up.
- **Fix:** every seller is picked by `BotEconomy.nearest_by_walk` (walk length, a metre of height as 8 m, 6 m of credit
  for the stand it is already walking to), `BotErrands` keeps the heading for every purchase and an arrival needs the
  stand's height within 1.5 m. Table tests put a bot on the landing and step it along; a night test with every link
  open expects the shotgun in 20 s (both fail on `main`).
- **Docs:** Deadnight `docs/research/bots.md`, "Shopping at the second map's machines". Check: when a map sells one
  thing in two places, every chooser that picks "the nearest" needs a heading (hysteresis) and height, and a test that
  starts the bot midway between the two.

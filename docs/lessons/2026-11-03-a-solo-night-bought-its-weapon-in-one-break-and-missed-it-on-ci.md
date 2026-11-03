---
areas: [tests, gameplay]
---
# A solo bot night bought its weapon in one break and missed it on CI

2026-11-03

- **Saw:** the second map's solo bot night (`test_smallmap_bot_night`, seed 7) failed on CI of several unrelated
  changes with the same purchases (`ammo_pistol` 3, two doors, no weapon), passed on a rerun, and never failed on a
  developer machine: 20 seeds at frame cadences 5, 7, 9, 11, 13, 17, 23, 30 and 50 all passed here (Deadnight #827,
  #876).
- **Cause:** the bot pays for two links first, and its first weapon (the shotgun, or a crane play) comes in the break
  of round 4, at 130 to 169 s on 17 of 20 seeds (the other three bought a crane play in round 2), in a 240 s night.
  A bot starts no errand with a dead within 12 m, so the buy waits for a stretch with no dead near (every weapon
  purchase printed for seed 7, at three cadences, fell in a break or with 0 dead standing). One window with 70 s of
  margin is luck in the fight; the same kind as #817's shop test, which could not use the same fix because this
  night has to play its rounds (the windows are what it asserts).
- **Fix:** the night runs 330 s, past the breaks of rounds 5 and 6, where the bot has points for the weapon (it buys
  ammo and tonics there with over 1,000), so the weapon is bought in one of three breaks. Not reproduced on the
  machine, so the evidence is the margin, not a red test turned green.
- **Check:** a test that asks "the bot bought X by T" lists the time of the buy on many seeds first; if the earliest
  window sits within a break or two of T, lengthen the run (or give the night a long break when the rounds are not
  the point). A failure that does not reproduce on a Windows machine at any frame cadence is a margin problem until
  shown otherwise.
- **Docs:** Deadnight `game/tests/world/smallmap/test_smallmap_bot_night.gd` (`SOLO_SECONDS`); see also
  [a shop test that ran into the rounds](2026-11-03-a-shop-test-ran-into-the-rounds-and-bought-by-luck.md).

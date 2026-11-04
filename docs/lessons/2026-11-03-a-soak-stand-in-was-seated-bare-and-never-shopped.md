---
areas: [tests, gameplay]
---
# A soak's stand-in for a person was seated bare and never shopped

2026-11-03

- **Saw:** in the bots soak (`--person --bots=3`) the person stand-in's pistol read 0/0 for rounds on end with
  thousands of points in hand: 807 of 1012 s up were dry on one lot night (seed 4), 931 of 1147 s on another (seed 31),
  and a boss round with it dry took 120 s of tail where one with a gun took 50 s (Deadnight #998, found in #950).
- **Cause:** the real night builds its `Autopilot` and then fills it from the lot and the rules (shop spots, ammo and
  weapon prices, doors, re-cut, tonic, breaches, fuel); `SeatedNight.seat(..., legacy)` built the same class with none of
  that. Its brain was fine, but with no spot to walk to it could only buy at a locker it happened to stand beside. The
  second construction path was written once, passed its tests, and nobody read the soak's person as a person.
- **Fix:** one `AutopilotSetup.configure(autopilot, world, tuning, night_tuning)` called by both; the soak report
  carries the person's up, dry and longest dry seconds (`people`), and a suite seats the stand-in dry and asks that it
  buys rounds and a wall weapon. Dry fell from 64.5% of the person's time to 4.2% on the lot (11 nights); the boss
  round's tail with a person from 63 s to 47 s. Once it could shop, watching the seats that stayed dry found three more
  faults of the same stand-in: it swapped between two empty guns, it never bought rounds for a gun it had put away for a
  blade, and it counted a locker one floor up as reached from underneath.
- **Docs:** Deadnight `docs/research/bots.md`, "The soak's person shops (#998)". Check for next time: when a test
  builds a thing the game also builds, it calls the game's own setup; a stand-in's report says what it did (spent, dry
  seconds), so a stand-in that does nothing shows in the numbers it skews.

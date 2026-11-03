---
areas: [tests, gameplay]
---
# A shop test said "in the break" and ran into the rounds, so what it bought followed where the dead stood

2026-11-03

- **Saw:** a bot-shop suite (a rich bot buys the tonic, the re-cut and a perk on the second map, 240 s, seat 3) passed on
  `main` and locally but failed on CI of an unrelated change to how the dead stand at the windows: `tonic_hearty` bought,
  `upgrade_weapon` and the perks never (Deadnight #817, after #844). Stepping a frame every 7 ticks instead of every 30
  was enough to reproduce it here; `main` passed with 7, 13 and 50.
- **Cause:** the suite's header spoke of "the break", but the first break lasts about 12 s and the 240 s ran through
  four rounds. A bot begins no errand with a dead within 12 m, and the bench is a long walk upstairs, so the trip happened
  only in the stretch of a round where every dead happened to be far (tick 4504 on `main`, tick 10952, after the fourth
  round, with the change). Both were luck; any change to where the dead stop or the pace of the physics frames moved it.
- **Fix:** a test about errands in a break gives the night a break longer than the run (`intro_seconds` and
  `break_seconds` of the rounds tuning, as the shop capture does): no dead on the lot, the same assertions, and every
  buy done by tick 5800 with 7, 13, 30 and 50 ticks between frames.
- **Check:** when a suite is about what a bot does in a calm, print the phase and the dead near at each purchase; if a
  purchase falls in a round, the test measures the fight, not the errand. Run a bot suite with two frame cadences before
  trusting a green.
- **Docs:** Deadnight `game/tests/world/smallmap/test_smallmap_bot_machines.gd` (`BREAK_SECONDS`).

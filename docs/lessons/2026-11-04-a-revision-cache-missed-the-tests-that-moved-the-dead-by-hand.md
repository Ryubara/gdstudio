---
areas: [gameplay, tests, godot]
---
# A cache keyed on a revision missed the tests that moved the dead by hand

2026-11-04

- **Saw:** after the server's target list, the grenade and combat tables and the frame's zombie bytes were built once for
  each `ZombieSim.revision` instead of every tick (Deadnight #931), four night suites failed (`test_night_blood`,
  `test_night_melee`, `test_night_quick_melee`, `test_shot_on_crosshair`): a rig that sets `body.position = spot` and
  shoots in the same tick missed on every tick the sim did not step.
- **Cause:** the revision moves in the sim's own methods and its 30 Hz step. About sixty places in the tests and tools write
  a `ZombieBody` field directly (`position`, `yaw`, `mode`, `enter()`); the old code rebuilt the list every tick, so a hand
  write showed at once, and the new one showed it at the next step.
- **Fix:** a public `ZombieSim.touch()` and a call after every hand write that a same-tick shot depends on (the rigs
  `SeatedNight` and `ShotRig`, and the four suites). Before caching anything on a version number, grep every writer
  of what the cache is built from (`rg "\.(position|yaw|mode)\s*=[^=]"` over `game/`, tests and tools included),
  give each one the bump, and run the suites that pin things in place (`tests/night`) as well as the new ones.
- **Docs:** [Performance review](../engines/godot/performance-review.md) (the checklist line on caches) and the game's
  `docs/research/crowd-budget.md`, "The server's crowd lists, once a step".

---
areas: [tests, gameplay]
---
# A soak that had to see a throw failed on the runner when the bots threw less

2026-11-03

- **Saw:** `test_bot_grenade_soak` asserted "the bots threw at least once" over two 90 s free nights. It passed
  on the machine and failed in CI (`godot (n)` red, `build-ok` red): the bots' grenade choice had become
  stricter, so a free night threw 0 to 1 times.
- **Cause:** one test did two jobs, proving the bots still throw and proving no one is hurt. The first depended
  on how often a free night happens to offer a throw, which changes with the bots' rules and the runner.
- **Fix:** a scripted night proves the throw (a bot, a pack that stands ten metres off, a person clear of it;
  the longest wait is 10 s) and the free soak only asserts the safety limit and prints its count. Measure the
  person by the player id that is not the bot, not by seat 1.
- **Docs:** the header of `game/tests/night/test_bot_grenade_soak.gd` in the Deadnight repository says so.

---
areas: [gameplay, tests]
---
# Bots with a loaded ray gun stood beside a zombie they would not shoot

2026-11-06

- **Saw:** the nightly bot soak (Deadnight #1319) broke its "idle with a zombie in view over 5 s" gate in 64 of 1200
  nights on 2026-11-05 (68 of 1170 on 2026-11-04). In 58 of the 64 (62 of the 68) every idle bot held a loaded ray gun
  (`ammo 8`, `reserve 40`, note `fight` or `choke`) with the zombie at 1.3 to 1.4 m: 81 samples, the farthest 2.2 m.
- **Cause:** `BotMotor._trigger` does not fire a weapon that hurts its shooter (`self_splash_share`) inside its own splash
  (the ray gun's 3 m), and the quick melee was asked only of a bot with nothing to fire (`plan.dry or plan.unloaded`).
  A loaded ray gun with a zombie at the zombie's own reach (1.4 m) had neither a shot nor a blow. The ray gun came in
  with #823 the day before the soak's first nightly run; its row in `bot_coverage.gd` read "fires like the pistol", true
  only outside 3 m, and no test put a zombie close to a bot holding it.
- **Fix:** the motor strikes with the quick melee when the gun in hand has a round, a zombie is in reach and the gun is
  held back by its own splash (`BotMotor._gun_held_back_by_its_splash`), with a test that fails without it.
- **Check next time:** when a weapon gets a rule in the bot motor (a refusal to fire, a minimum range, a charge), the
  test puts the zombie at the reach of the dead (1.4 m) and asserts the bot does *something* (a shot, a blow or a step
  away), and the soak's `idle_samples` are read by weapon before any gate is called the bots' fault
  (the same lesson as `2026-11-03-a-bot-stood-with-an-empty-gun-and-rounds-in-another.md`: 58 of 64 nights were one cause).
- **Docs:** Deadnight's `docs/research/bots.md` ("The first two nightly runs").

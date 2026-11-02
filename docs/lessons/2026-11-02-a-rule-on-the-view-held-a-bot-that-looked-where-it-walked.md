---
areas: [gameplay, tests]
---
# A rule on the view held a bot that looked where it walked

2026-11-02

- **Saw:** once the shot waited for the body to face the view (Deadnight #488), a bot-driven test failed on an
  unrelated budget: `test_kill_allocations.gd` held 54 to 66 objects against a slack of 48, and the fight took 574
  frames for 14 kills against `main`'s 464.
- **Cause:** the bot sent its walking direction as the view (`motion.yaw`) and the target as the ray (`dir`), so the
  new rule held its shots at every bend of its path. Once it looked along its aim (#511), it still chose targets with
  its barrel placed along its walking heading, so its view flipped between zombies and the body chased each one (515
  frames, 77 objects held). The research page had said "bots are unaffected" without a bot run.
- **Fix:** a bot sends a person's command. It looks where it acts, moves as a stick push under that view, and judges
  what it can hit from where the body will be when it fires (the barrel along the heading to the target): 395 frames,
  14 held. When a rule starts reading a command field, run every suite that drives a bot, and say "bots are
  unaffected" only after a run.
- **Docs:** Deadnight `docs/research/hip-fire.md` ("The bot had to look where it shoots") and `docs/research/bots.md`
  (gap 1).

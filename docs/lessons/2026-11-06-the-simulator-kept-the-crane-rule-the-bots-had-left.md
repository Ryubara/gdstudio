---
areas: [gameplay, tests]
---
# The simulator's shoppers kept the crane rule the bots had just changed

2026-11-06

- **Saw:** after Deadnight #1330 changed when a bot pays for a crane play (`BotProfile.crane_min_odds`, a pass lock-out),
  the bots made 21 plays in 16 bot-nights where they had made 51, and the balance simulator's shoppers made exactly the
  same as before: they still paid on any one prize worth taking. The crane's price was tuned against the simulator, and
  the parity reads (a bot cell beside the simulator's matching cell: median round, Kolmogorov distance, spend ratio)
  compare the two. Deadnight #1331.
- **Cause:** the bots' shopping was written to follow the simulator's players (`BotEconomy` says so in its header),
  so the same rule lived twice, once in `NightSim._crane_can_pay_off` and once in `BotEconomy._crane`. #1330 fixed the
  one the maintainer had seen, in the bots, and the page it left (`mystery-box.md`) said the simulator "was left as it
  was", an issue of its own. Nothing tied the two together, so no test could notice the gap.
- **Fix:** Deadnight #1331. The rule is one class (`CraneOdds`: the share of the draw a shopper would take, and the
  least share worth a play) and the lock-out another (`CranePass`); the bots and `NightSim` both call them. A suite
  (`test_sim_crane_shopper.gd`) checks that the simulator's share of the draw equals the bots' for every hand and round
  of a grid. Measured with 2,000 simulated nights a cell before and after, not ten.
- **Check next time:** when you change a rule a bot copies from the simulator (or the other way round), look for its
  twin first (`grep` the rule's name in `game/tools/balance/` and `game/gameplay/bots/`) and move the rule to one place
  both read, in the same pull request; a rule that has to be copied gets a test that feeds both the same cases. When a
  fix is left "for another issue", the issue is filed with the numbers of the gap it opens, because the parity reads
  see it before anyone does.
- **Docs:** Deadnight's `docs/research/mystery-box.md`, section "The simulator's shoppers at the crane (#1331)".

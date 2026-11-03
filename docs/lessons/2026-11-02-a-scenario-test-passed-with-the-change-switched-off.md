---
areas: [tests, gameplay]
---
# A scenario test for a bot rule passed with the rule switched off

2026-11-02

- **Saw:** The test for bots coming back to an unsafe body (Deadnight #673) passed with the new staging rule on and,
  after a first fix, also with it off: both runs raised the bodies at the same second (42.45 s). Only a "a bot staged"
  flag differed, so it proved nothing about the outcome. A 24-seed A/B soak (22 vs 26 bleed-outs in about 1100 downs)
  agreed.
- **Cause:** The scenario was built from the story ("a pack by two bodies, bots far away") and never run against the
  old behaviour. The far bots came back on their own (the verdict turned safe as the bots shot the pack down), so the
  failure it was meant to reproduce, arriving too late, never happened.
- **Fix:** Before building on a scenario, run it with the change off (a static switch such as `BotRevive.stage_on`) and
  see it fail on the outcome (a body that bleeds out), not on a flag of the new code. If it cannot be made to fail,
  the cause is not found yet: report that instead of shipping the change. Keep the switches for the A/B soak.
- **Docs:** [bots research](https://github.com/Ryubara/deadnight/blob/main/docs/research/bots.md), section "Revives".

---
areas: [gameplay, tests]
---
# The dodge of a bot read 0.7 when the swings that came due were counted, 0.3 when they were all counted

2026-11-02

- **Saw:** the share of zombie swings that did not hurt a bot (the simulator's `dodge`) was 0.6 to 0.85 for a bot
  that never moved, because most swings never ran their course.
- **Cause:** every hit on a zombie staggers it and takes its swing away (`ZombieBrain.stagger`); a bot that shoots a
  zombie at arm's length is not dodging, its gun is. The same holds for a boss: a test that put the headliner in front of
  a shooting bot passed vacuously, since the bot's shots kept it staggered.
- **Fix:** count only the swings that reached the moment of their blow (`zombie.struck`) and the blows that landed
  (`CombatProbe.dodge`); a boss test holds the bot's trigger (`SeatedNight.hold_fire`), counts only the swings that ran
  their course, and has a control (a bot with a 2.5 s reaction) that must be hit.
- **Docs:** [bots research page, phase 3](https://github.com/Ryubara/deadnight/blob/main/docs/research/bots.md).

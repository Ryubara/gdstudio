---
areas: [general, godot, tests]
---
# Nobody knew the game's limits until a maintainer lagged

2026-11-03

- **Saw:** a maintainer at round 12, triple intensity, three bots, said the game lags and that it "should've been done
  during the start" (Deadnight #906). The game had a web crowd study and a phone profile, but no run of its own worst
  night, no per-system limits and no check that a count or a cost had not grown.
- **Cause:** performance was measured per question (a phone, a bare crowd of 40 to 120) and never as a standing
  worst case. Nobody asked what the shipped settings together allow: with a bot in the room the crowd ceiling counted the
  hosted bot as a browser (40 dead on a desktop, 99 when the bot said it was not). And the machine was never quiet, so a
  frame time measured on it ranged 8 to 115 ms for the same code, which hid whatever the game itself cost.
- **Fix:** a sampler (a row a second of engine counts and labelled script times), arguments that start the autopilot at
  round R with N bots at Kx, a budget file with counts held tight and time held as a ratio of a calibration loop, a CI
  step that fails when either is over, and a limits page per game.
- **Docs:** [Performance budgets](../godot/performance-budgets.md); the line on
  [what to plan from the start](../research/plan-from-the-start.md#performance). Check: name the worst-case combination
  of settings in the first playable night, run it from one command, and read its limits off a page.

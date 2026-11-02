# A crowd cap measured in the browser became the desktop cap

2026-11-02

- **Saw:** the maintainer asked for over 100 zombies at once on desktop (RTX 5080, 9800X3D). Deadnight held every
  platform to 40 alive: `ZombieTuning.hard_cap` and `RoundTuning.alive_cap_ceiling`, pinned equal by a test, and the
  host's match settings clamped to the same number.
- **Cause:** the ceiling came from a careful web measurement (deadnight #315, `docs/research/crowd-budget.md`), the
  weakest platform, and was written as one constant. Nobody measured the native client, the headless server or the
  network at larger crowds, so the browser's limit silently became the game's.
- **Fix:** split the cap by platform and measure each budget on its own: client render and animation, server tick per
  agent, snapshot bytes per player (deadnight #453). A room takes the ceiling of its lowest client platform.
- **Docs:** [What the maintainer caught](../research/maintainer-corrections.md).

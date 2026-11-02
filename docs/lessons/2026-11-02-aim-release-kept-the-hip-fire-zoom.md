---
areas: [camera, process]
---
# Releasing aim after a shot kept the hip-fire zoom

2026-11-02

- **Saw:** aim, shoot, let go of aim: the view stayed zoomed for the hip-fire hold and then zoomed out, as if the shot
  had been fired from the hip (the maintainer, Deadnight #428).
- **Cause:** aim and hip fire share one output, the aim weight. It was held while `aiming or fire_age < hip_fire_hold`,
  and every shot reset `fire_age`, whether it was fired from the hip or while aiming.
- **Fix:** only a shot fired from the hip starts the hold (Deadnight #433); tests walk every transition between the two
  states (aim, shoot, release; hip fire, aim, release), not each state alone.
- **Docs:** [What the maintainer caught](../research/maintainer-corrections.md).

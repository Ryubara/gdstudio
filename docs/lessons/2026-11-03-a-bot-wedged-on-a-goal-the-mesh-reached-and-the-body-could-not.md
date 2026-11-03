---
areas: [gameplay, tests]
---
# A bot stood against the fence for up to 11 s: the mesh reached a goal the body could not

2026-11-03

- **Saw:** a roaming bot with a goal past the west fence stood against it, climbing the stuck ladder again and again
  (Deadnight #677). The probe showed no error: the goal was "on the mesh" and the path to it was fine.
- **Cause:** the walking mesh runs through each breach's gap into the pocket the dead come from, and the breach's boards
  are on a physics layer of their own (players only), which the bots' `sight` ray (the shots' layer) does not see. The
  path model said yes, the body said no. The earlier tests walked goals the mesh does not reach, never one that it does
  and the body cannot.
- **Fix:** a new path is checked as the body walks it (a ray along each segment with the walls and the boards): stopped
  with more than a metre left, the goal is marked unreachable at once; stopped with less, the path is cut short of the
  thing. A probe sends the bot to each pocket and to the fence's edge and reads the longest stuck episode (it was 5 to
  11 s; the test fails on `main`).
- **Docs:** Deadnight `docs/research/bots.md`, "Goals the body cannot reach". Check: when a bot's idea of the world (mesh,
  sight, a believed list) is built from one source and the body is stopped by another (a physics layer, a gate, a
  carved door), ask both before the bot walks, and test a goal where they disagree.

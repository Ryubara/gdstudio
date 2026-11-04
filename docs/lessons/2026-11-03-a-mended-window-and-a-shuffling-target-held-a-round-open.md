---
areas: [gameplay, tests]
---
# A mended window and a shuffling target each held a round open for minutes

2026-11-03

- **Saw:** the performance sweep's 30-minute solo nights (the autopilot and three bots) had rounds with one to three dead
  standing for a minute or more, once seven (Deadnight #950). The bots soak's 3-minute stall gate and a new
  "seconds down to the last three" count (`SoakWatch`, `tail_longest`) found two kinds in a day of nights.
- **Cause:** (1) a dead stood at a window's jamb, out of the person's line of fire, tearing a board in 1.2 s while the
  person, who mends when there is nothing to shoot, put one back every 1.0 s: boards at 5 for 190 s. (2) six dead
  chased a person who hugged two parked cars; the target was off the walking mesh, `map_get_path` snaps it to the
  nearest mesh point, and that point flips from one side of the car to the other as the person moves a metre (the two
  routes were 10 m and 29 m): every repath turned the dead round.
- **Fix:** a rule with a restoring side needs a limit (a dead that has pulled at one window for 30 s bursts the boards),
  a route is kept while its end is still near the target (`ZombieSim._keeps_its_route`), and the rules rescue what
  nothing else catches (the last dead, 45 s with nothing done to them, rise nearer the people). A seated-night test puts
  the person and the dead where the soak found them (the first version stood the person at the window's middle, shot the
  dead at once and passed on `main` too: use the log's own coordinates).
- **Docs:** Deadnight `docs/research/zombies.md`, "A round that waits on its last dead (#950)"; check: a loop in which one
  actor undoes another's work (mend and tear, heal and hurt, lock and pick) has a time limit and a test that runs past it.

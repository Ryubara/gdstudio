---
areas: [gameplay, tests]
---
# The stuck detector flagged bots that were turning round, and let a bot that shuffled go free

2026-11-02

- **Saw:** the first twenty-minute-style soak (Deadnight #226) had bots "stuck" 4 to 16% of their walking time in
  episodes of a second or less, with nothing in the way; and a bot pressed against a gap the mesh did not know shut
  kept restarting its ladder every second and never got past the first rung.
- **Cause:** (1) progress was measured along the new heading: a bot sprinting at 7 m/s that is given a goal behind it
  brakes and swings round for half a second, and the body's progress along the new way is zero or negative meanwhile.
  (2) Recovery was "a window of half a second with progress": the sidestep of the first rung moves 0.9 m along the wall,
  so every window on the way out showed progress and the way back showed none.
- **Fix:** progress on a path is the path left to walk (the same path as last tick; a bend or a turn does not count
  against the bot), a new heading more than 85 degrees off the last gives the body 0.6 s of grace, and an episode ends
  only after the bot has gained a metre of net progress since it began. A unit test feeds the detector a trace of
  shuffling back and forth and asserts it stays stuck, and one of a U-turn asserts it does not.
- **Docs:** Deadnight `docs/research/bots.md` (Stuck detection, Built in phase 2).

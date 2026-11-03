---
areas: [tests, gameplay]
---
# A test body teleported against a wall was pushed off the point the test judged

2026-11-03

- **Saw:** a press test teleported a player to a point 0.7 m behind a door's slab where the prompt was empty, pressed use,
  and the door was bought: "a press changed the night". Another fingerprint kept changing because it included the
  generator's fuel, which drains every tick.
- **Cause:** the body's capsule overlapped the slab, so the first physics step pushed it out to the door's front, and the
  server judged the press from there, not from the point the test had checked. The fuel was real state that moves with
  time, not something a press changed.
- **Fix:** sample standing points with a body's room clear (eight short rays of 0.5 m at knee height), check after the
  press ticks that the body stayed within 0.15 m of the point and skip the press where it did not, and fingerprint only
  what a press can change (points, weapons, doors, circuits, boards, the crane), never a clock.
- **Docs:** Deadnight `docs/research/use-reach.md#findings`. Check for next time: a test that puts a body next to
  geometry proves where the body ended, not where it was put.

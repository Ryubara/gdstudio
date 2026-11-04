---
areas: [tests, godot]
---
# A hand-ticked body cost ten times more than it had to until a physics step had run

2026-11-04

- **Saw:** a night of four hand-ticked bodies ran 3.7 ms a tick, 2.4 ms of it in `move_and_slide`; `PlayerSimulation.simulate`
  of a body standing still took 0.24 ms. Adding one `await get_tree().physics_frame` after the night was built made it 1.6
  ms a tick and 0.02 ms a call, with the same shots, hits and blows (Deadnight #1017: the bot suites halved).
- **Cause:** the build awaited one `physics_frame`, which is emitted at the start of an iteration, before that
  iteration's step; the bodies it had just added were still outside the physics server's index, and a body that is not
  indexed is slow to move in and query, not wrong. A second await returns after the step.
- **Also saw:** with several bodies it is not the same night. The unindexed bodies had passed through each other and
  through grenade casts; with them indexed the grenade soak failed on CI (a bot took 25.5 % of its health from its own
  grenade, limit 10 %) and 2 of 20 seeds did locally, where none had. A bot hazard the old fixture hid, fixed by a
  parallel pull request (bots throwing into posts at their own feet). Run a multi-body suite over twenty seeds before
  and after the change, not once.
- **Fix:** `SeatedNight.start` awaits two physics frames. After building a room or adding a body or collider: two frames,
  then tick by hand. Not every suite may take the frame as it is: the midway fence sweep (a body added after the lot
  settled) landed at different places with it (the same search, other floats), so it was left as calibrated and the
  frame is a calibration step for a sweep, not a free speed-up.
- **Check next time:** time `simulate` for one body standing still (about 0.02 ms indexed) before reading a profile of
  a hand-ticked suite; a 10x figure means the bodies are not indexed yet.
- **Docs:** [Test speed](../godot/test-speed.md#what-hand-stepping-needs).

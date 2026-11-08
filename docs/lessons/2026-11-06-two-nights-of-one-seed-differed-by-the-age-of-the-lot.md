---
areas: [tests, gameplay, godot]
---
# Two runs of one commit, seed and command differed by the age of the lot at the first tick

2026-11-06

- **Saw:** Deadnight's 30 minute autopilot night at a fixed step (`--fixed-fps 60`, headless, one seed) gave round 17
  with 296 kills and round 11 with 116 when run twice at once (issue #1350), and the nightly's round count moved by
  several rounds a commit. The first numbers to differ were load-time counts (nodes, resources, audio), which pointed at
  the audio theory; three nights of 600 s with those counts differing were identical in every position for 36 000 ticks.
- **Cause:** the lot waited for its navigation map a number of physics frames (3 to 9) that changed from run to run, so
  the lot was 10, 11 or 12 physics frames old at the night's first tick, and until a lot is about 17 frames old the
  physics engine plays a body's ground contacts differently by its age: one bot stood 0.9 mm up or on the floor, the
  dead chased it, 350 ticks later their places differed, then the paths, the points and the rules' dice. The first thing
  that differed was one number of one body, not the sound or the clock.
- **Fix:** write a per-tick trace of hashes by part of the night (the dead, the bodies, the dice, the paths) and compare
  two runs for the first differing tick and column (`autopilot_run` `trace=PATH`), then repeat the first differing
  quantity with one variable moved by hand (a delay of N frames: identical inside two groups). The build now returns
  only when the lot is `LOT_MIN_FRAMES` old, whatever the navigation map did, and a test builds nights 0 and 3 frames
  apart and checks every place to the last bit. Do not conclude "physics bodies are not repeatable" from a difference
  between two worlds until the two worlds are the same age at the first tick (the lesson of 2026-11-02 saw the hair and
  the tied routes; both may be this).
- **Docs:** [Fixed-step repeatability](../engines/godot/fixed-step-repeatability.md); Deadnight `docs/research/performance.md`,
  "Why two runs of one night differ (#1350)".

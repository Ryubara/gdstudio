---
areas: [web, ci]
---
# A faster menu failed a gate that divides the night's load by the menu's

2026-11-04

- **Saw:** the web job failed three times on the same pull request (8.64x, 11.15x and 6.6x, limit 5.5x) with "the
  night took 69.9 / 89.2 / 54.4 s to load", and an unchanged night path. The change moved the menu stage's viewport
  and multisampling, so it looked like the stage cost the night something.
- **Cause:** it did not. The night's loading was in the range of `main`'s (42 to 66 s on the 11 recent runs of other
  changes; the same warm-up steps, the same 191 GL programs, the same 15 to 27 s "Lighting the lot" that `main` shows
  on a slow runner). What moved was the other term: a frame trace of the page coming up (`first_use.py`) shows six
  frames of about 450 ms in the old build that the new one does not have (the stage's 1080p redraws as its container
  was laid out; several seconds on CI), and the menu loaded in 6.8 to 8.2 s where `main` takes 9 to 18 s. The gate is
  night over menu, so a quicker menu raises it with the night unchanged. Divided by the idle menu's mean frame (a
  stand-in for the runner's speed), the night is 0.4 to 0.9 s per ms on the pull request and 0.4 to 0.8 on `main`; the
  pull request's idle frames were slower, 99 to 131 ms against 59 to 102 on `main`, which a still stage should not
  cause and is not explained. A local A/B (the build of `main` and of the branch, interleaved, on all cores, 2 and 1)
  showed no night difference outside the machine's noise, so a hunt for a cost in the night path (shrinking the
  covered stage's multisample buffer was tried and dropped) would have changed code that was not the cause.
- **Fix:** none in the game. Before treating a red ratio as a regression: line up both terms of the ratio against
  `main`'s last runs (`gh run view <id> --log`, the `night_load` block and `menu_frames`), divide by a number the
  change is unlikely to move, and replay it locally with the two builds interleaved. When a change speeds up the term
  the gate divides by, the gate's calibration is what is out of date (a maintainer's decision, never a quiet raise of
  the limit in the same pull request).
- **Docs:** [Web export: testing the browser build](../godot/web-export.md).

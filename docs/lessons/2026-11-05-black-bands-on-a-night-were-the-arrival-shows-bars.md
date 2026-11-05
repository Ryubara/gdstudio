---
areas: [tests, godot-ui]
---
# Black bands across a night's capture were the arrival show's own bars, caught in the 0.45 s after it

2026-11-05

- **Saw:** two captures of a night (`night_phone_capture`, 1688 x 780) had a black band 58 px high at the top and bottom
  with the HUD over it; a 1536 x 864 capture had none. The issue guessed a letterbox, a Movie Maker window or a 3D
  view wider than 16:9, and a search of the UI code for a letterbox found nothing.
- **Cause:** none of those. The bars are `ArrivalCutscene.BAR_SHARE` (0.075 x 780 = 58.5 px), deliberate, in a
  `CanvasLayer` over the whole helicopter drop and the 0.45 s after it (`SPAWN_IN_SECONDS`, stepped by the physics clock),
  while the HUD is already back (`NightScreen._on_arrival_ended`). The capture awaited `arrival_ended` and then a
  timer of process time, so a loaded machine could take the shot inside that 0.45 s. A web probe (`?probe`) turns the
  show off, so the probe's night had no bands; `?probe&arrival` plays it and shows them.
- **Fix:** wait for the thing that draws it to be gone (`is_instance_valid(night.arrival_show)` over physics frames), not
  for a time. Check for next time: an unexplained black or coloured band is found by its size first (58.5 / 780 =
  0.075 named the constant in one step), then by `grep` for that constant, before any guess about the window or the
  camera; and a capture of "the night in play" waits for every show and fade of the start to be over.
- **Docs:** the game's `docs/design/arrival.md` (the bars are deliberate and last as long as the show).

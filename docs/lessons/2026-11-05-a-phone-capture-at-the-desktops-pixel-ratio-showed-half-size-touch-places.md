---
areas: [godot-ui, tests]
---
# A phone capture at the desktop's pixel ratio showed touch places half the size

2026-11-05

- **Saw:** the first capture of Deadnight's phone weapon places (#1280) at a 1688 x 780 window had places 55 px wide,
  22 CSS px, when the code asked for a fingertip (44 CSS px, `MenuScale.tap_units`).
- **Cause:** `tap_units` converts CSS px to units with the page's pixel ratio, and a capture window on a PC reports 1,
  where the phone's page has 2. The code was right; the capture asked it for a desktop's fingertip. A run on a desktop
  window with `TouchMode.device_is_touch` set looks like a phone and is not one.
- **Fix:** a capture of anything sized in CSS px sets `MenuScale.pixel_ratio = 2.0` first (`weapon_slots_tour.gd
  --ratio=`), and the size is read in CSS px from the result (the web probe's `touch_zones`), not off the picture.
- **Docs:** [Mobile controls](https://github.com/Ryubara/deadnight/blob/main/docs/research/mobile-controls.md) in
  Deadnight, "Weapons and grenades on the HUD (#1280)".

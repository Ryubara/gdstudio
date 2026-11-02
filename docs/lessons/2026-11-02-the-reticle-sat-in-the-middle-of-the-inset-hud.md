---
areas: [godot-ui, camera, input, tests]
---
# The reticle was drawn in the middle of the inset HUD, not of the screen

2026-11-02

- **Saw:** "Played it on website on iOS. Whenever I was shooting the bullets we're not landing where my crosshair was.
  A recent update we made might've broken it." The suspects (#572 hip aim, #582, #562, #470) were all clean: a test
  that fires the real shot at a wall across the reticle passed on `main` for the mouse and for touch, hip and aimed,
  close and far, until the phone's safe area was given.
- **Cause:** the night screen insets the whole HUD to the safe area (notch, rounded corners, home bar), and the
  reticle, hit markers, damage numbers and world markers were children that filled the HUD, so they were centred on the
  inset rectangle. An iPhone held sideways has insets of (59, 0, 59, 21) CSS pixels: the home bar under the picture
  and nothing above it. The reticle sat 14.5 canvas units (1.8 degrees at the hip) above the middle of the screen, where
  the camera looks and the shot goes. It dates from the touch layer (#279), not from a recent change.
- **Fix (Deadnight #601):** `Hud.set_safe_insets` keeps the cards inside the safe area and the overlays that are the
  screen itself (reticle, hit marker, damage, revive, world markers) at the full screen.
  `test_shot_on_crosshair.gd` fires through the trigger, the tick and the server and compares the shot's end,
  projected through the camera, with the reticle's drawn centre; `tools/web_smoke/shot_on_crosshair.py` does it with
  real touches at 844 x 390 (the 540 unit canvas).
- **General:** anything drawn "at the centre of the screen" for aiming belongs to the viewport (or the camera), never
  to a container that is inset, scaled or mirrored. Test aim end to end (where the shot lands against where the reticle
  is drawn), not each half against its own source, and with the odd inputs a real device has: uneven insets, the phone
  canvas, a finger. Every earlier aim test compared the shot with the camera and ran with zero insets.
- **Docs:** [What the maintainer caught](../research/maintainer-corrections.md).

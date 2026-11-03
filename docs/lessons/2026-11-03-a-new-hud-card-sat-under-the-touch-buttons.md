---
areas: [godot-ui, input, tests]
---
# A new HUD card sat under the phone's Fire and Melee buttons, and every test passed

2026-11-03

- **Saw:** the weapon slot strip (Deadnight #682) was above the ammo card, bottom right. All HUD layout, grid and touch
  tests were green; the first capture of the night on a phone showed the strip under the Fire and Melee buttons.
- **Cause:** `test_touch_layout` checks the buttons against a fixed list of HUD cards (`KEPT_PARTS`); a part added
  later is not on it, and the layout tests only look at parts against parts, not against the touch circles. The right
  thumb's corner is full by design.
- **Fix:** a new HUD part goes into `KEPT_PARTS` in the same change, and its place with the touch layer up is decided
  then (here the strip moves under the health card, `Hud.touch_layout`). Capture the part on a phone (2340 x 1080 and
  844 x 390 with the touch controls) before calling the layout done: the capture also showed the stick's resting ring
  over the card above, and a world marker over a card in the bottom middle, which no rectangle test sees.
- **Docs:** Deadnight `docs/design/touch-controls.md`, `docs/research/hud.md` ("Weapon slots").

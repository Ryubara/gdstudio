---
areas: [input, godot-ui, tests]
---
# A touch layer that was down lost every finger still on the screen when it came back

2026-11-06

- **Saw:** Deadnight #1320 found that a finger landing during the helicopter drop (the touch layer is down) turned
  nothing once the layer was up, and the review called it acceptable; #1329 guessed a thumb resting through the drop
  has no look and no stick until it lifts. Tested: it has none. 10 drags of 20 units on free ground turned 0.0 mouse
  pixels, a stick finger walked 0.0, and the same two cases pass once the layer takes the finger in.
- **Cause:** an input layer that returns early from `_input` while it is off only learns of a touch by its press. A
  finger that goes down (or stays down) across the off period has no entry when the layer is on again, so its drags
  are dropped for the rest of its life: `_touch_drag` finds no role for the index. Godot has no query for "which
  fingers are down". The same hole was open for a finger down when the layer went off (a pause under a thumb).
- **Fix:** keep the fingers while off, from the events themselves (press adds, drag moves, lift erases, plus the ones
  the layer was reading when it went off) and take them in when it is on again: the stick's zone makes a stick from
  where the finger is, anything else a look finger, none presses a button and none is a tap. A GdUnit4 test that
  presses with the layer off, turns it on and drags, with the lift-in-the-dark and fresh-tap cases beside it.
- **Check for next time:** any layer, screen or mode that stops reading input and starts again must say what happens to
  a pointer that is down across the gap, and have a test with the press before the gap and the drag after it. Do not
  call a lost finger "acceptable" without running it: the guess about the player was right here, but only the run
  said how much was lost.
- **Docs:** Deadnight `docs/design/touch-audit.md` ("A finger held through the drop").

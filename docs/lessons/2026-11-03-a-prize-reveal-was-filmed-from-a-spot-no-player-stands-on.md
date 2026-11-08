---
areas: [camera, tests]
---
# A prize reveal was filmed from a spot no player stands on

2026-11-03

- **Saw:** "It's difficult to see which weapon got selected at times" (Deadnight #830): from the crane's marker the
  prize floated at the top edge of a level shoulder view, end on half of each turn, washed by the beam behind it.
- **Cause:** its only capture stood the player 1.6 m back and 1.2 m aside, pitched down "so the whole crane is in
  frame"; nothing was filmed or measured from where the use prompt appears, with the player's own body in the frame.
- **Fix:** the prize slides out on a lit board at the camera's eye height (its bottom over the hair), side on; a test
  projects every prize and the Soldier into a 1920 x 1080 view of the resting camera on the marker (whole on screen,
  10 % of the width at least, 10 % behind the body at most), and fails with the board at grab height (79-98 % hidden).
- **Docs:** [Measuring an effect on the screen](../engines/godot/measuring-effects-on-screen.md#a-reveal-from-where-the-player-stands).

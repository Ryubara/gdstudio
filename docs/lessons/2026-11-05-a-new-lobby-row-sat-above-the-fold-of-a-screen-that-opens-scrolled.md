---
areas: [godot-ui, tests]
---
# A new lobby row sat above the fold of a screen that opens scrolled to its button

2026-11-05

- **Saw:** Deadnight #1186's Private switch was first put under the invite link, above the seats. Every test passed
  (the row existed, was a tap target high, fitted). The first capture of the host's lobby, at 1920 x 1080 and on a
  1169 x 540 phone canvas, did not show the row at all: its rect was at y -373 and -913.
- **Cause:** the lobby's scrolling column has `follow_focus` and the screen focuses Start on entry, so it opens
  scrolled to the bottom; a row above eight seats and the rules is off screen until the host scrolls up. "Visible" in a
  test means `is_visible_in_tree`, not "in the part of the scroll the player sees".
- **Fix:** the row goes after the rules, with Start (the last thing set before the button). A capture script prints the
  control's global rect with each still, so a row outside the canvas is a number, not something to notice by eye. Check
  for next time: for a control added to a screen that scrolls, read its rect in the first frame the player sees (after
  the initial focus), and put anything a host must see next to the button that screen focuses.
- **Docs:** [UI controls](../godot/ui-controls.md), Deadnight `docs/design/lobby.md`.

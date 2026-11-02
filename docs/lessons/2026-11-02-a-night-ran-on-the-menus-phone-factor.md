---
areas: [godot-ui, input, web]
---
# A night ran on the menu's phone factor

2026-11-02

- **Saw:** on a phone-sized page the touch SIDE button was off the top and AIM, RELOAD and SWAP were clipped, and the
  HUD's cards took a third of the screen. A fix by shrinking the layout to the short canvas could not work either:
  the ammo card alone covered Fire, Jump and Interact there.
- **Cause:** not the touch layout. The menu doubles the units' size on a phone (`content_scale_factor` 2, a canvas
  540 units high) and only gives it back when it leaves the tree, but a night is pushed over the menu, which stays.
  The night's HUD and touch layer are made for 1080, so the night ran on a canvas half as tall as it was drawn for.
  The first lesson on this ([a touch button off screen on the phone canvas](2026-11-02-a-touch-button-was-off-screen-on-the-phone-canvas.md))
  patched one button instead of asking why the night was at 540 at all.
- **Fix:** a screen that is not the menu sets the scale it is made for when it starts (`NightScreen` puts the
  player's own UI scale on the window), and the menu re-applies its factor when it shows again
  (`MenuShell.visibility_changed`, and never while hidden). A test pushes a night over a phone menu and pops it
  (`test_night_scale.gd`); the browser probe checks every touch button's circle is inside an 844 by 390 page.
- **Check:** when a layout is off screen at one size, read the canvas the game reports and ask who set it, before
  moving the buttons.
- **Docs:** the deadnight menu shell page (`docs/research/menu-shell.md`).

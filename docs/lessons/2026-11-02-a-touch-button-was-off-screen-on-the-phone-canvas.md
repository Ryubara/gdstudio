---
areas: [input, godot-ui, web]
---
# A touch button was off screen on a phone's 540 unit canvas

2026-11-02

- **Saw:** a browser probe tapping the new touch MELEE button (844 by 390 page, touch emulation) made 0 blows in
  both hands. The game reported the button's centre at page y of -108: off the top of the screen.
- **Cause:** `MenuShell` sets the window's `content_scale_factor` to 2.0 on a phone (short side under 500 px), so the
  canvas is 540 units high, and it only gives the factor back when it leaves the tree. A night is pushed over the
  menu, so the menu stays and the night runs on 540 units. `TouchLayout` offsets (up to 690 from the bottom) and its
  tests only knew canvases of 864 to 1080 units, so a button placed by offset from the bottom went above the top.
  The SIDE button (640 up) and the top of AIM, RELOAD and SWAP are off or clipped there too.
- **Fix:** place a new touch button where it fits both sizes (MELEE: 60 left, 310 up) and test its circle against
  a 1168 by 540 canvas as well. Read the canvas the browser reports (`window.__melee` or the bench's `viewport`)
  before blaming the tap. The older buttons are a follow-up issue.
- **Docs:** [touch controls](https://github.com/Ryubara/deadnight/blob/main/docs/design/touch-controls.md), the
  deadnight pull request for #588.

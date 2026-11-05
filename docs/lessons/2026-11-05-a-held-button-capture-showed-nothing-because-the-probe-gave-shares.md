---
areas: [tests, input]
---
# A held-button capture showed nothing because the probe's places were shares, sent as pixels

2026-11-05

- **Saw:** a browser capture of "Scoreboard held" and "Bots wheel held" (Deadnight #1275) looked exactly like the frame
  before: no ticket, no wheel. A script left by an earlier agent had been trusted and its frames filed as "the held
  state". The run printed no error.
- **Cause:** the probe's `touch_hits` list gives each button as shares of the page (`0.18913,0.16481`), and the script
  sent them to the DevTools touch event as pixels (a touch at 0.19 px, 0.16 px, the page's corner), where nothing is
  pressed.
- **Fix:** multiply by the page's width and height (`x * W`, `y * H`) before `Input.dispatchTouchEvent`. Check for next
  time: read the frame of every "held" capture before it is used as evidence, and have the script assert the state it
  claims (`touch_held` in the probe names what the layer thinks is down); a script inherited from another agent is
  read, not trusted.
- **Docs:** [Mobile controls](https://github.com/Ryubara/deadnight/blob/main/docs/research/mobile-controls.md#the-audit-1275)
  (Deadnight).

---
areas: [tests, input, web]
---
# A browser probe's bench set the mouse visible and the night paused itself

2026-11-02

- **Saw:** Deadnight's `touch_assist.py` probe "sometimes never turned the view": the crosshair stayed 1.17 m off the
  zombie in some runs, passed in others, and on a loaded machine the bench never got ready at all. The page showed the
  Paused card.
- **Cause:** the bench's player had asked for the pointer lock when it entered the night, then the bench set
  `capture_mouse = false` and `Input.mouse_mode = VISIBLE`. The grip still wanted the lock, so the free mouse read as a
  lock lost and the night paused (touch layer off, controls off): 3 of 3 runs paused at the start with the old bench
  and 0 of 3 with the request withdrawn (`grip.want(false)`), measured on one build with the fix behind a query flag.
  A second flaw hid behind it: the zombie was placed while the shoulder camera still eased in, so the view started
  0.44 m off, under the 0.55 m stop, and the drag loop exited on its first check without a drag (a passing run that
  proved nothing).
- **Fix:** the bench withdraws the request, waits until the lens is still, then places the zombie. The probe now fails
  when the bench starts too near to need a drag, when the night is paused, and when the yaw does not change, and it
  prints the yaw and the distance at every drag step.
- **General:** a probe's pass must need the thing it tests (a drag that has distance to cover), and it reads and
  reports the game's own pause state before it blames the feature.
- **Docs:** [Web export](../engines/godot/web-export.md#pointer-lock-and-esc-design-it-in-from-the-first-playable-night).

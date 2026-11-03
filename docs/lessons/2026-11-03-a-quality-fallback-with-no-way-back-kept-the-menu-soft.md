---
areas: [godot-ui, godot, tests]
---
# A quality fallback that never stepped back up kept the menu at half resolution all session

2026-11-03

- **Saw:** the menu stage ran at half resolution (960 x 540 at 1080p) after one busy second when the game opened, and
  stayed there at 4 ms frames until the game was closed (Deadnight #893). A probe that busied the main thread for 5 s
  at launch read Half at 3 s and still Half at 15 s.
- **Cause:** the governor judged the look by one 1.5 s window of frame time and had no way back ("never steps back up,
  so a machine that struggles does not flicker"). Anything running at launch (other processes, a shader compile)
  decided the look for the session.
- **Fix:** drop only after two slow windows in a row; climb back after 4.5 s of good windows counted in seconds (a
  240 Hz display fills a 90-frame window in 0.4 s); each climb that fails within 30 s doubles the wait, and after two
  the stage stays down, so the look changes at most three times. Tests feed frames by hand: the recovery, the doubling
  and the stop, the fast display, and a drop long after a climb not counting. Capture the fallback at both levels on
  the target display, and run the governor in a real window with a load that ends.
- **Docs:** [UI controls](../godot/ui-controls.md#3d-in-a-menu).

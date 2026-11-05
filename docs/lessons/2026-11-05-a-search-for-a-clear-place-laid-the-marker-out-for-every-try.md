---
areas: [godot-ui, tests]
---
# A search for a clear place laid the marker out for every try, and a suite ran past ten minutes

2026-11-05

- **Saw:** Deadnight #1218 moves a HUD marker (shape, words, arrow) to the nearest place under no card. The first
  suite that put 300 markers under the cards of a phone's HUD ran past ten minutes and had to be stopped (the desktop
  pages of the same suite took 31 s; after the fix 7 s, and the phone pages 29 s).
- **Cause:** every candidate place was checked by laying the marker out again, shaping its strings
  (`Font.get_string_size`), and the search had two rounds that were both run in full: about 44 places, then 44 more from
  each of those, so about 2000 layouts for one marker. Run in a draw, that is tens of milliseconds a marker a frame.
- **Fix:** measure the strings once a draw (`HudMarkers._width` keeps a dictionary the draw clears), take the nearest
  clear place of the first round and only run the second when the first has none. A background run that is stopped
  is not always killed: `TaskStop` left the Godot of the first run burning a core, found in the process list by its
  command line and stopped by its PID.
- **Check:** a search that tries places counts its tries per item; a test that builds a worst case (every card, every
  corner, every kind) also times it, and a layout that is run per try must not shape text per try.
- **Docs:** Deadnight `docs/research/mobile-controls.md` (World markers on a phone's night, #1218).

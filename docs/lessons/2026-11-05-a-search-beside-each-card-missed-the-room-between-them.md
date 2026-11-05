---
areas: [godot-ui, tests]
---
# A search beside each card missed the room between them, and the grid test left that page out

2026-11-05

- **Saw:** Deadnight #1230. On the smallest phone page (667 x 375 CSS px at interface size 1.25, a 1536 x 864 canvas) a
  marker the #1218 search could not place stayed under a card, and the suite that was meant to prove it skipped that
  page (`CRAMPED`). A column 344 units wide stood free between the cards and the buttons the whole time.
- **Cause:** the search tried the places beside each side of each card, then once more from the nearest four: it only
  found a place that was one or two slides away from the marker, so a corridor of three obstacles was out of reach. The
  exclusion in the test turned "the search is incomplete" into "this page is out of scope".
- **Fix:** a rectangle that is clear can be slid left, then up, until it rests on an obstacle or the screen, so a place
  exists only on lines where its left edge is on either side of an obstacle (or the screen) and its top the same: try
  those columns nearest first, and in each column take the nearest clear `y` from the obstacles' edges
  (`HudMarkers._nearest_clear`, `_clear_y`). It is complete and cheaper than the slides (a frame with every marker
  moved: 7 ms against 37 ms on the smallest page). Take the rectangle's size in the middle of the screen, where nothing
  clamps it, and look at the place found as it is drawn.
- **Check:** a test that skips a page names a follow-up issue, and the follow-up removes the skip. A placement search
  gets a test with a corridor (cards and buttons on both sides) and one that counts how many markers a page holds, so
  "no room" is a number on a page and not a guess; a second pass that exists to find the leftover places is a sign the
  first is incomplete.
- **Docs:** Deadnight `docs/research/mobile-controls.md` (World markers on a phone's night, #1218 and #1230).

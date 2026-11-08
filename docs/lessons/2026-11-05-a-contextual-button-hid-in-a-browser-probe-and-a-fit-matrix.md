---
areas: [godot-ui, tests, web]
---
# A contextual button hid in a browser probe and in a fit matrix, and a new hint was missing from two expected lists

2026-11-05

- **Saw:** Deadnight #1295 (the scoreboard held on the players' column) met #1296 (Strike shows only with a dead in
  reach) and #1297 (the shoulder's double tap). After the merges: `tools/web_smoke/touch_scoreboard.py` failed with "the
  ticket is under the quick_melee button" though Strike was not drawn (the probe's `touch_buttons` lists every circle);
  the ticket-fit matrix had only been run with Strike down (with it up the smallest page was at the least step, 0.50);
  `test_touch_hints` and `test_popup_lane` expected a first-run list without the new hint; and the new hint stood
  over the popup lane's cards on the smallest canvas.
- **Cause:** the earlier lesson on a button that shows only sometimes named the suites, not the browser probes and not
  a geometry matrix that fits one part among the buttons; each keeps its own picture of "the buttons". A hint with a
  place search only knew buttons and places, not the HUD's cards or the lane's stack, which come and go.
- **Fix:** after merging a contextual button, `grep -rn "<id>\|touch_buttons\|TouchHints.ORDER" game/tests tools/web_smoke`
  and give the probe the context flag (`touch_strike`) so it skips a circle that is not drawn; run a fit or clearance
  matrix twice, with the context down and up; hand a place search the cards that move (the zone's `cards`), and add
  the new hint to every "first run" list in the same commit.
- **Docs:** [Testing a game](../gamedev/testing.md#shared-change).

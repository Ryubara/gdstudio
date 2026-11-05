---
areas: [godot-ui, input]
---
# A thumb's room between two buttons was written in canvas units, and Pause and Ping were a thumb's width apart

2026-11-05

- **Saw:** the phone audit of Deadnight #1275: Pause and Ping, side by side on the top edge, were 27 CSS px apart by
  the audit's count (the exported page measured their centres 33 to 35 CSS px apart and their hit areas overlapping by
  12 to 13), so a tap for one could pause the night. Every layout test passed: the
  buttons did not overlap as drawn circles, and the distance was a constant of 96 units.
- **Cause:** a distance a finger needs was written in canvas units. A unit is 0.29 CSS px at interface size 0.8 and
  0.45 at 1.25 (0.36 at 1.0), so one constant is 7 mm at one size and 11 mm at another, and the tests read units and
  the drawn radius, never the glass. The hit area (a fingertip, `MenuScale.tap_units`) is wider than the drawn button
  on a phone, so "no overlap" of the drawn buttons said nothing about the touch.
- **Fix:** Ping's place is computed from the fingertip (`TouchLayout.ping_drop`: the most of 56 CSS px, both hit areas
  with air between them, and a unit fallback where no fingertip is known), and `test_touch_ping_place` measures the
  distance and the air in CSS px on the two phone pages at every interface size, plus real touches walked from one
  button to the other in the exported page (`tools/web_smoke/touch_ping_place.py`). Check for next time: a spacing a
  thumb needs between controls is stated in millimetres or CSS px and derived from `tap_units`; its test converts
  units with the page's own scale and asserts the hit areas, not only the drawn circles. A test with no fingertip
  (`finger = 0`) lays out a different page than the player's.
- **Docs:** [Mobile controls](https://github.com/Ryubara/deadnight/blob/main/docs/research/mobile-controls.md#ping-under-pause-a-thumb-apart-1289),
  Deadnight.

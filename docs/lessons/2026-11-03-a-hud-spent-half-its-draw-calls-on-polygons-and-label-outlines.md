---
areas: [godot-ui, godot]
---
# A HUD spent half its draw calls on polygons and on the four glyph runs of a label

2026-11-03

- **Saw:** with a late-round crowd the HUD was about 125 of 400 draw calls (Deadnight #948); the script cost was small
  (0.13 ms), the cost was drawing. A card with its text was 10 to 15 calls, the six perk badges 48, the round banner 52,
  the whole late-round HUD 249 in a fight, 301 with the banner (no 3D under it).
- **Cause:** in the Compatibility renderer only rect commands (`draw_rect`, `draw_texture*`, `draw_string*`) batch;
  every polygon, polyline, circle, arc and line is a call of its own and ends the batch around it (a spike: 20 cards
  with a rect each, 1 call as rects, 40 with any one polygon, line or circle). A ticket was a shadow polygon, a paper
  polygon, an edge polyline and a stripe rect. And a `Label` with an outline and a shadow draws four glyph runs (shadow
  of the outline, shadow, outline, letters) that alternate between the outline's texture and the letters', so each run
  is a call: about 30 labels, 120 calls.
- **Fix:** collect shapes in one triangle array (`RenderingServer.canvas_item_add_triangle_array`, a colour a vertex, in
  drawing order): a card is one call. Draw a label's outline yourself in a canvas item behind the label's own and give
  the engine none: shadow and letters are one texture, so a label is two calls. 249 calls became 133 in a fight and
  301 became 140 with the round banner up (222 became 107 and 272 became 112 on a phone's window), and the picture differs
  by at most one level of 255 (the order black runs are blended in).
- **Things that went wrong on the way:** the outline drawn from the label's own `_draw()` came out over the letters (the
  script's `_draw` runs after the engine's label drawing; use a child item with `canvas_item_set_draw_behind_parent`); a
  child item does not get its parent's `self_modulate` (a row stack that fades rows in by it left the outline at full
  strength: give the child the alpha too); the shadow of the outline is a rim hidden under the outline, and drawing it
  at the outline's size made the label darker.
- **Docs:** [Canvas draw calls](../engines/godot/canvas-draw-calls.md), [Performance review](../engines/godot/performance-review.md).

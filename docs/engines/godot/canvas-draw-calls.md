# Canvas draw calls in the Compatibility renderer

What makes a Control-drawn HUD cost draw calls, and how to cut them without changing a pixel. From Deadnight #948: a
late-round HUD in a fight was 249 draw calls (1920 x 1080, no 3D under it) and is 133 after, 222 and 107 on a phone's
window, pixel for pixel the same picture (at most one level of 255 in about 3,000 pixels). Counts are the right unit
on a shared machine; read them with `Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)` and
attribute them by hiding one node at a time (Deadnight `HudCostProbe`).

## What batches and what does not

A spike of 20 cards, each drawing one shape and a small `draw_rect` after it (draw calls of the frame):

| Each card draws | Calls for 20 cards |
| --- | ---: |
| `draw_rect` only | **1** (rects with one texture batch across canvas items) |
| `draw_colored_polygon` + a rect | 40 |
| `draw_primitive` (two quads) + a rect | 40 |
| `draw_line` (width 4) + a rect | 40 |
| `draw_polyline` (width 3) + a rect | 40 |
| `draw_circle` + a rect | 40 |

- `draw_rect`, `draw_texture*` and `draw_string*` are rect commands: consecutive ones with the same texture are one
  call, even across canvas items.
- Every polygon, polyline, circle, arc, line and primitive is a call of its own (they are not rects) **and ends the rect
  batch around it**, so one polygon between two rects is three calls.
- A `Label` with an outline and a shadow draws **four runs of glyphs**: the shadow of the outline, the shadow of the
  letters, the outline, the letters. The outline's glyphs and the letters' glyphs are on different textures, so the runs
  alternate and each is a call: 4 calls a label. A label with neither is 1. (`shadow_outline_size`, default 1, is the
  rim of the shadow of the outline.)
- `Control.visible = false` takes a node out of the count at once: hide one node, count again, and the difference is
  what it draws (hiding a parent takes its children with it, so read the tree, not a sum).

## Draw many shapes as one command

`RenderingServer.canvas_item_add_triangle_array(item, indices, points, colours)` is one polygon command with a colour
for each vertex. Collect a card's shadow, paper, edge and stripe in one array, in drawing order (the GPU blends the
triangles of one draw in index order, so they stack as separate commands did), and the card is one call, not four. In
Deadnight `HudShapes` does it: `polygon` (`Geometry2D.triangulate_polygon`, the engine's own triangulation), `rect`,
`line`, `polyline`, `circle`, then `flush(item)`.

To keep the picture the same, build the engine's geometry:

- `draw_polyline` (no antialiasing): a quad a segment, **mitred** at each vertex (the offset along the mean of the two
  segments' normals, lengthened by `1 / dot(mean, normal)` so the edges stay half the width from the line); a closed
  shape repeats its first point at the end and the seam is joined like any other corner. Without the seam join one pixel
  at the start vertex of every card was missing; with the mean normal left short (no mitre) the picture was identical at
  1:1 and 174 border pixels short at 0.36 scale, where a stroke is 0.7 pixel thick and a pixel centre is covered or not
  by a few tenths of a unit. **Check a rebuilt shape at the smallest scale the game runs at (a phone), not only at 1:1.**
- `draw_circle`: a fan of 64 segments from the centre.
- `draw_line` of width 2 or more: the same quad as a two-point polyline.
- An antialiased arc or polyline (`draw_arc(..., true)`) has a feathered edge that is not reproduced: leave it as its own
  command, drawn after the array.

## A label's outline in two calls instead of four

Give the label an outline of its own and none to the engine (`outline_size` 0): the engine draws the shadow and the
letters (one texture, one call). Draw the outline yourself into a child canvas item made with
`RenderingServer.canvas_item_create()`, `canvas_item_set_parent(item, label.get_canvas_item())` and
`canvas_item_set_draw_behind_parent(item, true)`: it is drawn first, with its own texture, one call (Deadnight
`HudLabel`; free the RID on `NOTIFICATION_PREDELETE`). `TextLine.draw_outline(canvas_item_rid, pos, size, colour)` draws
into any canvas item. Three things made the picture match:

- Position: the engine sets a line in a box of `get_line_height()` (the font's line plus the theme's `line_spacing`) and
  centres it there, so the outline's top is `(get_line_height() - text_line.get_size().y) / 2`, not 0.
- The shadow of the outline is **dropped**: it is a quarter-pixel rim in the shadow's alpha under an outline that covers
  it. Drawn at the outline's size it was darker than the engine's, at its own size (1) it differed in 20,000 pixels, and
  dropped the difference is at most one level in 2,600.
- The order of the runs under the letters does not matter when they are all black at some alpha (the product of
  `1 - alpha` does not depend on the order), up to one level of rounding.

A label that wraps (`autowrap_mode`) draws the same outline with a `TextParagraph` on the engine's breaks. The engine
sets each line in a box of the font's height (`Label.get_line_height()` is the font's height, without the theme's
`line_spacing`) with `line_spacing` between the boxes, and centres the shaped line in its box: set
`paragraph.line_spacing = box + theme_spacing - line_height` and draw at `(box - line_height) / 2`. Getting the pitch
wrong by a pixel or two put the second line's outline out of its letters (the first line matched), so compare a
two-line label.

A child canvas item does not get its parent's `self_modulate` (it gets `modulate`): a fade-in by `self_modulate` must set
the outline item's `canvas_item_set_self_modulate` too (Deadnight `HudLabel.set_enter_alpha`).

## Icons from one atlas

Deadnight's level icons (#1060), eight 24 px name tags, counted in the web build and on the desktop with the same
numbers, the frame's own call taken off:

| Eight of them | Calls |
| --- | ---: |
| Icons from one atlas (`draw_texture_rect_region`, or eight `TextureRect`s of `AtlasTexture`s) | 1 |
| Icons from eight textures | 8 |
| Whole tags: every icon, then every outline, then all the letters | 3 |
| Whole tags: icon, outline, letters, tag by tag | 24 |

- **The order of the commands is the batch.** One atlas is not enough: a run of glyphs between two icons ends the
  batch, so draw all the icons of a frame before any words.
- **`load()` in `_draw` is not enough either.** Draw commands keep a RID, not a reference, so a texture nothing else
  holds is freed when `_draw` returns and the rect comes out white, with no error
  ([lesson](../../lessons/2026-11-04-a-texture-loaded-in-draw-came-out-white.md)).
- **An atlas shown far under its size:** import it with mipmaps and set `texture_filter` to
  `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`. 64 px cells at 24 px are softer at rest and change 22 to 43 percent less at each
  quarter-pixel step than with plain linear filtering. Keep the art 3 px of 128 inside the cell so a mipmap does not
  bleed into the next one.
- **Rasterise in a headless `-s` script:** `Image.load_svg_from_string` needs no window; it draws shapes, strokes and
  transforms, and no `<text>`. Compare hashes of the sources in a manifest to catch a stale atlas, not pixels: no
  raster has to match across machines.

## Animate alpha with `modulate`, not a redraw

A fade or pulse that only changes a colour's alpha does not need `queue_redraw()`: draw the shapes in a child at full
alpha and set its `self_modulate.a` (the same blend, no new vertex arrays; see [the web heap](web-heap.md)).

## A node per box counts against the canvas-item budget

The late-round budget (Deadnight `tools/perf/budget.json`, `canvas_items`) counts every canvas item in the tree, and a
HUD box is built once per player, so one `Control` added to a box costs the party's size (Deadnight #1199: a strip
behind the words made 233 against a limit of 230 when main peaked at 229). Draw a second shape in a neighbouring
item that is already there (`draw_set_transform` moves it to the right place; it may draw outside its own rect) and
keep the shape's data in a `RefCounted` that emits `changed`. Do not raise the limit for a look.

## A hidden part still counts: build it when it is first needed

The same budget counts a card that is hidden for the whole night, so the room is usually in the parts a night builds
and never shows. Count by part first (Deadnight: `--canvasparts=1` on the budget's command, then
`tools/perf/canvas_parts.py`): its end board, challenge prompt, scoreboard, marquee and boss bar were 43 of 215 and
are one item each until used. Make the words on first need (a property whose getter builds, `_build()` where the part
is shown) and never park them out of the tree, which makes them orphans, another budgeted count. A test checks both
ends: nothing under the part while idle, the whole card after use.

## How to compare two builds

Capture a still scene (the time-driven parts stopped) from the old and the new build and compare pixels. Render both from
separate checkouts, never by swapping files under a run. Mask what is not deterministic (a 3D portrait in a SubViewport
differs from run to run: capture the same build twice to find those regions) and the rest should be 0 pixels, or a
number you can explain. Deadnight: `tests/captures/hud_cost.tscn` and its `--deep` report.

---
areas: [web, godot, tests]
---
# A control redrawn every frame made the web page's heap grow 30 MB a minute

2026-11-03

- **Saw:** in a 13-minute autopilot night in the web build the page's JS heap after a forced garbage collection grew
  from 148 to 815 MB, while the engine's nodes, resources and video memory stayed flat (Deadnight #728, #834). The plan
  was to switch the page's JavaScript publishers and recorder off one at a time.
- **Cause:** not those. Emscripten numbers every WebGL object from one shared counter and pads every id table to it;
  the tables never shrink, so each object ever created costs about eight slots for the life of the page. The touch
  controls called `queue_redraw()` every frame and drew fourteen buttons and a stick with `draw_circle` and `draw_arc`;
  in the Compatibility renderer each of those is a polygon with its own vertex array and buffers, built again at every
  redraw: 116 buffers, 78 vertex arrays and 5 fences a frame, which the page kept for good (a phone page only: the
  desktop has no touch layer).
- **Fix:** redraw the controls when a key of what they show changes (held buttons, stick, verb, layout), and the round
  banner's bulbs only when the chase steps (5 a second): 31 to 3.9 MB a minute (8 times less). What stays is about 5
  fence syncs a frame, the renderer's own, which the page cannot stop.
- **Found by** a forced collection, V8's sampling heap profile (eight stacks of 25 MB, all `glGen*` through
  `getNewId`), a count of the WebGL creations a frame, a trace of the GL calls of a few frames and ablation by freeing
  nodes at the page's address, not by reading code or switching the publishers off.
- **Docs:** [The web page's heap](../godot/web-heap.md); Deadnight `docs/research/web-heap.md`. Check: a canvas item
  that draws circles, arcs or polygons never calls `queue_redraw()` every frame; a test counts its `draw` signals over
  a few idle frames.

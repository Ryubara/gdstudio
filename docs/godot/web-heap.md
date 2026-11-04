# The web page's heap: what holds it, and how to find it

What a Godot 4.7 web build (Compatibility renderer) taught about a page whose JS heap, after a forced garbage
collection, grew 50 MB a minute over a night while the engine's own nodes, resources and video memory stayed flat
(Deadnight #834, found by #728). The game's numbers are on `docs/research/web-heap.md` there.

## The mechanism: WebGL object ids are never given back

Emscripten numbers every WebGL object the engine creates (`glGenBuffers`, `glGenVertexArrays`, `glGenTextures`,
`glFenceSync`, `glCreateProgram`, ...) from **one shared counter**, `GL.counter`, and pads **every** id table
(`GL.buffers`, `GL.vertexArrays`, `GL.textures`, `GL.programs`, `GL.syncs`, ...) with `null` up to that counter
(`GL.getNewId`). Deleting an object nulls its slot; nothing shrinks a table. So each object ever created costs a slot
in each of about eight arrays (8 bytes each in the page's heap) until the page closes, whatever kind it was and
however soon it was deleted. `GL` is a private variable of the engine's script (`index.js`): a page cannot reach it
and there is nothing to call. The only fix is to create fewer objects.

A game that creates a few hundred objects at load never sees it. One that creates and frees objects **every frame**
leaks: 200 objects a frame at 100 frames a second is 80 MB a minute. The engine's monitors (objects, nodes,
resources, texture and buffer memory) are flat, because the objects are freed; only the page's heap shows it.

## What makes objects every frame

In the Compatibility renderer a **canvas item that is redrawn builds its polygons again**: every `draw_circle`,
`draw_arc`, `draw_polygon`, `draw_polyline` and `draw_colored_polygon` command is a polygon that gets its own vertex
array, vertex buffer and index buffer (`RasterizerCanvasGLES3`'s polygon buffers), freed when the item is redrawn or
cleared. `draw_rect`, `draw_string` and `draw_style_box` are batched rects and cost none. So a control that calls
`queue_redraw()` in `_process` and draws forty circles and arcs creates about 40 vertex arrays and 80 buffers a frame.

Deadnight's touch controls did exactly that (14 round buttons and the stick, `queue_redraw()` every frame): 116 buffers,
78 vertex arrays and 5 fences a frame in a running night, none in the menu.

Rules:

- **Redraw on change.** Compute a cheap key of everything `_draw` reads (what is held, the layout, the verb, the
  look) in `_process` and call `queue_redraw()` only when it differs. An animation that must move every frame should
  not be built from `draw_circle` and `draw_arc`: step it at the animation's own rate (bulbs that chase five times a
  second redraw five times a second), or use a mesh or shader.
- The engine redraws a `Control` itself while its `scale` changes (a banner that popped in by scaling drew 20 times in
  60 frames, a test counts the `draw` signal), so an animation of that kind rebuilds the polygons too. Count `draw`
  signals in a test to see what is really redrawn.
- Redraw by what was **drawn**: record the key in `_draw` (not where the redraw is queued), and compare it to the key
  of now. A count of the `draw` signal over a few idle seconds shows any other `queue_redraw()` left (a `refresh`, a
  setter); a label or bar that is a child node moves with its own `modulate` and never needs the parent redrawn
  (Deadnight #934: 60 draws a second to 3).
- A hidden item (`visible = false`) is not redrawn, but a parent that sets its own `visible` again every few frames
  (as the touch layer did) brings it back.
- About 5 fences a frame are the renderer's own (one per canvas or 3D render pass: `bufferData` of a state buffer, then
  `fenceSync`, then `deleteSync`); they stay.

## How to find it (an hour, not a week)

Switching the page's own JavaScript publishers and recorders off one at a time was the plan and it was the wrong
tree: they were never the cause. What found it, in order:

1. **Force a collection, then read the heap.** `HeapProfiler.collectGarbage` over a CDP session, then
   `Runtime.getHeapUsage`: a rise after it is held, not waiting to be freed (Deadnight `tools/web_smoke/heap_soak.py`,
   every 30 s).
2. **V8's sampling heap profiler** (`HeapProfiler.startSampling` at load, `stopSampling` after a collection) lists the
   stacks that allocated what is still alive. Here: eight stacks of 25 MB each, every one a `_emscripten_glGen*` or
   `glCreate*` through `getNewId`. That names the mechanism in one run.
3. **Count the WebGL creations**: wrap `WebGL2RenderingContext.prototype.createBuffer`, `createVertexArray`, `fenceSync`,
   ... in an init script and divide by the frames drawn (`requestAnimationFrame` count). Menu: 0 a frame; running
   night: 116 + 78 + 5.
4. **Trace the calls of a few frames** (wrap `bufferData`, `bindVertexArray`, `deleteBuffer`, ...): a unit of
   `createBuffer, createVertexArray, bufferData(ARRAY_BUFFER, STATIC_DRAW), createBuffer, bufferData(ELEMENT_ARRAY_BUFFER)`
   repeated every frame is a canvas polygon.
5. **Ablate by dropping nodes** at the page's address (Deadnight's `BenchAblation`: `drop=Class`, `still=Class`) and
   read the creations a frame again. Hiding a node (`ui=0`) does not stop a node that makes itself visible again;
   freeing it does. Group the candidates and halve.

Release web exports have no function names (the wasm has no name section, the debug template neither), so a stack of
`wasm-function[9312]` only tells two sources apart; use it to count sources, not to name one.

## Reading a heap number

`performance.memory.usedJSHeapSize` rises and falls with the collector (93, 158, 117 MB seconds apart). Only the value
after a forced collection says anything. Compare arms after the same minutes of the same night, and give the
statement a rate: MB a minute at the frame rate measured (the cost is per frame, so a phone at 30 frames a second
grows at a third of a desktop at 100).

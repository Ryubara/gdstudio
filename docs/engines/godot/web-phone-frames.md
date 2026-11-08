# The web build on a phone: frame rate, pixels and how to measure

What a phone-sized Chrome taught about a Godot 4.7 web build (Compatibility renderer), from Deadnight's issue #689.
The game's own numbers are on `docs/research/phone-frames.md` there.

## There is no frame cap to lift {#there-is-no-frame-cap-to-lift}

The web main loop is `requestAnimationFrame`: the game draws once per display refresh, whatever the refresh is (60,
90, 120 Hz). `application/run/max_fps` is 0 (unlimited) by default and the project setting "vsync" is ignored by the
browser. If a player says the frame rate is "capped" on a phone, it is that the frame takes too long, and the browser
shows only the frames that finished. Check `max_fps` and the physics tick in `project.godot`, then measure.

## Pixels are the first lever {#pixels-are-the-first-lever}

- **Godot sizes the canvas by `window.devicePixelRatio`.** A phone reports 3 (a page of 844 x 390 becomes a canvas of
  2532 x 1170, 2.9 million pixels), and a Compatibility frame is mostly fill. Capping what the page reports
  (`Object.defineProperty(window, 'devicePixelRatio', {get: () => Math.min(real, 2)})` in `html/head_include`, before
  the engine script) draws 56 % of the pixels at a ratio of 2. It costs nothing in the picture a phone shows, and touch
  input is unchanged (Godot reads the canvas rectangle). Do it for a coarse pointer only: a desktop at ratio 1 or 2 is
  left alone.
- **`scaling_3d_scale` below 1.0 is slower on the web**, not faster: the 3D view goes to its own render target and is
  stretched, which cost more than the pixels saved (2.4 times in Chrome at 67 %). Do not offer it as the phone's fix.
- **MSAA on the 3D view** is the largest single piece of a fill-bound frame; off, at a ratio of 2 or more, the
  stair-steps it smooths are under a real pixel.

Measured (Deadnight, a fill-bound stand-in): ratio 3 with 2x MSAA 565 ms median, capped at 2 303 ms, capped and no MSAA
212 ms; 99th percentile 797, 595, 325 ms.

## Measuring a phone without one {#measuring-a-phone-without-one}

Chrome has two knobs and each hides what the other shows:

| Stand-in | Shows | Hides |
| --- | --- | --- |
| CPU throttle (`Emulation.setCPUThrottlingRate`) | script, physics, driver, draw-call cost | fill cost (the desktop GPU stays fast) |
| SwiftShader (`--use-gl=angle --use-angle=swiftshader`) | fill cost, as a weak GPU has | absolute speed (a few frames a second) |

- Emulate the phone fully: `is_mobile`, `has_touch`, the viewport and `device_scale_factor`, or the page does not pick
  its phone paths.
- **Compare ways of drawing inside one page, interleaved**, never in separate runs on a shared machine: two runs of one
  setup differed by 10 times when other programs started. Switch the setting every 30 seconds, drop the first seconds
  after a switch (the canvas reallocates), and give each arm the same minutes. Ten minutes per arm set is the least that
  shows throttling; heat itself cannot be emulated.
- Record every `requestAnimationFrame` delta from a page script (`add_init_script`), not the engine's own frame time:
  the engine's number leaves out the frames the browser dropped.
- The engine's own counters help find the cost: `RenderingServer.get_rendering_info(RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)`
  and `..._PRIMITIVES_IN_FRAME`, and `viewport_get_measured_render_time_cpu` (after `viewport_set_measure_render_time`;
  the GPU time reads 0 in WebGL). Read them only when a profile asks, so a player's page pays nothing.

- **Approach:** Measure a phone claim on a phone-shaped page (pixel ratio 3, touch) with a GPU-bound stand-in as well as
  a CPU throttle, before and after interleaved in one run, and name the limit measured against. **Watch out for:** a
  phone frame costs fill rate times the pixel ratio; the export sized its canvas by the page's ratio (3 on a phone, 2.9
  million pixels) with 2x MSAA everywhere, and every check ran on desktop or under a CPU throttle, which hides fill
  cost. **Seen:** Deadnight #689, 2026-11-03 (fix: one page switches between the arms every 30 s; fill cost is read with
  SwiftShader and processor cost with the throttle, each as a ratio and never as a phone's frame rate).

- **Approach:** Measure a rendering change on a GPU and on the software renderer, interleave the cells so a slow minute
  hits every row, report both, and read the draw calls (`RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME`) first. **Watch out
  for:** a GPU hides draw calls and extra passes behind its own parallelism, while the software renderer pays every
  vertex and pixel on the CPU, nearer to a weak phone or an integrated chip: an outline of 3 zombies (51 extra draw
  calls) moved a 40-zombie frame from 2.66 to 2.62 ms in Chrome with a GPU and from 199 to 239 ms on SwiftShader.
  **Seen:** Deadnight #580, 2026-11-02 (fix: `outline_cost.py --gl gpu` and `--gl software` are both reported).

## Fewer draw calls is not a faster CPU-bound frame (Deadnight #728) {#draw-calls-cpu-bound}

Folding a lot's 850 mesh surfaces and 295 CSG boxes into per-cell meshes (`SurfaceTool.append_from`, one surface per
material per cell) cut draw calls by about a quarter and left the CPU x4 median unchanged (46.8 against 48.2 ms over 10
minutes of shuffled 20 s blocks): of a 47 ms frame, script and physics were 47 and 21 ms and render CPU 10 ms.

- Bound a lever with an ablation that removes the thing outright before building it; split the frame
  (`TIME_PROCESS`, `TIME_PHYSICS_PROCESS`, measured render CPU) to see where the rest is.
- A merged mesh is drawn whole, so triangles rise; the Compatibility renderer lights a mesh by its box with at most
  `max_lights_per_object` lights, so a cell is split until the lights reaching it are few (see
  [Compatibility lighting](compat-lighting.md)), and a merge must keep each cell under the cap or the picture changes.
- Shuffle the order of the interleaved arms each round: the night's waves have a beat, and a fixed order falls on it.
- Chrome's CPU throttle belongs after the page has loaded, and `gds quiet` stops a command at 900 s.
- A page whose heap grows over a night is a different question from its frame time: see [The web page's heap](web-heap.md).

## Counting a scene's draw calls from fixed cameras (Deadnight #849) {#counting-draw-calls}

To say what new geometry costs, put one camera at each of a few dozen spots, draw, and read the count: an instance
draws whether or not anything is in front of it (no occlusion culling), so a wall across the map costs a call from every
spot that faces it, not only from the spots near it.

- Wait about 12 frames after the camera moves and take the median of five reads; the count of the frame right after a
  move is still partly the old view (one spot read 1117 and 37 in two runs of the same scene with three frames of
  waiting).
- Draw the before scene and the after scene through the same probe (a copy of the old `.tscn` beside the new one),
  and run the unchanged one twice.
- `visibility_range_end` on a `GeometryInstance3D` (a CSG box or a `MeshInstance3D`) culls by distance from the camera
  and keeps the collision: eight walled aprons, two bays and 50 boards that were +31 draws on average (+10 %) cost
  +14 (+4 %) with the aprons hidden past 35 m and the boards past 45 m (49 spots, Godot 4.7.2).

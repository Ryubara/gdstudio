# Minimap

<!-- new section: the kit had no page for a map of the world on the HUD; the third-person template's page lists it,
     this one says how it works, what it costs and how to reuse it -->

How the kit's minimap works and how a game uses it: one widget with a live camera or a baked image behind it, one marker
component any node can carry, and boxes for floors and map sections (gdstudio #884, built into the 3D Third Person
template). Measured in Godot 4.7.2 on Windows (an RTX 5080), in the Compatibility renderer, which is what the web build
runs, and in headless Chromium without a GPU. The code is in `templates/3d-third-person/game/`: `core/minimap/` (the
marker and the section, which gameplay scenes may carry), `ui/minimap/` (the widget and the full-screen map) and
`tools/minimap/`, `tools/bench/minimap_bench.tscn` (the baker and the cost bench).

## The parts {#parts}

| Part | Where | What it is |
| --- | --- | --- |
| `Minimap` | `ui/minimap/minimap.tscn` | The widget: a round or square map that follows a target, turns, zooms and draws every marker. Everything is an inspector export. |
| `MinimapMarker` | `core/minimap/minimap_marker.gd` | A node you add under any `Node3D` or `Node2D`: icon, colour, size, rotation, edge clamping and a rule for when it shows. Data only: it draws nothing and is never sent over the network. |
| `MinimapSection` | `core/minimap/minimap_section.tscn` | A box of the world (a floor, a room, a wing): slices the live camera to its height, names the map, may hold its own picture, and is what the `SAME_SECTION` rule compares. |
| `MapScreen` | `ui/minimap/map_screen.tscn` | The full-screen map: a second `Minimap` (north up, every kind, the whole map) that opens on `map` and renders while open only. |
| `MinimapIconPool`, `MinimapIcon` | `ui/minimap/` | The pool of sprites that draw markers; made once, reused. |
| `MinimapProjector` | `ui/minimap/minimap_projector.gd` | The maths with no nodes (world to widget, turn, zoom, edge clamp); the tests hold the camera and the shader to it. |
| `MinimapBaker` | `ui/minimap/minimap_baker.gd`, `tools/minimap/bake_level.tscn` | Renders a rectangle of the world top down into an image for the `IMAGE` source. |

## Using it in a game {#using-it}

1. **Put the widget in the HUD**: instance `ui/minimap/minimap.tscn` in a region (3D Third Person has it in
   `ui/minimap/minimap_layer.tscn`, a `CanvasLayer` with the small map and the full-screen one, until the HUD takes
   it). It finds its target (the first node in the `target_group`, `player`), the markers and the sections by itself.
2. **Mark things**: add a `MinimapMarker` under a pickup, an enemy, a door, a goal. Set `kind` (`enemy`, `pickup`) and
   a minimap can hide it by kind. A parent that turns inside its node (the player turns its model) gives its facing
   with a `get_minimap_heading() -> Vector2` method; otherwise the marker uses the parent's `-Z`.
3. **Choose the rotation**: `NORTH_UP`, `TARGET_FACING` or `CAMERA_FACING` (the default: what is ahead on screen is up
   and an N sits where north is). Rotating suits compact levels and following a route, north up suits big maps that
   people learn; offer the choice in a game's settings by setting `rotation_mode`.
4. **Add sections** where the map has floors or wings (`MinimapSection` boxes), and leave roofs and props off the
   camera with render layers (`live_layers`).
5. **Bake it when the level is done** (`gds godot -- --path game res://tools/minimap/bake_level.tscn`) and switch
   `source` to `IMAGE`: the second render pass is gone.

## Three ways to draw the map {#sources}

<!-- new section: nothing in the docs said how a minimap should be drawn for the web and for a map that keeps growing -->

Shipped games and the Godot community do it three ways (sources are in the pull request's research notes: Godot's
viewport and `SubViewport` pages, the community's forum threads on viewport cost in web exports, and the design
writing on rotating against fixed maps).

| Way | Cost | Strong | Weak |
| --- | --- | --- | --- |
| **Live camera**: an orthographic `Camera3D` in a `SubViewport` looking down | the level drawn once more at the map's resolution each time it renders | any level, any new section, any floor with nothing to author; rotation is free | a second 3D pass; the Compatibility renderer cannot draw it unshaded, so it is lit and casts shadows |
| **Baked image**: that same picture rendered once and drawn as a texture over a rectangle | one textured rectangle, whatever the level | no 3D cost, can be art-directed, tiles for huge maps | stale when the level changes; zoom and rotation are done on the texture |
| **Vector shapes**: footprints drawn as 2D polygons | cheapest, crisp at any zoom | no render pass | needs footprint data the template's `ProtoBlock` meshes do not export; schematic |

The widget does the first two and lets a game feed the second with any picture it draws itself (vector footprints
included); a vector source of its own was left out because the template has no footprint data to draw. One shader
cuts the shape, the background and the border and slides the last snapshot into place, so the picture moves smoothly
even when it renders a few times a second and a rotating map does not blur (the camera, not the texture, is turned).

## What it costs {#cost}

TODO_COST

## Drawing it right {#drawing}

<!-- new section: building the minimap met several faults of an off-screen camera, a viewport texture and a
     shader that no page had met -->

- **Approach:** Turn physics interpolation off on the map camera (`physics_interpolation_mode = OFF`: the widget moves
  it in `_process`), and hold the camera to the shader's maths with a test that unprojects known points through it
  (`MinimapProjector.snapshot_uv`). **Watch out for:** the templates have interpolation on, so the camera was blended
  with its transform a tick ago and a point unprojected through it was 0.4 to 0.65 of the picture away from where the
  shader looks for it (the first run of that test), and in play the picture would have lagged the icons. The rule is on
  [Physics interpolation](physics-interpolation.md#using-it); a capture of a still scene hides it. **Seen:** gdstudio
  #884, 2026-11-10 (fix: the camera's mode in `minimap.tscn` and in the baker).
- **Approach:** Ask `RenderingServer.get_current_rendering_method()` before turning on `Viewport.debug_draw =
  DEBUG_DRAW_UNSHADED` (`Minimap.unshaded_available()`), and in Compatibility draw the lit scene with a flat white
  ambient `Environment` on the camera. **Watch out for:** in Compatibility (the web build, phones) Godot 4.7.2 prints
  `Parameter "spec" is null` from `shader_gles3.h` every frame and draws nothing for that viewport, with no hint in the
  editor or in Forward+, where flat drawing works and costs about half the draw calls (99 against 180 for the
  minimap's own pass) because it casts no shadows. **Seen:** gdstudio #884, 2026-11-10 (found by running the cost bench
  with `--rendering-method gl_compatibility`; the first desktop numbers were all Forward+).
- **Approach:** Separate what the picture shows from when it was drawn: render a snapshot (a little larger than the
  view when it renders less often than every frame), tell the shader the snapshot's centre, turn and size and the
  view's, and skip the render while the view has not moved (only now and then, `still_refresh_seconds`, for a moving
  door). **Watch out for:** drawing the texture as it came made a map that rendered 15 times a second step through its
  motion while the icons moved every frame, and re-rendering a still view every frame cost the same as a moving one.
  **Seen:** gdstudio #884, 2026-11-10 (the bench: a still view renders nothing, a 15 Hz one costs 0.2 ms less than every
  frame on the desktop).
- **Approach:** Read a camera's lens only a frame after you set its transform: `Camera3D.unproject_position` uses the
  transform the node last notified, which lags `global_transform` until the end of the frame. **Watch out for:** a
  test that set the map camera and unprojected a point in the same call got the previous orientation (an unturned
  camera for a turned map). **Seen:** gdstudio #884, 2026-11-10.
- **Approach:** When a full-screen map fits the world, add the sections' footprints to the map the game starts with
  (`fit_bounds`) and let an empty rectangle mean sections only. **Watch out for:** the first version replaced the map by
  the sections, and the template's one section (a workshop 12 m wide in a 50 m map) zoomed the whole-map view onto the
  workshop with the player's marker 900 pixels off screen; the in-game test found it the moment the section existed.
  **Seen:** gdstudio #884, 2026-11-10.

## Testing it {#testing}

<!-- new section: a minimap is mostly a picture and a headless run draws nothing, so what a suite can and cannot prove
     needed saying -->

A headless run (the CI's) has a renderer that draws nothing, so what a suite can prove about a picture is its maths and
its nodes, and the pixels are proved in a windowed run or a capture.

- **Approach:** Prove the picture's orientation with numbers: unproject known points through the map camera (a frame
  after setting it) and compare with `MinimapProjector.snapshot_uv`, which is the sum the shader does; read the
  shader's defaults from its source text (`Shader.code`) because `RenderingServer.shader_get_parameter_default`
  returns nothing headless; and keep one windowed test for the baker (it reads pixels and skips itself headless).
  **Watch out for:** a rotated map is easy to get mirrored or turned the wrong way and every node test still passes
  (the first expectation for a map facing west had north on the left; it is on the right); a capture of the walk shows
  it only if a landmark is looked for. **Seen:** gdstudio #884, 2026-11-10.
- **Approach:** Send a key or an `InputEventAction` through `Input.parse_input_event` (the suites' `InputSim`) when a
  test or a capture tour presses an action a node reads in `_unhandled_input`. **Watch out for:** `Input.action_press`
  changes the action's state and sends no event, so a tour that "pressed" the map and zoom actions did nothing, and a
  frame later `Input.is_action_pressed` still disagreed while events were queued. **Seen:** gdstudio #884, 2026-11-10
  (see also [Input in UI tests](ui-input-tests.md#edges)).
- **Approach:** Keep a suite under gdlint's twenty public methods, `before_test` and `after_test` included, and look
  for the same private helper names across suites (`_carry`, `_section`) so a split moves cleanly. **Watch out for:**
  the minimap's view suite had 21 and gdlint failed the pre-commit hook after the tests had passed. **Seen:** gdstudio
  #884, 2026-11-10.

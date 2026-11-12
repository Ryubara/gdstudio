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
| `MinimapHeading` | `core/minimap/minimap_heading.gd` | A node you add under a parent whose own node does not turn (a character turns its model inside its body): `turns` points at the node that does, `front` says which of its axes is the front. The marker and a minimap that follows the parent find it by type (`MinimapHeading.of(parent)`). |
| `MinimapSection` | `core/minimap/minimap_section.tscn` | A box of the world (a floor, a room, a wing): slices the live camera to its height, names the map, may hold its own picture, and is what the `SAME_SECTION` rule compares. |
| `MapScreen` | `ui/minimap/map_screen.tscn` | The full-screen map: a second `Minimap` (north up, every kind, the whole map) that opens on `map` and renders while open only. |
| `MinimapIconPool`, `MinimapIcon` | `ui/minimap/` | The pool of sprites that draw markers; made once, reused. |
| `MinimapProjector` | `ui/minimap/minimap_projector.gd` | The maths with no nodes (world to widget, turn, zoom, edge clamp); the tests hold the camera and the shader to it. |
| `MinimapBaker` | `ui/minimap/minimap_baker.gd`, `tools/minimap/bake_level.tscn` | Renders a rectangle of the world top down into an image for the `IMAGE` source. |

## Using it in a game {#using-it}

1. **Put the widget in the HUD**: instance `ui/minimap/minimap.tscn` in a region (3D Third Person has it in the
   HUD's `MinimapSlot`, top right, and the full-screen map in `ui/minimap/map_layer.tscn`, a `CanvasLayer`). A slot
   that is a container (a `MarginContainer`) takes the widget's size; a plain `Control` slot gives it none.
   `max_screen_fraction` keeps the map to a share of the screen's short side however far its parents scale it (the
   HUD grows 1.5 times on a phone, so a 220 px map would be 325 units of 1080 and push the ammo onto the buttons).
   It finds its target (the first node in the `target_group`, `player`), the markers and the sections by itself.
2. **Mark things**: add a `MinimapMarker` under a pickup, an enemy, a door, a goal. Set `kind` (`enemy`, `pickup`) and
   a minimap can hide it by kind. A parent that turns inside its node (the player turns its model) gets a
   `MinimapHeading` child with `turns` set to that model (`front` `PLUS_Z` for a Blender model); otherwise the marker
   and the minimap use the parent's `-Z`. It is a node and not a method, so the scene shows which things give their
   own heading and a renamed method cannot break the arrow without a word (#1047, as `Health` and `Interactable` did
   for hits and use in #1029).
3. **Choose the rotation**: `NORTH_UP`, `TARGET_FACING` or `CAMERA_FACING` (the default: what is ahead on screen is up
   and an N sits where north is). Rotating suits compact levels and following a route, north up suits big maps that
   people learn; offer the choice in a game's settings by setting `rotation_mode`.
4. **Add sections** where the map has floors or wings (`MinimapSection` boxes), and leave roofs and props off the
   camera with render layers (`live_layers`). In 3D Third Person every character's meshes are on layer 2
   (`CharacterModel.body_layers`), which the default `live_layers` (1) leaves out: a body is its marker on the map.
5. **Bake it when the level is done** (`gds godot -- --path game res://tools/minimap/bake_level.tscn`) and switch
   `source` to `IMAGE`: the second render pass is gone.

## Three ways to draw the map {#sources}

<!-- new section: nothing in the docs said how a minimap should be drawn for the web and for a map that keeps growing -->

Shipped games and the Godot community do it three ways. The sources: Godot's [viewports](https://docs.godotengine.org/en/stable/tutorials/rendering/viewports.html)
and [`SubViewport`](https://docs.godotengine.org/en/stable/classes/class_subviewport.html) pages (update modes, `Once`,
`Never`), a [forum report](https://forum.godotengine.org/t/subviewport-rendering-performances-on-web/101434) of 3D
viewports under 1 FPS in a Godot 4.3 web export, the [tutorial recipe](https://uhiyama-lab.com/en/notes/godot/subviewport-techniques/)
that names update mode, resolution and `cull_mask` as the three levers, and the design writing on
[rotating against fixed maps](https://www.gamedeveloper.com/design/minimap-rotation) (rotate for compact and linear
levels, fix for big ones, offer both and mark north).

| Way | Cost | Strong | Weak |
| --- | --- | --- | --- |
| **Live camera**: an orthographic `Camera3D` in a `SubViewport` looking down | the level drawn once more at the map's resolution each time it renders | any level, any new section, any floor with nothing to author; rotation is free | a second 3D pass; the Compatibility renderer cannot draw it unshaded, so it is lit and casts shadows |
| **Baked image**: that same picture rendered once and drawn as a texture over a rectangle | one textured rectangle, whatever the level | no 3D cost, can be art-directed, tiles for huge maps | stale when the level changes; zoom and rotation are done on the texture |
| **Vector shapes**: footprints drawn as 2D polygons | cheapest, crisp at any zoom | no render pass | needs footprint data the template's `ProtoBlock` meshes do not export; schematic |

The widget does the first two and lets a game feed the second with any picture it draws itself (vector footprints
included); a vector source of its own was left out because the template has no footprint data to draw. One shader
cuts the shape, the background and the border and slides the last snapshot into place, so the picture moves smoothly
even when it renders a few times a second, and a map that renders every frame does not blur when it turns (the camera,
not the texture, is turned).

## What it costs {#cost}

`tools/bench/minimap_bench.tscn` runs the template's map with a minimap over it, once for each setting, 90 frames to warm
up and 240 measured, vsync off, and prints one JSON line a case (the header of the script says how to run it in the
renderer you want). Frame times move by a tenth of a millisecond or two between runs on a shared machine, so the table
gives the range of two runs.

**Desktop, Compatibility** (the renderer of the web build; 1920 x 1080, an RTX 5080): the map alone is 1.05 to
1.21 ms and 109 draw calls.

| Setting | Frame ms | Draw calls | What it says |
| --- | --- | --- | --- |
| Live camera, every frame (lit) | 1.64 to 1.85 | 315 | +0.5 ms; the second pass draws 205 calls (the shadow map is half of them); 0.5 ms of CPU and 0.25 ms of GPU |
| Live, 30 Hz or 15 Hz | 1.24 to 1.31 | 122 to 126 | about +0.2 ms: the pass is paid only on the frames it renders |
| Live, view standing still | 1.24 to 1.37 | 118 | one render a second (`still_refresh_seconds`), so +0.1 to +0.3 ms |
| Live, half the resolution | 1.53 to 1.82 | 301 | no saving: the cost is draw calls, not pixels |
| Image source | 1.21 to 1.48 | 118 | the widget, its shader and its pool and nothing else |

**Desktop, Forward+** (flat drawing, which has no lights or shadows): the live camera every frame is 1.24 ms against
1.14 ms alone, and the second pass draws 99 calls, half of the lit one.

**Markers**, pooled icons all moving every frame, on top of the image source (the "pass" is the widget's own
`marker_pass_usec`: the rules, the maths and the icon updates in GDScript):

| Markers | Frame ms added | Pass ms | Draw calls added |
| --- | --- | --- | --- |
| 100 | +0.4 to +0.5 | 0.35 | 31 |
| 500 | +2.1 | 1.5 | 154 |
| 1000 | +4.5 to +4.7 | 3.0 | 320 |

About 3 microseconds a marker for the pass and 4 to 5 in the frame. The same 1000 icons drawn by one `_draw` call (a
mock with no rules and no maths) add under 0.3 ms, so the way the icons are drawn is not what costs: the pass that
decides where they go is, and it is the same pass for any drawing method. Sprites moved as cheaply as controls (500
icons: 3.6 ms either way), so the icon is a `Sprite2D` for the look it can take (`minimap_icon.tscn`), not for speed.
What brings a thousand markers down is the rate (`marker_update_rate` 15 puts them once every four frames at 60 Hz),
`max_markers`, `hidden_kinds` and rules that drop markers before they are placed (`NEAR`, `SAME_SECTION`).

**Web** (the exported build in headless Chromium on SwiftShader, 960 x 540, so it has no GPU and a frame is
about 87 ms alone; WebAssembly runs the same GDScript): the live camera every frame adds 13 to 20 ms to that
(94 and 87 ms alone, 107 and 116 with it: the second pass is another 205 draw calls rasterised in software), a still
view or the image source adds 2 to 4 ms, and the rate limits cannot show here because a frame (about 100 ms) is longer
than the interval of 15 or 30 Hz, so every frame renders; measure the rates on a real GPU. The marker pass is the
number that is real CPU work in WebAssembly: 0.6 to 1.1 ms for 100 markers, 2.4 to 2.9 for 500 and 4.2 to 5.1 for
1000, about 1.5 times the desktop. The run printed one page error, `currentTime` of null (the browser's audio
context in headless Chromium), which no minimap code can raise, and no failed request. The first desktop runs used
the unshaded draw mode that Compatibility cannot do ([below](#drawing)); the web run is the proof that the lit
fallback draws.

**What to do with it.** A web or phone build keeps the live camera if the map is small (a 220 px minimap at
`live_resolution_scale` 1 is fine) and sets `map_update_rate` to 15 to 30; a finished level bakes its picture and uses
the image source, which costs nothing per frame; a crowd of markers sets `marker_update_rate` and rules before it
counts icons.

- **Approach:** Keep skinned bodies off the live camera's layers (a body has its marker), and count a character's
  frame cost in the whole game, minimap included, before blaming its animation. **Watch out for:** the live camera saw
  every layer-1 mesh, characters included, so each frame it drew every body again from 40 m up, off-screen ones too,
  and the Compatibility renderer skinned each of them for it: seven online puppets cost the browser page about 1 ms
  each on a GPU, while a bench of the same seven puppets without a minimap cost 0.25 ms each. With the bodies on
  layer 2 the page with seven puppets went from 8.6 to 9.9 ms a frame to 5.0 to 6.6 ms. **Seen:** gdstudio #1138,
  2026-11-11 ([what a puppet costs](third-person/puppet-cost.md#puppet-cost)).

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
- **Approach:** Drop the widget into a HUD slot that is a container (`MarginContainer`), and cap its share of the
  screen (`max_screen_fraction`, 0.25 of the short side) instead of giving the slot a fixed size. **Watch out for:** the
  slot was a plain `Control` with a 260 minimum, so the map in it was 0 pixels until the slot was a container; with the
  HUD's phone scale (1.5 at 844 x 390) the map took 325 of 1080 units and the ammo part, stacked under it, ended 2
  units over the Aim button (`test_hud_layout.gd` failed in two of three windows). **Seen:** gdstudio #884,
  2026-11-10 (merging the HUD, #914).
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

In 3D Third Person: the `test_minimap_*.gd` suites of `tests/core/` and `tests/ui/` and `test_map_screen.gd`
(`test_minimap_baker.gd` runs windowed only); `tools/capture/minimap_tour.tscn` records both maps and
`tools/bench/minimap_bench.tscn` measures the cost.

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
  #884, 2026-11-10; #1100, 2026-11-11 (a menu sound suite of 21, split into wiring and rules; the same hook refuses a
  function with more than six `return`s: fold the conditions into one `silent :=` expression).

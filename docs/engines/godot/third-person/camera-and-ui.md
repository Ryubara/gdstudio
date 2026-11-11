# The camera, the map and the screen

<!-- new section: split out of the third-person template page when it reached the size limit (#983) -->

The 3D Third Person follow camera, the map components, the minimap and the HUD. Part of [the 3D Third Person template](../third-person-template.md).

## Phantom Camera in a third-person follow {#phantom-camera}

<!-- new section: camera.md covers the hand-built camera; this is what the addon did in the template -->

- **Approach:** Make the player's camera a `PhantomCamera3D` in Third Person follow mode, with a wrapper that sets its
  follow target, `spring_length`, `collision_mask`, `margin` and offsets in its own `_enter_tree` (before the addon's
  `_ready` builds the spring arm), and turn it with `set_third_person_rotation_degrees(Vector3(-pitch, yaw, 0))` from
  the third `_process` on. **Watch out for:** the addon moves the camera under a `SpringArm3D` it makes, so its path at
  run time is `PlayerCamera/@SpringArm3D@N/FollowCamera` (ask the wrapper); the arm exists a frame or two after
  `_ready`; and a camera with a `tween_resource` tweens to its first view from the Camera3D's own transform unless
  `tween_on_load` is off (3D Blank's view camera had it on: a test read the lens too early and failed on the CI
  runner). **Seen:** gdstudio #821, 2026-11-08.
- **Approach:** Tune `PlayerCamera`, never `Camera`: `Camera` (a `Camera3D`) renders, `PhantomCameraHost` under it
  copies the active Phantom Camera onto it, `PlayerCamera` is the tuning wrapper and `FollowCamera` the
  `PhantomCamera3D` it drives (3D Blank has no wrapper: its `ViewCamera` is a plain `PhantomCamera3D`). The one
  exception is the shoulder: `PlayerCamera` writes the `Camera` node's own H and V Offset. **Watch out
  for:** the host overwrites the real `Camera`'s FOV, and the wrapper's exports now forward through setters
  ([Phantom Camera](../camera.md#phantom-camera)); the addon moves `FollowCamera` under its spring arm, so the wrapper
  exports it as `follow_camera` (a path looked up after the move finds nothing). **Seen:** gdstudio #830, 2026-11-08;
  gdstudio #831 (the export, and the wrapper is a `@tool` script: [Phantom Camera](../camera.md#phantom-camera)).
- **Approach:** A second view is a `PhantomCamera3D` with a lower priority that a trigger raises (`CameraZone`); the
  blend is the lower camera's `tween_resource` (duration, transition, ease). **Watch out for:** the camera is
  only raised and lowered by the zone's two signals, so a zone that never reports the player leaves the view where it
  was. The spring arm keeps the lens out of a wall (in the north wall test the arm hit at 0.76 m of its 4.4 m and the
  lens stayed inside).
  **Seen:** gdstudio #821, 2026-11-08.
- The addon's updater window and network request are off in the template (`phantom_camera/updater/updater_mode=0`); a
  game that takes a new release replaces the folder and edits its licence entry. The addon is committed without its
  `examples/` and C# scripts, and every hook of the game's `pre-commit` and the kit's skips it (the addon's files have
  no final newline in places and its own style).

## The map components as scenes {#map-components}

<!-- new section: the six components were first scripts that built their children in code; #831 made them scenes -->

`Door`, `MovingPlatform`, `PhysicsProp`, `Pickup`, `TriggerZone` and `SpawnPoint` each hold their visible parts as nodes
of their own scene (the door's `Panel`, `Shape` and `Sensor`; the platform's `Mesh`, `Shape` and `EndPreview`; the
pickup's `Visual` and `Shape`; the trigger's `Shape` and `Plate`; the spawn point's `Marker`; a prop's crate, barrel and
ball), as `@tool` scripts that size them from the inspector. The platform's `EndPreview` is a translucent copy of the
slab at the far end (hidden in the game) and the door's sensor sphere is `auto_open_range`, so the editor shows the
travel and the reach; the spawn point's blue arrow is its `-Z`.

- **Approach:** Give each node's mesh, shape and material `resource_local_to_scene = true` in the component's scene, set
  the sizes from setters (looking nodes up with `get_node_or_null("%Panel")`, which works from an instance's own root
  and before `_ready`), and apply them again in `_ready`. **Watch out for:** without `local_to_scene` two doors share
  one `BoxMesh` and a resize of one resizes all (a test makes two and resizes one); a `PhysicsProp` with `shape = BALL`
  would save a generated sphere mesh into the level, so its three shapes are nodes and `shape` shows one. **Seen:**
  gdstudio #831, 2026-11-08.
- **Approach:** Read an `AnimatableBody3D`'s new transform after a `physics_frame` or two in a test, and set its place
  before it enters the tree. **Watch out for:** with `sync_to_physics` on, `global_position = x` read straight back gave
  the old position until the next step, so a door's `slide_distance` change and a test that moved a door and asked the
  interactor for it both saw the old place. **Seen:** gdstudio #831, 2026-11-08.

## Minimap {#minimap}

<!-- new section: #884 added the minimap; how it is built and what it costs are on [Minimap](../minimap.md) -->

The HUD's `MinimapSlot` holds the small `Minimap` (follows the character, turns with the camera); the rig's `MapLayer`
holds the `MapScreen` (`M`, the whole map). The player, pickups, targets and doors carry a `MinimapMarker`; the
workshop is a `MinimapSection`. `character_dressed.tscn` carries a `MinimapHeading` pointed at its `Model`, so the
player's arrow (and any dressed character's) shows where the model faces, not the body, which never turns. How it
works and what it costs: [Minimap](../minimap.md).

- **The inspector, on `Minimap`.** Nodes: `target`, `target_group`. Shape: `shape`, `map_size`, `max_screen_fraction`,
  `corner_ratio`. View: `range_m`, `range_min`, `range_max`, `zoom_step`, `zoom_smoothing`, `rotation_mode`, `turn_smoothing`,
  `follow_target`, `fixed_centre`, the two zoom actions. Map source: `source`, `image`, `image_world_rect`,
  the `live_*` settings of the camera source. Look: `background_color`,
  `border_color`, `border_width`, `edge_fade`, `opacity`, `tint_*`, `marker_scale`,
  `show_north`, `show_self`. Markers: `default_icon`, `default_edge_icon`, `hidden_kinds`, `pool_prewarm`,
  `max_markers`. Update: `map_update_rate`, `marker_update_rate`, `still_refresh_seconds`.
- **On `MinimapMarker`.** Look: `icon`, `color`, `size`, `rotates_with_node`, `kind`, `draw_order`. Edge:
  `clamp_to_edge`, `edge_inset`, `edge_icon`. Show: `active`, `rule`, `near_distance`, `revealed`, `height_fade`.
- **On `MinimapHeading`:** `turns` (the node that turns; empty: the parent), `front` (`MINUS_Z`, or `PLUS_Z`
  for the mannequin).
- **On `MinimapSection`:** `title`, `size`, `level`, `map_texture`. **On `MapScreen`:** `toggle_action`, `fit_bounds`,
  `fit_to_sections`, `fit_margin`, `fade_time`.

## The HUD {#hud}

<!-- new section: the HUD went from two loose nodes in a layer to regions, widgets and one theme (gdstudio #880) -->

How to use and extend it is in [The template HUD](../ui-layout.md#template-hud). In the inspector: on `Hud`, the group Look
(`theme`, `margin`), Phone (`min_text_size`, `max_scale`, `pixel_ratio`, `touch_controls`), Data (`player`) and Parts (`root`,
`safe_area`, `minimap_slot`); on every part the group Data (`player`, `hide_without_data`) and Phone (`touch_region`);
on a `HudStat` the Data (`source`, `value_property`, `max_property`, `extra_property`, `refresh_signals`), Look
(`title`, `show_title`, `show_bar`, the three formats, `low_share`, `low_color`) and Parts groups; on `ItemCounter` the
`separator`. The ammo part reads the weapon's `ammo`, `magazine_size` and, as its `extra_property`, `reserve`, shown
`magazine | reserve` (`extra_format`), and hides for the fists, whose definition has no magazine ([Ammo, reloading and
switching](shooting.md#weapons)); the player has no health yet, so that part stays hidden until the hit zones (#876)
make `health`/`max_health` exist, and `tools/capture/hud_tour.tscn` shows it fed by a stand-in.

Cost, measured in Compatibility on Windows (an RTX 5080, vsync off, 150 frames after 150 of warm-up): the game with the
HUD hidden draws 109 calls at 0.48 ms CPU and 0.27 ms GPU, and with the coin counter, health, ammo and the crosshair all
showing it draws 118 calls at 0.54 ms and 0.29 ms (about 9 calls, 0.05 ms CPU, 0.015 ms GPU). The HUD is local: nothing
in it is sent over a network.

**The weapon slots and the hotbar** (gdstudio #1148) are two rows of `HudSlot` places (`hud_slot.tscn`: `IconMargin/Icon`,
`Key`, `Count`), made by their row from `cell_scene` because their number is a setting (the editor shows them, a `@tool`
script): `HudWeaponSlots` (`hud_weapon_slots.tscn`, under the ammo card) shows the first `place_count` weapons of the
loadout's round with the one in hand (or asked for) lit, and `HudHotbar` (`hud_hotbar.tscn`, bottom middle) shows the
player's `Hotbar` ([The hotbar](../inventory.md#hotbar)). A place shows the first key of its action (`weapon_1`,
`hotbar_1`: a rebound key shows the new one), an empty place its key alone. The look is the theme's variations
`HudSlot`, `HudSlotLit`, `HudSlotEmpty` (with an `icon_color` each), `HudSlotKey` and `HudSlotKeyLit`. On a touch screen
each place is a place a finger presses (`touch_zones()`, through `Hud.touch_zones()` to the touch layer), and every
place is at least 44 CSS pixels (84 units: the HUD's phone scale makes them 45 on an 844 x 390 and a 667 x 375 page).
In the inspector: on both rows Keys (`action_format`, `first_key_number`), Parts (`row`, `cell_scene`) and Phone
(`touch_region`: the slots `BottomLeft`, the hotbar `TopLeft`); `HudWeaponSlots` Places (`place_count` 2);
`HudHotbar` Look (`flash_time` 0.3 s, `flash_scale` 1.15) and Places (`editor_places` 4, the editor's count; the game's
is the `Hotbar`'s); on `HudSlot` Look (`panel_variations`, `key_variation`, `key_variation_lit`, `spent_alpha` 0.35) and
Parts. Cost, measured as above on the same machine (1920 x 1080, 150 frames): the six places add about 24 draw calls
(285 against 261 with them hidden) and 0.04 ms of CPU; the GPU time did not move past its noise.

- **Approach:** Give a part its player in one place: `Hud.player` points every part that has none (or had the old one)
  at the rig's `Player`, and a part given its own `player` keeps it. **Watch out for:** a first version bound every part
  to `Hud.player` on `add_widget` and overwrote the stand-in subjects the HUD tests had set, 15 of 15 cases failed; bind
  only the parts with no player of their own. **Seen:** gdstudio #927, 2026-11-10.

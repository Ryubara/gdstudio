# The camera, screen and map parts

<!-- new section: the template page's table of parts reached the size limit (#1457); each row's place and
     notes moved here, for the camera, the screen, the menus and the map -->

The full row of each part of [the 3D Third Person template](../third-person-template.md#what-is-in-it), moved from its
table of parts (#1457): where it lives (in `templates/3d-third-person/game/`, the base in `templates/3d-blank/game/`),
what it does, its inspector and the pages with the rest. What the player sees and touches, and the map it plays on: the
camera and its shake, the HUD, touch controls, menus, the inventory and the minimap, the scene map and the map, the
physics layers and the web build's program list. A new inspector line goes in its part's section here.

## Camera {#camera-part}

**Where:** `gameplay/player/player_camera.gd`, `gameplay/camera_zone/`

A wrapper on a Phantom Camera in Third Person follow mode, with a sprint zoom and shake, an aim view, a fire view and a
shot kick blended on its framing (the shared `CameraShake`, next row); a zone that raises a second camera's priority.
The distance is on `PlayerCamera`; the over-the-shoulder view is the `Camera` node's H and V Offset, set from
`PlayerCamera`'s Shoulder group (left, center, right; the middle mouse button swaps). An aimed swap at a character keeps
the point on the crosshair (inspector, Shoulder swap: `aim_shoulder_time`, `keep_aim_on_swap`,
`keep_aim_when_not_aiming`, `swap_anchor_strength`, `swap_look`, `swap_release_angle`, `aim_point_range`,
`aim_point_min_distance`, `aim_point_mask`, `keep_aim_layers`, `shoulder_time`; defaults on the linked page). [Keeping
the aim through a shoulder swap](../camera.md#shoulder-swap-aim).

## Camera shake {#camera-shake-part}

**Where:** `core/camera_shake/presets/*.tres` (in 3D Blank, for every template); the scripts `CameraShake` and
`ShakePreset` are the synced `addons/gds_game/camera_shake/`

A `CameraShake` node under `PlayerCamera` and `ShakePreset` resources: `CameraShake.shake(preset, at)` shakes the view
from anywhere, with falloff with distance and one global `CameraShake.strength` (the player's Settings > Controls >
Camera shake, 0 to 100 %); the sprint shake and the shot kick are on it, 0 by default. A `NearHitShake` beside it
(`gameplay/player/near_hit_shake.gd`, preset `core/camera_shake/presets/near_hit.tres`) shakes the view for a hit near
the camera, offline and online (inspector: `enabled`, `preset`, `strength`, `shaker`, `impacts`). [Camera: shake
component](../camera.md#shake-component).

## HUD {#hud-part}

**Where:** `ui/hud/`

`hud.tscn` (regions, one theme `hud_theme.tres`), `HudWidget` (binds to the player, hides without data), the coin
counter, the crosshair, health and ammo (`HudStat`: show only when the player and its weapon have the data), a slot for
the minimap, and two rows of numbered places (`HudSlotRow`): the weapon slots (1 and 2, the one in hand lit) and the
hotbar (3 to 6, the player's `Hotbar`), pressed by their keys or a finger. [The HUD](camera-and-ui.md#hud), [the
hotbar](../inventory.md#hotbar).

## Touch controls {#touch-controls-part}

**Where:** `ui/touch/` (in 3D Blank, for every template)

Real `Control` nodes in `touch_controls.tscn` (a stick, two zones, buttons you drag in the 2D editor) that press the
game's actions; the script only reads their places. 3D Third Person adds the Fire, Aim, Crouch, Prone and Melee buttons
in `third_person_touch_controls.tscn`, a scene that inherits the base's.

## Menus {#menus-part}

**Where:** `ui/menus/`, `core/settings/`

Main, pause and settings menus, saved options: [Menus](../menus.md#menus). Their sounds are the `MenuSounds` autoload
(`ui/menus/menu_sound_service.tscn`): one `AudioStreamPlayer` a sound on `UI`, picked by a table of roles and cues.

Inspector: `MenuSoundService` `enabled`, `hint_gap`, `quiet_after_action`, `tick_gap`, `tick_pitch`, and each player's
`stream`, `volume_db` and `pitch_scale`; a control's `ui_sound_role` metadata (`tab`, `back`) overrides its own role.
[Menu sounds](../audio.md#menu-sounds).

## Inventory {#inventory-part}

**Where:** `ui/inventory/` (the screen, its slot, the model preview), the `Inventory` node of
`gameplay/player/player.tscn` (script: the synced `addons/gds_game/inventory/`), `gameplay/inventory/` (the coin and
bandage `ItemDef`s), `gameplay/weapon/weapon_chooser.gd`, the `Hotbar` node (script:
`addons/gds_game/inventory/hotbar.gd`), `gameplay/player/quick_keys.gd`

I, a pad's right shoulder or the touch Bag button open it on the screen host: the live model (turned by a drag or the
right stick), the loadout's weapons (pressing one switches by the ordinary weapon presses,
`PlayerInput.request_weapon`), the hotbar's places (drag a bag slot on one, or press its key on a bag slot), a 16-slot
bag (pick up and put down, drag, Drop). Keys 1 and 2 take the HUD's weapon slots in hand, 3 to 6 use a hotbar place (the
bandage heals 25: `ItemDef.use_effect`, a `HealEffect`).

Inspector: `Hotbar` `place_count`, `start_items`, `inventory`, `user`, `authoritative`; `ItemDef` `use_effect`,
`consumed_on_use`; `HealEffect` `amount`, `only_when_hurt`; `Inventory` `slot_count`, `start_items`, `catalog`,
`collector`, `collect_signal`, `drop_origin`, `drop_offset`, `drop_parent`; `InventoryScreen` `player`, `cell_scene`,
`pause_setting`, `pauses_by_default`, `stop_player_input`; `DetailText` `lines`; `ModelPreview` `preview_layer`,
`distance`, `camera_height`, `look_height`, `field_of_view`, `start_angle`, `drag_turn`, `stick_turn`, `max_height`,
`msaa`. [Inventory](../inventory.md#template-screen).

## Minimap {#minimap-part}

**Where:** `ui/minimap/` (the widget, the full-screen map), `core/minimap/` (`MinimapMarker`, `MinimapHeading`,
`MinimapSection`)

A round map that follows the character and a full-screen map on `M`; a marker component any node carries, and a heading
component (inspector: `turns`, `front`) on the dressed character that says its model's facing, found by type, never by a
method name. [Minimap](camera-and-ui.md#minimap).

## Scene map {#scene-map-part}

**Where:** `main.tscn`, `world/world.tscn`, `ui/player_rig/player_rig.tscn`, `ui/hud/hud.tscn`,
`ui/menus/screen_host.tscn`

`main.tscn` holds four instances and three wires, nothing else; open the one scene a feature lives in. [Which scene to
open](../third-person-template.md#scene-map).

## The map {#the-map-part}

**Where:** `world/`, `gameplay/` (the six components; `TriggerZone`'s and `SpawnPoint`'s scripts are the synced
`addons/gds_game/`)

The #788 prototype map, a spawn point, a camera zone and two [map sections](../map-sections.md); `ProtoBlock` makes the
solids.

## Physics layers {#physics-layers-part}

**Where:** `core/physics_layers/` (in 3D Blank), `project.godot` `[layer_names]`

Eight layers (World, Characters, Projectiles, Props, Ragdoll, Hit Zones, Sensors, Shot Hulls) and `PhysicsLayers` with
the masks; characters pass each other: [Physics layers](../physics-layers.md#template-layers).

## Web program list {#web-program-list-part}

**Where:** `assets/shaders/web/shader_programs.json`, `tools/web_smoke/shader_programs.py`

The GL programs the web build links, recorded from a browser run; the export serves them beside `index.html` and the
page links them at once before the engine boots (21 s to about 6 s to the last link on a cold GPU browser), the menu
scene starting them for a page without them; CI fails when the build links more than 10 programs the list lacks.

Inspector: `MenuScene` `shader_programs` (the same file as the project setting `gds_game/shader_prelink/list`). Record
it again when a material, a shader, the lights or the pinned Godot change: [Linking every program at
once](../first-use-hitches.md#prelink).

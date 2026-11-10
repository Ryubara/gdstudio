# The 3D Third Person template

<!-- new section: the new-game page lists the templates; nothing held how the character template is built -->

How the template's character is built and what Godot 4.7.2 did on the way: a `CharacterBody3D`
controller, a Phantom Camera third-person view, touch controls for phones and a Quaternius mannequin animated with the
Universal Animation Library 1 and 2. What a game made from it holds is in its own
`docs/design/character.md`; the template list is [A new game from a template](new-game.md#the-templates). Measured on
Windows, an RTX 5080, Godot 4.7.2, and in headless Chromium on SwiftShader.

## What is in it {#what-is-in-it}

| Part | Where (in `templates/3d-third-person/game/`, the base in `templates/3d-blank/game/`) | Notes |
| --- | --- | --- |
| Character | `gameplay/character/` (`character.gd` + `character.tscn`, `character_dressed.tscn`, `character_controller.gd`, `character_state.gd`, `character_tuning.gd`, `step_climber.gd`, `interactor.gd`) | `Character` is the body whoever drives it: it is moved by `step(command, delta)` alone and reads no input and no camera. `character.tscn` is the body alone (capsule, eye point, interactor, a weapon with no muzzle: what a server loads), `character_dressed.tscn` inherits it and adds the model, animation, footsteps and ragdoll at the same node paths ([a second kind of controller](third-person/character.md#second-controller)). One resource (`CharacterTuning`) holds every tuned number. Signals: `jumped`, `landed`, `took_hit`, `health_changed`, `hit_received`, `interacted`, `item_collected`, `state_changed`, `teleported`, `aim_changed`, `crouch_changed`, `vault_started`, `prone_changed`, `died`, `revived`, `fell`. Health and hits: [Hit zones](third-person-hits.md). Crouch, aim and shoot: [below](third-person/shooting.md#crouch-aim-shoot). |
| Player | `gameplay/player/` (`player.gd` + `player.tscn`, `player_input.gd`, `player_command.gd`, `player_tuning.tres`) | `Player` extends `Character`: `player.tscn` inherits the dressed character and adds `PlayerInput`, the one reader of the actions and the camera. The player joins the group `player` (the HUD, the minimap and a camera zone look for it; another character is not taken for it), starts at a `SpawnPoint` of that group and again when it says `fell`, and holds `input_enabled` and `ragdoll_key`. Signals: `jumped`, `landed`, `took_hit`, `interacted`, `item_collected`, `state_changed`, `teleported`, `aim_changed`, `crouch_changed`, `prone_changed`, `died`, `revived`, `fell`. Crouch, aim and shoot: [below](third-person/shooting.md#crouch-aim-shoot). |
| Prone | `gameplay/character/character_prone.gd`, `prone_tuning.gd`, `gameplay/player/prone_tuning.tres` | Lying down and the crawl, a module of its own driven by the command's `prone` bit (Z, d-pad down, the Prone button). The inspector (`Character` > Prone > `prone_tuning`): Crawl `crawl_speed` 1.0 m/s, `backward_share` 0.7, `sideways_share` 0.8, `acceleration` 10, `deceleration` 12, `turn_speed` 3, `move_while_changing` off; Getting down and up `enter_time` 0.5 s, `exit_time` 0.7 s, `air_time` 0.15 s; Body `height` 0.6 m, `radius` 0.28 m, `camera_height` 0.55 m; Aim `aim_allowed`, `fire_allowed`, `spread_share` 0.5, `aim_move_share` 0.5, `aim_turn_speed` 6, `look_up_limit` 12, `look_down_limit` 40; Input `input_mode` (toggle, hold, hold crouch), `crouch_hold_time` 0.5 s, `jump_gets_up`, `sprint_gets_up`. On `Animation` > Prone: the clips, `prone_idle_pace`, `crawl_clip_speed` and the placeholder pose. [Prone and the crawl](third-person/character.md#prone). |
| Vaulting and mantling | `gameplay/character/character_vault.gd`, `vault_settings.tres`; the scripts `Vaultable`, `VaultSettings`, `VaultProbe` and `VaultPlan` are the synced `addons/gds_game/traversal/`; the map's `VaultCourse` | Jump at a wall that carries a `Vaultable` vaults over it or mantles onto it, by its measured height, depth and landing room; a wall without one is only jumped. Inspector: the `Vaultable` (allowed moves, faces, height and depth overrides, clips), `vault_settings.tres` (Trigger, Detection, Vault, Mantle, Body groups) and `Animation`'s Traversal clips. [Vaulting and mantling](third-person/traversal.md). |
| Model | `gameplay/character/character_model.gd` | `Model` is a slot (a `Node3D`) that holds the glb and the pistol seat; replace the glb under it: [Replacing the model](third-person/character.md#replacing-the-model). |
| Animation | `gameplay/character/character_animation.gd`, `character_clips.gd` | An `AnimationTree` built in code (also in the editor, as a `@tool` script): a body state machine, a pistol layer (the grip on one hand, the aim pose on the upper body) and a one-shot action layer. The carry is an inspector choice ([Crouch, aim and shoot](third-person/shooting.md#crouch-aim-shoot)). `CharacterClips.ALL` names all 86 clips. |
| Camera | `gameplay/player/player_camera.gd`, `gameplay/camera_zone/` | A thin wrapper on a Phantom Camera in Third Person follow mode, with a sprint zoom and shake, an aim view, a fire view and a shot kick blended on its framing (the shakes are the shared `CameraShake`, next row); a zone that raises a second camera's priority. The distance is on `PlayerCamera`; the over-the-shoulder view is the `Camera` node's H and V Offset, set from `PlayerCamera`'s Shoulder group (left, center, right; Q swaps). |
| Camera shake | `core/camera_shake/presets/*.tres` (in 3D Blank, for every template); the scripts `CameraShake` and `ShakePreset` are the synced `addons/gds_game/camera_shake/` | A `CameraShake` node under `PlayerCamera` and `ShakePreset` resources: `CameraShake.shake(preset, at)` shakes the view from anywhere, with falloff with distance and one global `CameraShake.strength`; the sprint shake and the shot kick are on it, 0 by default. [Camera: shake component](camera.md#shake-component). |
| Weapon | `gameplay/weapon/`, `gameplay/projectile/`, `gameplay/target/` | A `Weapon` fires `Projectile` spheres from a muzzle marker along the ray its character hands it (the human's crosshair, an AI's look; it reads no camera, and with no muzzle it fires from `no_muzzle_offset` beside its `shooter`); its cooldown is counted by `tick()` (`self_ticking` for a weapon alone). A `Target` falls over when hit. The `Crosshair` is `ui/hud/crosshair.tscn`. |
| HUD | `ui/hud/` | `hud.tscn` (regions, one theme `hud_theme.tres`), `HudWidget` (binds to the player, hides without data), the coin counter, the crosshair, health and ammo (`HudStat`: show only when the player and its weapon have the data) and a slot for the minimap. [The HUD](third-person/camera-and-ui.md#hud). |
| Hit zones | `gameplay/hit_zones/` (`HitZones`, `HitZone`, `HitRecord`), `gameplay/character/hit_reaction.gd` | Eleven body parts on the skeleton a shot finds once it meets the capsule, each with a damage multiplier; health and a death that carries the shot into the ragdoll, a flinch for a hit that does not kill, pushes and marks on a lying body; one small `HitRecord` is all a network sends. [Hit zones](third-person-hits.md). |
| Impacts | `gameplay/impacts/` (`impacts.tscn` in `world/world.tscn`; scripts in the synced `addons/gds_game/impacts/`), `assets/shaders/impacts/`, `assets/materials/impacts/`, `assets/audio/impacts/` | Where a shot lands: a mark on what it hit (it rides a moved or pushed body and goes with a freed one), an effect and a sound, picked by the kind of surface. [Bullet impacts](third-person/shooting.md#impacts). |
| Effects | `gameplay/effects/effect_emitter.tscn`, scripts in the synced `addons/gds_game/effects/` | One pooled player of one-shot effects (muzzle flash, impacts). [Effects](third-person/shooting.md#effects). |
| Sound | `gameplay/character/footsteps.tscn`, `gameplay/pickup/pickup.tscn`, `world/world.tscn` | `Footsteps` follows the skeleton's feet (from the `Model` slot), a `Pickup` plays its coin, `Wind` plays the bed on `Ambient`; every player is on a bus ([Audio](audio.md#template-buses)). |
| Touch controls | `ui/touch/` (in 3D Blank, for every template) | Real `Control` nodes in `touch_controls.tscn` (a stick, two zones, buttons you drag in the 2D editor) that press the game's actions; the script only reads their places. 3D Third Person adds the Fire, Aim, Crouch and Prone buttons in `third_person_touch_controls.tscn`, a scene that inherits the base's. |
| Menus | `ui/menus/`, `core/settings/` | Main, pause and settings menus, saved options: [Menus](menus.md#menus). |
| Assets | `assets/characters/mannequin/` (`mannequin_female.glb`, the default, and `mannequin_male.glb`), `assets/animation/universal/` | CC0, each folder with a `LICENSE.md`; [the two mannequins](third-person/character.md#mannequins). |
| Ragdoll | `gameplay/character/character_ragdoll.gd`, `ragdoll_braces.gd`, `Character.die()` / `revive()` | Death as a hybrid: an animated capsule while alive, physical bones generated on the model's skeleton on the first death, a blend back on getting up. Y or the `ragdoll` checkbox; runs on Jolt. [Ragdoll](third-person/character.md#ragdoll). |
| Minimap | `ui/minimap/` (the widget, the full-screen map), `core/minimap/` (`MinimapMarker`, `MinimapSection`) | A round map that follows the character and a full-screen map on `M`; a marker component any node carries. [Minimap](third-person/camera-and-ui.md#minimap). |
| Pistol | `assets/weapons/pistol/` | GDStudio's own (MIT, from Deadnight's build script), 692 triangles, one palette material; `pistol_held.tscn` seats it on `hand_r` for the six pistol clips ([Weapons](../../tools/blender/weapons.md#the-third-person-template-pistol)). |
| Net packets and link | `gameplay/net/` (the packets; `NetLink`, `WebSocketLink`, `WsListener`, `LoopbackLink`, `LinkConditioner`), `tools/net/`, `ui/probe/net_probe.gd` | The bytes of online play ([packets](multiplayer.md#template-packets)) and the transport under them: a WebSocket client (desktop and web), the server's listener, an in-process pair and a bad network around any of them; polled each physics tick; no inspector (code objects). [The template's transport](multiplayer.md#template-transport). |
| Rifle | `assets/weapons/rifle/` | GDStudio's own (MIT, Deadnight's M4A1 build), 1,236 triangles and a 420-triangle far level, one palette material; sockets `Grip`, `Support`, `Trigger`, `Muzzle`, `Eject`, `Butt`, the `Magazine` and `Bolt` as their own nodes; `rifle.tscn` swaps to the far level at 10 m. A model for the weapon work, not yet held: the hold proposal is in its README ([Weapons](../../tools/blender/weapons.md#the-third-person-template-pistol)). |
| Physics layers | `core/physics_layers/` (in 3D Blank), `project.godot` `[layer_names]` | Seven named layers (World, Characters, Projectiles, Props, Ragdoll, Hit Zones, Sensors) and `PhysicsLayers` with the masks; characters do not block each other: [Physics layers](physics-layers.md#template-layers). |
| Scene map | `main.tscn`, `world/world.tscn`, `ui/player_rig/player_rig.tscn`, `ui/hud/hud.tscn`, `ui/menus/screen_host.tscn` | `main.tscn` holds four instances and three wires, nothing else; open the one scene a feature lives in. [Which scene to open](#scene-map). |
| The map | `world/`, `gameplay/` (the six components; `TriggerZone`'s and `SpawnPoint`'s scripts are the synced `addons/gds_game/`) | The #788 prototype map, a spawn point, a camera zone and two [map sections](map-sections.md); `ProtoBlock` makes the solids. |

Measured in Compatibility on the desktop (vsync off, 300 frames after 150 of warm-up): the map alone from the overview
camera 0.34 ms CPU, 0.19 ms GPU, 145 draw calls, 84.4 MB of texture memory; with the character 0.38 / 0.21 ms, 149
draw calls, the same texture memory (the mannequin has two flat materials and no texture) and 1.9 MB more video memory.
The whole game from the third-person camera draws 64 calls. The trimmed 3D Blank (floor and walls) is 0.17 / 0.16 ms,
10 draw calls and 64.2 MB. Forward+ is 0.21 / 0.68 ms and 348 MB for the character in the map. The web export is a
0.92 MB `index.pck` for 3D Blank and 3.26 MB for 3D Third Person (the character and the two libraries are most of the
difference), and both load in headless Chromium with no console error, page error or failed request (a SwiftShader
frame is about 39 ms for 3D Blank and 67 ms for 3D Third Person, which only says it runs with no GPU).

## Which scene to open {#scene-map}

<!-- new section: main.tscn held every node of the game, so each feature edited the same lines (gdstudio #927);
     nothing said where a part now lives -->

`main.tscn` is the game scene the menu loads. It holds four instances and the wires between them, and a test fails when
it holds anything else (`tests/test_main_scene.gd`), so a feature adds its node to the scene it belongs to and never to
this file.

| Open | For | Holds |
| --- | --- | --- |
| `world/world.tscn` | the map and what the map does by itself | `Level`, the two sections (`AISection`, `PathingSection`), `Impacts`, `Effects`, the `Wind` player and `AudioSettings` |
| `ui/player_rig/player_rig.tscn` | one local player's body, camera and input | `Player`, `PlayerCamera` with its Phantom Camera, the `Camera` and its host, `TouchControls` (its `look_turned` turns the camera inside the scene), `LookSettings`, the pause button in `MenuLayer`, the full-screen map in `MapLayer`; at run time a `WebProbe` on a page opened with `?probe` |
| `ui/hud/hud.tscn` | the heads-up display | the `Hud` and its parts; `player` names the player the parts read |
| `ui/menus/screen_host.tscn` | the host that opens the pause menu and other screens | the `ScreenHost` with its pause screen |

The wires in `main.tscn`: `Hud.player` and `Hud.touch_controls` point into the rig, and the host's `opened` and `closed`
call the touch layer's `suspend` and `resume`. A second local or networked player is a second instance of the rig. The
rig is in `ui/` because it holds the touch layer, and a scene may only name folders at its own level or below
([the layer rule](project-conventions.md#rules)); the world is in `world/`. A weapon puts its projectiles under the
shooter's parent, which is the rig now, not `Main`.

- **Approach:** Put a new node in the scene it belongs to (a prop or a system the map owns in `world.tscn`, a thing the
  local player carries in `player_rig.tscn`, a HUD part in `hud.tscn`) and reach across scenes with an export or a
  signal connection in `main.tscn`, not with a node there. **Watch out for:** a test, tour or capture that finds a node
  by `get_node("Player")` from the game scene breaks when the node moves into an instance (16 suites and 11 tours named
  `Player`, `Level`, `Camera` and the rest at the top); the path is now `PlayerRig/Player`, `World/Level`, and a
  `CanvasLayer` that moves out of `main.tscn` keeps its draw order only if its `layer` is set (the pause button's
  `MenuLayer` is layer 2, above the HUD). **Seen:** gdstudio #927, 2026-11-10.

## Where the rest is {#moved}

<!-- new section: the page was split at the size limit; moved anchors stay here so links resolve -->

The page is split by subject (#983). Each section below moved to a subpage; the link is its new place.

### The animation libraries {#animation-libraries}

Moved: [The animation libraries](third-person/character.md#animation-libraries).

### The two mannequins {#mannequins}

Moved: [The two mannequins](third-person/character.md#mannequins).

### Replacing the model {#replacing-the-model}

Moved: [Replacing the model](third-person/character.md#replacing-the-model).

### The character controller {#controller}

Moved: [The character controller](third-person/character.md#controller).

### Phantom Camera in a third-person follow {#phantom-camera}

Moved: [Phantom Camera in a third-person follow](third-person/camera-and-ui.md#phantom-camera).

### The map components as scenes {#map-components}

Moved: [The map components as scenes](third-person/camera-and-ui.md#map-components).

### Crouch, aim and shoot {#crouch-aim-shoot}

Moved: [Crouch, aim and shoot](third-person/shooting.md#crouch-aim-shoot).

### Bullet impacts {#impacts}

Moved: [Bullet impacts](third-person/shooting.md#impacts).

### Effects and the muzzle flash {#effects}

Moved: [Effects and the muzzle flash](third-person/shooting.md#effects).

### Minimap {#minimap}

Moved: [Minimap](third-person/camera-and-ui.md#minimap).

### Ragdoll {#ragdoll}

Moved: [Ragdoll](third-person/character.md#ragdoll).

### Touch controls {#touch-controls}

Moved: [Touch controls](third-person/character.md#touch-controls).

### The HUD {#hud}

Moved: [The HUD](third-person/camera-and-ui.md#hud).

## A route for a clip {#walkthrough}

<!-- new section: nothing said how a character is filmed through a map without a person -->

- **Approach:** Film a character with an autopilot that presses the same input actions a player would and turns the
  camera with the same `orbit()` the mouse uses, over a list of waypoints with a jump distance, and give each waypoint a
  "stuck for 2 s" exit. **Watch out for:** the first route went through a 1 m wall (the low wall by the gate) and the
  clip was 25 s of a character running into it; read a contact sheet of the clip before calling it done. The movie is
  the same every run (the mp4 had the same size twice). **Seen:** gdstudio #821, 2026-11-08
  (`tools/capture/walkthrough.tscn`: gate, four coins up the jump blocks, the props, the room's door).

# The 3D Third Person template

<!-- new section: the new-game page lists the templates; nothing held how the character template is built -->

How the template's character is built and what Godot 4.7.2 did on the way: a `CharacterBody3D`
controller, a Phantom Camera third-person view, touch controls for phones and a Quaternius mannequin animated with the
Universal Animation Library 1 and 2. What a game made from it holds is in its own
`docs/design/character.md`; the template list is [A new game from a template](new-game.md#the-templates). Measured on
Windows, an RTX 5080, Godot 4.7.2, and in headless Chromium on SwiftShader.

## What is in it {#what-is-in-it}

One line a part; each part's section on its subpage has where it lives in full, its notes, its inspector and its links:
[the character](third-person/body-parts.md), [the weapons](third-person/weapon-parts.md), [the camera, screen and
map](third-person/screen-parts.md) and [the AI and online play](third-person/online-parts.md) (#1457). A new inspector
line goes on the part's subpage, not here.

| Part | Where (in `templates/3d-third-person/game/`, the base in `templates/3d-blank/game/`) | What it is |
| --- | --- | --- |
| [Character](third-person/body-parts.md#character-part) | `gameplay/character/` | The body whoever drives it, moved by `step(command, delta)` alone, and its modules. |
| [Player](third-person/body-parts.md#player-part) | `gameplay/player/` | `Player` extends `Character` and adds `PlayerInput`, the one reader of the actions and the camera. |
| [Prone](third-person/body-parts.md#prone-part) | `gameplay/character/character_prone.gd` | Lying down and the crawl, a module driven by the command's `prone` bit. |
| [Slide](third-person/body-parts.md#slide-part) | `gameplay/character/character_slide.gd` | Crouch pressed at a sprint slides; every number in `SlideTuning`. |
| [Vaulting and mantling](third-person/body-parts.md#vaulting-and-mantling-part) | `gameplay/character/character_vault.gd` | Jump at a `Vaultable` wall vaults over it or mantles onto it. |
| [Model](third-person/body-parts.md#model-part) | `gameplay/character/character_model.gd` | The `Model` slot that holds the glb and the pistol seat. |
| [Animation](third-person/body-parts.md#animation-part) | `gameplay/character/character_animation.gd` | The `AnimationTree` built in code: body states, the weapon layer and the gaits. |
| [Camera](third-person/screen-parts.md#camera-part) | `gameplay/player/player_camera.gd` | The Phantom Camera follow with sprint zoom, aim and fire views and the shot kick. |
| [Camera shake](third-person/screen-parts.md#camera-shake-part) | `core/camera_shake/` | `CameraShake.shake(preset, at)` and the `ShakePreset` resources. |
| [Weapon](third-person/weapon-parts.md#weapon-part) | `gameplay/weapon/` | `WeaponDef`, the `Weapon` node, the loadout, melee, fire modes and the rifle's `RifleHeld`. |
| [HUD](third-person/screen-parts.md#hud-part) | `ui/hud/` | `hud.tscn`, `HudWidget` and the counters, crosshair and stats. |
| [Hit zones](third-person/body-parts.md#hit-zones-part) | `gameplay/hit_zones/` | Eleven body parts with damage multipliers, the flinch and the death into the ragdoll. |
| [Health and using things](third-person/body-parts.md#health-and-using-things-part) | `addons/gds_game/hits/`, `interact/` | The `Health` and `Interactable` components as nodes. |
| [Impacts](third-person/weapon-parts.md#impacts-part) | `gameplay/impacts/` | The mark, effect and sound where a shot lands, by surface. |
| [Effects](third-person/weapon-parts.md#effects-part) | `gameplay/effects/` | The pooled one-shot effects and the hitscan tracers. |
| [Weapon pickup](third-person/weapon-parts.md#weapon-pickup-part) | `gameplay/pickup/` | A floating, turning weapon that gives its weapon or rounds and comes back. |
| [Sound](third-person/body-parts.md#sound-part) | `gameplay/character/footsteps.tscn` | Footsteps from the skeleton's feet, the pickup's and the world's sounds. |
| [Touch controls](third-person/screen-parts.md#touch-controls-part) | `ui/touch/` | Real `Control` nodes that press the game's actions, and the template's buttons. |
| [Menus](third-person/screen-parts.md#menus-part) | `ui/menus/`, `core/settings/` | Main, pause and settings menus, saved options and `MenuSounds`. |
| [Web program list](third-person/screen-parts.md#web-program-list-part) | `assets/shaders/web/` | The GL programs the web build links before the engine boots. |
| [Inventory](third-person/screen-parts.md#inventory-part) | `ui/inventory/` | The inventory screen: the live model, the loadout's weapons and the items. |
| [Assets](third-person/body-parts.md#assets-part) | `assets/` | The prototype bodies, the clip libraries and the third-party folders with their licences. |
| [AI characters](third-person/online-parts.md#ai-characters-part) | `gameplay/ai/` | The `AiCharacter` base, senses, navigator, tasks, brain, director, factions and the soak. |
| [Peek lean](third-person/body-parts.md#peek-lean-part) | `gameplay/character/peek/` | Q and E tilt the body from the hips; stepped, predicted, sent. |
| [Ragdoll](third-person/body-parts.md#ragdoll-part) | `gameplay/character/character_ragdoll.gd` | Death as a hybrid: physical bones on the first death, a blend back up. |
| [Minimap](third-person/screen-parts.md#minimap-part) | `ui/minimap/`, `core/minimap/` | The round map, the full-screen map and the marker and heading components. |
| [Pistol](third-person/weapon-parts.md#pistol-part) | `assets/weapons/pistol/` | GDStudio's own pistol model, its sockets and `pistol_held.tscn`. |
| [Prototype mannequins](third-person/body-parts.md#prototype-mannequins-part) | `assets/characters/prototype/` | GDStudio's own bodies on the library's rig, with twist bones and sockets. |
| [Weapon hold](third-person/weapon-parts.md#weapon-hold-part) | `gameplay/weapon/hold/` | The hands closed on the pistol after the clips: fingers, trigger and the support hand. |
| [Slide rack](third-person/weapon-parts.md#slide-rack-part) | `assets/animation/pistol/` | The `Pistol_Rack` clip and the `SlideRack` resource a body. |
| [Aim layer](third-person/body-parts.md#aim-layer-part) | `gameplay/character/aim/` | Points the held weapon at the aim in every move, after the clips. |
| [Net packets and link](third-person/online-parts.md#net-packets-and-link-part) | `gameplay/net/` | The packets of online play and the transport under them. |
| [Game server](third-person/online-parts.md#game-server-part) | `gameplay/net/net_server.gd` | The headless server that admits and steps the players and sends the TICK. |
| [Server image](third-person/online-parts.md#server-image-part) | `server/` | The game server as a Docker image and its deploy to Railway. |
| [Online client](third-person/online-parts.md#online-client-part) | `gameplay/net/net_client.gd` | The predicting client, its reconciler and stall guard, and the other players. |
| [Online game](third-person/online-parts.md#online-game-part) | `online_main.tscn` | The offline game with a `NetClient`, `RemotePlayers` and the join overlay. |
| [Online shots](third-person/online-parts.md#online-shots-part) | `gameplay/net/server_combat.gd` | The server owns every shot, hit and health; each screen plays the events. |
| [Networked map parts](third-person/online-parts.md#networked-map-parts-part) | `gameplay/net/net_entity.tscn` | Doors, platforms, pickups, props and targets the server owns. |
| [Rifle](third-person/weapon-parts.md#rifle-part) | `assets/weapons/rifle/` | GDStudio's own rifle model, its far level and sockets. |
| [Physics layers](third-person/screen-parts.md#physics-layers-part) | `core/physics_layers/` | Eight layers and `PhysicsLayers` with the masks. |
| [Scene map](third-person/screen-parts.md#scene-map-part) | `main.tscn` | Four instances and three wires; open the one scene a feature lives in. |
| [The map](third-person/screen-parts.md#the-map-part) | `world/` | The prototype map, a spawn point, a camera zone and two map sections. |

What the map, the character and the web export cost to draw and load: [the draw cost](third-person/character.md#draw-cost).

## Which scene to open {#scene-map}

<!-- new section: main.tscn held every node of the game, so each feature edited the same lines (gdstudio #927);
     nothing said where a part now lives -->

`main.tscn` is the game scene the menu loads. It holds four instances and the wires between them, and a test fails when
it holds anything else (`tests/test_main_scene.gd`), so a feature adds its node to the scene it belongs to and never to
this file.

| Open | For | Holds |
| --- | --- | --- |
| `world/world.tscn` | the map and what the map does by itself | `Level`, the two sections (`AISection`, `PathingSection`), `Impacts`, `Effects`, `Tracers`, the `Wind` player and `AudioSettings` |
| `ui/player_rig/player_rig.tscn` | one local player's body, camera and input | `Player`, `PlayerCamera` with its Phantom Camera, the `Camera` and its host, `TouchControls` (its `look_turned` turns the camera inside the scene), `LookSettings`, the pause button in `MenuLayer`, the full-screen map in `MapLayer`; at run time a `WebProbe` on a page opened with `?probe`, a `NetProbe` with `?netprobe` and a `NetPlayProbe` with `?netplay` |
| `ui/hud/hud.tscn` | the heads-up display | the `Hud` and its parts; `player` names the player the parts read |
| `ui/menus/screen_host.tscn` | the host that opens the pause menu and other screens | the `ScreenHost` with its pause screen and the inventory on the `inventory` action |
| `online_main.tscn` | the online game (the menu's Play online, `--connect`, `?url=`) | `Main` (an instance of `main.tscn`, unchanged), `RemotePlayers`, `PuppetAnimationThrottle`, `AiReplica`, `NetClient`, `OnlineStatus` |

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
  `MenuLayer` is layer 2, above the HUD). **Seen:** gdstudio #927, 2026-11-10; gdstudio #963, 2026-11-11 (its issue
  put the AI director in `main.tscn`: an issue that places a node names its scene from the table).
- **Approach:** To add a course or blocks to the prototype map, find open ground in `world/prototype/prototype_level.tscn`
  first (the blocks' positions and sizes, clear of the two sections, the spawn points and the routes a tour walks),
  then bake the level again with `tools/map_bake/` (its header has the run) and run `test_map_lighting.gd`. **Watch
  out for:** a block added after the bake is in no lightmap and reads black or flat, and the lighting test fails on
  it; nothing on this page said where free space was, so each course author searched the scene by hand. **Seen:**
  gdstudio #1013 (PR #1024), 2026-11-10 (the vault course, west of the room); gdstudio #885, 2026-11-10
  ([the stale bake](compat-lighting.md)).

## Where the rest is {#moved}

<!-- new section: the page was split at the size limit; moved anchors stay here so links resolve -->

The page is split by subject (#983). Each section below moved to a subpage; the link is its new place.

### The animation libraries {#animation-libraries}

Moved: [The animation libraries](third-person/clips.md#animation-libraries).

### The two mannequins {#mannequins}

Moved: [The two mannequins](third-person/character.md#mannequins).

### Replacing the model {#replacing-the-model}

Moved: [Replacing the model](third-person/character.md#replacing-the-model).

### The character controller {#controller}

Moved: [The character controller](third-person/character.md#controller).

### Sliding {#slide}

<!-- new section: the slide (#1011) lives on the character page; this anchor points there -->

Lives at: [Sliding](third-person/moves.md#slide).

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

### A route for a clip {#walkthrough}

Moved: [A route for a clip](third-person/camera-and-ui.md#walkthrough).

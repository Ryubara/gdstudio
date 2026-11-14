# gds_game

The gameplay code every GDStudio game can use, whatever template it came from: scripts only, no scene, no tuning
resource, no plugin and no autoload (a `class_name` under `addons/` is a global class without one). The kit's own Godot
project is its one source; `gds sync` writes it into every game's `game/addons/gds_game/` and the game's CI fails
(`gds sync --check`) when a copy differs, so a fix made here reaches every game by its next sync. A game never edits
its copy.

## Contents

| Folder | What |
| --- | --- |
| `effects/` | `EffectDef` (what an effect is), `EffectEmitter` (one capped pool of one-shot effects, found by `EffectEmitter.find(self)`), `EffectSlot` (one playing effect) |
| `trigger_zone/` | `TriggerZone`: an area that says when the first body comes in and the last one leaves; with `sensing` off it notices nothing and shows what `show_active` says (a copy whose state is owned elsewhere: an online client's) |
| `impacts/` | `Impacts` (where a shot lands: a mark on the body it hit, an effect and a sound by the kind of surface; `impact(collider, point, normal)`), `ImpactSurface` (one kind of surface), `ImpactMark` (one mark) |
| `spawn_point/` | `SpawnPoint`: where something starts, in a named group; `SpawnPoint.pick()` passes over a point taken in the same frame |
| `camera_shake/` | `CameraShake` (the trauma shake a camera rig applies; `CameraShake.shake(preset, at)` from anywhere) and `ShakePreset` (one kind of shake as a resource) |
| `screen_host/` | `ScreenHost`: opens `UIRouter` screens over the running game, pauses it (unless the top screen's `pauses_game()` says no) and gives it back; its `menu_scene` is set by the game's scene (empty: the project's main scene); needs `gds_ui` |
| `hits/` | `Health` (the harm a character, a target or a prop can take: `apply(hit)`, `damaged`, `changed`, `flinched`, `died` once, regeneration, invulnerable; found on a body by `Health.of(body)`) and `HitRecord` (one hit: damage, zone, bone, point, direction, strength; about 40 bytes on the wire) |
| `interact/` | `Interactable`: an area on the Sensors layer that makes its parent usable; `interact(by)` says `interacted`, so a door, a lever or a chest needs no method of its own |
| `inventory/` | `Inventory` (a bag of numbered slots of stacks: add, move, remove, drop in front of the owner; filled from a collector's pickup signal by its `catalog`), `ItemDef` (one kind of item; `use_effect` says what using it does), `ItemStack` (an item and a count), `Hotbar` (quick-access places naming items of the bag: assign, use; found by `Hotbar.of(node)`), `ItemEffect` (what using an item does) and `HealEffect` (gives health to the user's `Health`); kit `docs/engines/godot/inventory.md` |
| `traversal/` | `Vaultable` (on an obstacle: it may be vaulted over or mantled onto, from which faces, with what overrides), `VaultSettings` (the numbers, as a resource), `VaultClip` (what a vault clip was keyed on: its obstacle, speed and contact times, so the vault is timed by the clip and the hand lands on the top), `VaultProbe` (shape casts that measure the obstacle ahead and plan a crossing) and `VaultPlan` (the crossing: kind, measurements, the warped path) |
| `shader_prelink/` | `ShaderPrelink`: in a browser build, hands the page a list of the GL programs the game links (recorded from a browser run) to link all at once with `KHR_parallel_shader_compile` before the game draws; `start(path)`, `is_done()`, `progress()`, `wait(tree)`; does nothing off the web or with a list of another Godot. With the addon's editor plugin on (`plugin.cfg`), `ShaderPrelinkExport` serves the list (`gds_game/shader_prelink/list`, default `res://assets/shaders/web/shader_programs.json`) beside a web export's `index.html` and writes a script into its head that links it before the engine boots; kit `docs/engines/godot/first-use-hitches.md#prelink-page` |
| `skin_buffers/` | `SkinBuffers`: in a browser build on Direct3D 11 (Chrome, Edge and Firefox on Windows), has the page bind skinned meshes' buffers to draws instead of copying them out of the GPU at every draw; with the addon's editor plugin on, `SkinBuffersExport` writes its script first in a web export's `index.html` head; kit `docs/engines/godot/web-export.md#skin-buffer-hint` |
| `clip_export/` | `ClipReferences` (which clips of a game's large animation libraries its shipped scripts, scenes and resources name, by `gds_game/clip_export/libraries`, `catalogue` and `keep`) and, with the addon's editor plugin on, `ClipExport`, which exports each of those libraries with only the named clips; kit `docs/tools/blender/own-animation.md#replacing` |
| `testing/` | `ExportPins` (pins every export's default in a suite) and `InputSim` (key, pad and mouse events through the `InputMap`, waits in physics ticks); used by suites only |

The scenes and resources that carry these scripts are the template's and the game's own (3D Third Person's
`gameplay/effects/effect_emitter.tscn`, `gameplay/trigger_zone/trigger_zone.tscn`, `gameplay/impacts/impacts.tscn`,
`gameplay/spawn_point/spawn_point.tscn`, `ui/menus/screen_host.tscn`, the `Inventory` node of
`gameplay/player/player.tscn`, and 3D Blank's shake presets in
`core/camera_shake/presets/`): restyle and retune them there.

## What goes here

A part belongs here when any game of any template can use it unchanged (it names no template class, path, input
action or group but its own), it is code whose look and numbers come from exports or the scene it sits on, and its
suite proves it alone in the kit's project (`godot/tests/gds_game/`). Everything else is the template's. The rule and
how a file moves here are in the kit's `docs/studio/sync.md#addons`.

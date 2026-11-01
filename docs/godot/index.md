# Godot

The Godot 4.7 systems GDStudio games rely on, what we know about each, and where the risk is. Each system gets its own
page here once someone learns something about it; the table links them. Every game runs the **Compatibility renderer**
(the web build is WebGL2), so a system is judged by how it behaves there, not in Forward+.

**Status:** *known* (used in a merged pull request, page written), *spike* (needs a sandbox experiment before the
game depends on it), *learn while building* (low risk: the first task that uses it writes the page).

## UI and presentation

| System | Used for | Status |
| --- | --- | --- |
| Control, containers, Theme | every menu and the HUD; tokens generate the Theme | learn while building (gds_ui) |
| Tween, easing | all UI motion | learn while building (gds_ui) |
| canvas_item shaders | screen transitions, film grain, vignette | learn while building (gds_ui) |
| Focus and input map, gamepad | keyboard and gamepad navigation | learn while building |
| Fonts (FontFile, MSDF) | crisp text at any scale | learn while building |

## Rendering (Compatibility renderer)

| System | Used for | Status |
| --- | --- | --- |
| LightmapGI (baking) | most of the lighting: the drive-in at night | **spike**: bake quality and size on the web |
| Environment: fog, glow, tonemap | mood | **spike**: what the Compatibility renderer supports |
| Full-screen post shaders | colour grade, outlines, grain | **spike**: cost on the web |
| OmniLight3D / SpotLight3D | projector beam, lamps, muzzle flash | **spike**: how many dynamic lights the web holds |
| Visibility ranges (LOD), occlusion | far zombies and props | spike with crowds |
| CPUParticles3D / GPUParticles3D | blood, sparks, smoke | learn while building |

## Characters and animation

| System | Used for | Status |
| --- | --- | --- |
| glTF import, BoneMap, SkeletonProfile | the shared Quaternius rig | **spike**: one animation library on every character |
| AnimationTree, state machines, blend spaces | player and zombie movement | **spike** with crowds |
| Skeleton3D cost, MultiMesh | 20 to 40 zombies in a browser | **spike**: frame time on the web |
| BoneAttachment3D | weapons in hands | learn while building |

## Gameplay

| System | Used for | Status |
| --- | --- | --- |
| CharacterBody3D | the first-person player | learn while building |
| Physics (Jolt), raycasts, layers | hits, barricades, pickups | learn while building |
| NavigationServer3D, NavigationAgent3D, avoidance | zombies finding players | **spike** with crowds |
| SpringArm3D, Camera3D | the over-the-shoulder third-person camera: collision, shoulder swap, aim zoom | learn while building (Deadnight #14) |
| AudioServer buses, AudioStreamPlayer3D | mixing, positional sound | learn while building |

## Multiplayer and the web

| System | Used for | Status |
| --- | --- | --- |
| WebSocketMultiplayerPeer, MultiplayerSpawner, MultiplayerSynchronizer | server-authoritative co-op | **spike** (Deadnight #6) |
| Web export (single-threaded) | the browser build and the Discord Activity | spike with multiplayer |
| Headless server export | the game server on Railway | spike with multiplayer |
| ResourceLoader (threaded loading) | loading screens | learn while building |

## Testing and capture

| System | Used for | Status |
| --- | --- | --- |
| Movie Maker (`--write-movie`) | captures for every visual change | known (`docs/capture.md` when it lands) |
| GdUnit4 (scene runner, input simulation) | unit and scene tests | known (Deadnight's smoke test) |
| Godot MCP | driving a live editor | known (`docs/workspace.md#integrations`) |

# Godot

The Godot 4.7 systems GDStudio games rely on, what we know about each, and where the risk is. Each system gets its own
page here once someone learns something about it; the table links them. Every game runs the **Compatibility renderer**
(the web build is WebGL2), so a system is judged by how it behaves there, not in Forward+.

**Status:** *known* (used in a merged pull request, page written), *spike* (needs a sandbox experiment before the
game depends on it), *learn while building* (low risk: the first task that uses it writes the page).

## UI and presentation

| System | Used for | Status |
| --- | --- | --- |
| Control, containers, Theme | every menu and the HUD; tokens generate the Theme | known: [UI controls](ui-controls.md) |
| Tween, easing | all UI motion | learn while building (gds_ui) |
| canvas_item shaders | screen transitions, film grain, vignette | learn while building (gds_ui) |
| Focus and input map, gamepad | keyboard and gamepad navigation | learn while building |
| Fonts (FontFile, MSDF) | crisp text at any scale | learn while building |

## Rendering (Compatibility renderer)

| System | Used for | Status |
| --- | --- | --- |
| LightmapGI (baking) | most of the lighting: the drive-in at night | known, with a warning: bakes only from a Vulkan editor and our bake looked wrong ([Compatibility lighting](compat-lighting.md#lightmapgi)) |
| Environment: fog, glow, tonemap | mood | known ([Compatibility lighting](compat-lighting.md#environment-features)) |
| Full-screen post shaders | colour grade, outlines, grain | known on desktop; web cost still to measure ([Compatibility lighting](compat-lighting.md#full-screen-post-shader)) |
| OmniLight3D / SpotLight3D | projector beam, lamps, muzzle flash | known on desktop: 16+ unshadowed fine, 8 per mesh; web still to measure ([Compatibility lighting](compat-lighting.md#dynamic-lights)) |
| Visibility ranges (LOD), occlusion | far zombies and props | known: [crowds](crowds.md) (no gain when the crowd is close; throttle animation instead) |
| CPUParticles3D / GPUParticles3D | blood, sparks, smoke | learn while building |

## Characters and animation

| System | Used for | Status |
| --- | --- | --- |
| glTF import, BoneMap, SkeletonProfile | the shared Quaternius rig | **spike**: one animation library on every character |
| AnimationTree, state machines, blend spaces | player and zombie movement | known: [crowds](crowds.md) (walk/run blend plus punch one-shot; throttle with manual advance) |
| Skeleton3D cost, MultiMesh | 20 to 40 zombies in a browser | known: [crowds](crowds.md) (40 at most; MultiMesh not tried) |
| BoneAttachment3D | weapons in hands | learn while building |

## Gameplay

| System | Used for | Status |
| --- | --- | --- |
| CharacterBody3D | the first-person player | learn while building |
| Physics (Jolt), raycasts, layers | hits, barricades, pickups | learn while building |
| NavigationServer3D, NavigationAgent3D, avoidance | zombies finding players | known: [crowds](crowds.md) (avoidance is cheap; repath on a timer) |
| SpringArm3D, Camera3D | the over-the-shoulder third-person camera: collision, shoulder swap, aim zoom | learn while building (Deadnight #14) |
| AudioServer buses, AudioStreamPlayer3D | mixing, positional sound | learn while building |

## Multiplayer and the web

| System | Used for | Status |
| --- | --- | --- |
| WebSocketPeer, TCPServer (own protocol); MultiplayerAPI, netfox | server-authoritative co-op over WebSockets | known for our own protocol: [Multiplayer](multiplayer.md); MultiplayerAPI and netfox being compared (Deadnight #38) |
| Web export (single-threaded) | the browser build and the Discord Activity | spike with multiplayer |
| Headless server export | the game server on Railway | spike with multiplayer |
| ResourceLoader (threaded loading) | loading screens | learn while building |

## Testing and capture

| System | Used for | Status |
| --- | --- | --- |
| Movie Maker (`--write-movie`) | captures for every visual change | known (`docs/capture.md` when it lands) |
| GdUnit4 (scene runner, input simulation) | unit and scene tests | known (Deadnight's smoke test) |
| Godot MCP | driving a live editor | known (`docs/workspace.md#integrations`) |

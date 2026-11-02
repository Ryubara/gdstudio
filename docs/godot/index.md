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
| Tween, easing | all UI motion | known: [UI controls](ui-controls.md) (not on disabled or freed nodes; bind transition tweens to the stage) |
| canvas_item shaders | screen transitions, film grain, vignette | known: [UI controls](ui-controls.md) (procedural, no screen read) and [Compatibility lighting](compat-lighting.md#full-screen-post-shader) |
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
| CPUParticles3D / GPUParticles3D, shader quads | blood, sparks, smoke, muzzle flash, camera shake | known: [Shot feedback](shot-feedback.md) (flash quads on the weapon's `Muzzle`, pooled impacts, trauma shake) |
| Spatial shaders, textures on CSG | the greybox lot's ground, walls and paint | known: [Surface materials](surface-materials.md) (world-projected shader, one read, no specular; headless import leaves mipmaps off) |
| Shader and program builds, first use | the first shot, enemy or explosion stutters | known: [First-use hitches](first-use-hitches.md) (no baker or ubershaders in Compatibility; warm up behind a loading screen; short-lived materials rebuild their shaders at every use) |

## Characters and animation

| System | Used for | Status |
| --- | --- | --- |
| glTF import, BoneMap, SkeletonProfile | the shared Quaternius rig | known: [Rig sharing](rig-sharing.md) |
| AnimationTree, state machines, blend spaces | player and zombie movement | known: [crowds](crowds.md) (walk/run blend plus punch one-shot; throttle with manual advance) |
| Skeleton3D cost, MultiMesh | 20 to 40 zombies in a browser | known: [crowds](crowds.md) (40 at most; MultiMesh not tried) |
| BoneAttachment3D | weapons in hands | learn while building |

## Gameplay

| System | Used for | Status |
| --- | --- | --- |
| CharacterBody3D | the first-person player | learn while building |
| Physics (Jolt), raycasts, layers | hits, barricades, pickups | learn while building |
| Physics interpolation (3D) | smooth bodies, weapons and enemies on fast screens with a fixed tick | known: [Physics interpolation](physics-interpolation.md) (on from the first build; hand-blended rigs off; measure on screen at 144 fps) |
| NavigationServer3D, NavigationAgent3D, avoidance | zombies finding players | known: [crowds](crowds.md) (avoidance is cheap; repath on a timer) |
| SpringArm3D, Camera3D | the over-the-shoulder third-person camera: collision, shoulder swap, aim zoom | known: [Third-person camera](camera.md) (damped springs, tick interpolation, own sweeps instead of SpringArm3D) |
| AudioServer buses, AudioStreamPlayer3D | mixing, positional sound | known: [Audio](audio.md) (pooled voices, limits, ducking, sounds made by script) |

## Multiplayer and the web

| System | Used for | Status |
| --- | --- | --- |
| WebSocketPeer, TCPServer (own protocol); MultiplayerAPI, netfox | server-authoritative co-op over WebSockets | known: [Multiplayer](multiplayer.md) (own protocol; MultiplayerAPI and netfox measured against it) |
| Web export (single-threaded) | the browser build and the Discord Activity | spike with multiplayer; testing it in a headless browser: [Web export](web-export.md) (pointer lock on the Linux runner) |
| Headless server export | the game server on Railway | spike with multiplayer |
| ResourceLoader (threaded loading) | loading screens | known: [First-use hitches](first-use-hitches.md) (threaded requests polled each frame; hold the references) |

## Testing and capture

| System | Used for | Status |
| --- | --- | --- |
| Movie Maker (`--write-movie`) | captures for every visual change | known: [Capture](../capture.md) |
| Windowed runs (captures, autopilots, GdUnit) | every one that is not `--headless` | known: [Windowed Godot without taking the focus](no-focus.md) (`gds godot` runs it on a private desktop; a plain start takes the keyboard) |
| GdUnit4 (scene runner, input simulation) | unit and scene tests | known (Deadnight's smoke test) |
| Godot MCP | driving a live editor | known (`docs/workspace.md#integrations`) |

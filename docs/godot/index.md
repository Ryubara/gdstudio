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
| Canvas drawing (`_draw`, labels) | the HUD's cards, bars and text | known: [Canvas draw calls](canvas-draw-calls.md) (polygons and outlined labels are draw calls of their own; one triangle array per card, two calls per label) |
| Tween, easing | all UI motion | known: [UI controls](ui-controls.md) (not on disabled or freed nodes; bind transition tweens to the stage) |
| canvas_item shaders | screen transitions, film grain, vignette | known: [UI controls](ui-controls.md) (procedural, no screen read) and [Compatibility lighting](compat-lighting.md#full-screen-post-shader) |
| One-shot and pooled effects (blasts, gibs, flashes) | every effect made while a night runs | known: [One-shot effects](one-shot-effects.md) (free the part at its tween end; `_process` is on after ready) |
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
| Stencil, outline through walls | a glowing silhouette of marked enemies | known: [Outline through walls](outline-through-walls.md) (stencil works in Compatibility, desktop and web; mask pass plus a ring of shifted copies) |
| Screen measurement of an effect | is the flash, marker or glint readable | known: [Measuring an effect on the screen](measuring-effects-on-screen.md) (draw the frame again without it and compare; `force_draw` in `frame_post_draw`) |
| Shader and program builds, first use | the first shot, enemy or explosion stutters | known: [First-use hitches](first-use-hitches.md) (no baker or ubershaders in Compatibility; warm up behind a loading screen; short-lived materials rebuild their shaders at every use) |

## Characters and animation

| System | Used for | Status |
| --- | --- | --- |
| glTF import, BoneMap, SkeletonProfile | the shared Quaternius rig | known: [Rig sharing](rig-sharing.md) |
| AnimationTree, state machines, blend spaces | player and zombie movement | known: [AnimationTree](animation-tree.md) (reading a clip's place, locking one branch to another, stepping by hand) and [crowds](crowds.md) (walk/run blend plus punch one-shot; throttle with manual advance) |
| Skeleton3D cost, MultiMesh | 20 to 40 zombies in a browser | known: [crowds](crowds.md) (40 at most; MultiMesh not tried) |
| BoneAttachment3D | weapons in hands | learn while building |

## Gameplay

| System | Used for | Status |
| --- | --- | --- |
| CharacterBody3D | the first-person player | learn while building |
| Physics (Jolt), raycasts, layers | hits, barricades, pickups | learn while building |
| Physics interpolation (3D) | smooth bodies, weapons and enemies on fast screens with a fixed tick | known: [Physics interpolation](physics-interpolation.md) (on from the first build; hand-blended rigs off; measure on screen at 144 fps) |
| NavigationServer3D, NavigationAgent3D, avoidance | zombies finding players | known: [crowds](crowds.md) (avoidance is cheap; repath on a timer) |
| A cutscene one player sees | an arrival, an intro or a kill cam on one screen while the server's night goes on | known: [A cutscene one client plays](client-cutscene.md) (the server keeps the player safe by the client's word, with a cap; the show is a pure function of time; the camera is placed by rays; the sounds load on demand) |
| SpringArm3D, Camera3D | the over-the-shoulder third-person camera: collision, shoulder swap, aim zoom | known: [Third-person camera](camera.md) (damped springs, tick interpolation, own sweeps instead of SpringArm3D) |
| Mouse look, stick look | the view turns one to one with the hand at any frame rate | known: [Mouse look at any frame rate](mouse-look.md) (raw delta once per event, no delta time; set the parent before the child; test the Camera3D's transform) |
| AudioServer buses, AudioStreamPlayer3D | mixing, positional sound | known: [Audio](audio.md) (pooled voices, limits, ducking, sounds made by script) |
| A map, before it ships | judging a layout as a level designer: loops, chokepoints, spawns, pacing, lighting, out-of-bounds and door skips proven by movement | known: [Map review](map-review.md) (a checklist built from published level-design writing, first run on Deadnight's two maps) |

## Multiplayer and the web

| System | Used for | Status |
| --- | --- | --- |
| WebSocketPeer, TCPServer (own protocol); MultiplayerAPI, netfox | server-authoritative co-op over WebSockets | known: [Multiplayer](multiplayer.md) (own protocol; MultiplayerAPI and netfox measured against it) |
| Web export (single-threaded) | the browser build and the Discord Activity | spike with multiplayer; testing it in a headless browser: [Web export](web-export.md) (pointer lock on the Linux runner) |
| Web page heap (WebGL id tables) | a page whose heap grows while the engine's counters are flat | known: [The web page's heap](web-heap.md) (every `glGen*` costs a slot in each id table for good; a canvas item redrawn every frame makes about 200 objects a frame) |
| Headless server export | the game server on Railway | spike with multiplayer |
| ResourceLoader (threaded loading) | loading screens | known: [First-use hitches](first-use-hitches.md) (threaded requests polled each frame; hold the references) |

## Testing and capture

| System | Used for | Status |
| --- | --- | --- |
| Movie Maker (`--write-movie`) | captures for every visual change | known: [Capture](../capture.md) |
| Windowed runs (captures, autopilots, GdUnit) | every one that is not `--headless` | known: [Windowed Godot without taking the focus](no-focus.md) (`gds godot` runs it on a private desktop; a plain start takes the keyboard) |
| Local browser probes of the web build (Playwright) | every one, under pointer lock | known: [`gds quiet`](no-focus.md#browser-probes-and-any-other-program-gds-quiet) (headless Chrome clips the real cursor to its hidden window) |
| The editor's own inspector, photographed | pull requests that move numbers into resources | known: [Screenshots of the editor's inspector](editor-screenshots.md) (a throwaway plugin on `gds godot -- --editor`) |
| Performance budgets (worst-case run, sampler, CI budget, leak soak, timing on a shared machine) | every game from its first playable night | known: [Performance budgets](performance-budgets.md) (count what does not depend on the load, time as a ratio of a calibration loop, headless at a fixed step, a leak read at the same crowd) |
| GdUnit4 (scene runner, input simulation) | unit and scene tests | known (Deadnight's smoke test) |
| Performance review (cost per frame, per tick, per spawn) | every pull request that adds per-frame work, a spawn, a light, a shader or a message | known: [Performance review](performance-review.md) (state the cost in a `## Cost` section; every run-time spawn frees itself or is pooled; measure a tick of the real night with the bots at the ceiling, counts first) |
| Test speed (hand ticks, settles, CI job time) | every suite that steps the game by hand | known: [Test speed](test-speed.md) |
| The headless (dummy) renderer | every GdUnit run in CI | known: [meshes are not safe to make from two threads](headless-renderer.md) |
| Navigation in tests (a mesh of your own, errors caught, what the baked mesh closes) | every suite that asks for a path | known: [Navigation in tests](navigation-in-tests.md) |
| One mesh, two kinds of walkers (the dead's gaps that boards shut to a person) | every bot or stand-in that asks the map for a path | known: [Navigation layers](navigation-layers.md) (a region of the polygons across the barricades, on a layer only the dead ask for) |
| A tour that exits with 139 after saving its frames | every capture that sets a hook on the game | known: [Exit code 139](exit-code-139.md) (a lambda left in a static variable is freed after its script; clear the hook before `quit()`) |
| A probe that builds the game (`-s` or a scene, autoloads, fresh worktree) | every throwaway run that prints what it saw | known: [Probes and tools in headless Godot](headless-probes.md) (`-s` has no autoloads: write the probe as a scene) |
| A script that will not parse (`--check-only --script`) | every "could not parse global class" error | known: [lesson](../lessons/2026-11-03-a-parse-error-in-one-class-showed-up-as-errors-in-its-users.md) (the real message shows only when the script is loaded on its own) |
| Godot MCP | driving a live editor | known (`docs/workspace.md#integrations`) |

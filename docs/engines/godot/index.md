# Godot

The Godot 4.7 systems GDStudio games rely on, what we know about each, and where the risk is. Each system gets its own
page here once someone learns something about it; the table links them. Every game runs the **Compatibility renderer**
(the web build is WebGL2), so a system is judged by how it behaves there, not in Forward+.

**Belongs here:** how Godot does something (GDScript, scenes, physics, rendering, animation, UI, export, networking,
testing) and what it costs. **Not here:** the principle behind it, which holds in any engine
([Game development](../../gamedev/index.md)), and one game's numbers (that game's docs).

**Status:** *known* (used in a merged pull request, page written), *spike* (needs a sandbox experiment before the
game depends on it), *learn while building* (low risk: the first task that uses it writes the page).

## Starting a game

| System | Used for | Status |
| --- | --- | --- |
| `gds new game`, the templates | a new game repository that builds, tests and exports from its first commit | known: [A new game from a template](new-game.md) (`3d-blank` first; the local steps, the GitHub repository with its settings and proof, MIT by default; adding a template) |
| Folder, naming and dependency rules | every game's project layout, enforced by `gds check layout` | known: [Project conventions](project-conventions.md) (by feature, snake_case, dependencies one way, tools out of the export) |

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
| A grid with no texture file, a daylight rig | the 3D Blank template's prototype level | known: [Prototype surfaces and daylight](prototype-surfaces.md) (world-space triplanar grid in the fragment shader; colour ambient, one shadowed sun, filmic; measured in Compatibility and in Chromium) |
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
| Browser probes (Playwright, CDP) and the gates that read them | every web build tested in a headless browser | known: [Browser probes](web-probes.md) (run through `gds quiet`; a probe that can fail; a time gate set from many runs, not one) |
| Web page heap (WebGL id tables) | a page whose heap grows while the engine's counters are flat | known: [The web page's heap](web-heap.md) (every `glGen*` costs a slot in each id table for good; a canvas item redrawn every frame makes about 200 objects a frame) |
| Headless server export | the game server on Railway | spike with multiplayer; deploying it: [Railway](../../studio/railway.md); the rules that hold in any engine: [Netcode](../../gamedev/netcode.md) |
| Callable, `await` | a send that waits on a request and is handed over as a Callable | known: [Callables and coroutines](callables-and-coroutines.md) (a Callable does not keep a RefCounted object alive; what `await` does with a plain value) |
| `static var` initialisers | a cache or flag shared by scripts that refer to each other | known: [Static variables and the order scripts load in](static-variables.md) (an initialiser runs when its script loads; a script loaded inside another still holds the type's defaults, so "not read" is 0, not -1) |
| `Performance.OBJECT_RESOURCE_COUNT`, `ResourceLoader.has_cached` | finding what a resource count (a leak budget's peak) is made of | known: [Naming what the resource count is made of](resource-count.md) (`OS.dump_resources_to_file` is not in GDScript; walk the files and ask the cache) |
| ResourceLoader (threaded loading) | loading screens | known: [First-use hitches](first-use-hitches.md) (threaded requests polled each frame; hold the references) |

## Testing and capture

| System | Used for | Status |
| --- | --- | --- |
| Movie Maker (`--write-movie`) | captures for every visual change | known: [Capture](../../studio/capture.md) |
| Windowed runs (captures, autopilots, GdUnit) | every one that is not `--headless` | known: [Windowed Godot without taking the focus](no-focus.md) (`gds godot` runs it on a private desktop; a plain start takes the keyboard) |
| GdUnit in a window on a CI runner (`xvfb-run`, Mesa software GL) | every game that wants its pixel and window-only suites run on a schedule | known: [Windowed GdUnit on a Linux runner](windowed-gdunit-on-linux.md) |
| A windowed GdUnit session of several suites | every suite that waits for a drawn frame (a night's warm-up) | known: [A minimized window draws nothing](minimized-window.md) (GdUnit minimizes after every suite; restore the window in `before()`) |
| Local browser probes of the web build (Playwright) | every one, under pointer lock | known: [`gds quiet`](no-focus.md#browser-probes-and-any-other-program-gds-quiet) (headless Chrome clips the real cursor to its hidden window) |
| The editor's own inspector, photographed | pull requests that move numbers into resources | known: [Screenshots of the editor's inspector](editor-screenshots.md) (a throwaway plugin on `gds godot -- --editor`) |
| Performance budgets (worst-case run, sampler, CI budget, leak soak, timing on a shared machine) | every game from its first playable night | known: [Performance budgets](performance-budgets.md) (count what does not depend on the load, time as a ratio of a calibration loop, headless at a fixed step, a leak read at the same crowd) |
| GdUnit4 (scene runner, input simulation) | unit and scene tests | known (Deadnight's smoke test) |
| Performance review (cost per frame, per tick, per spawn) | every pull request that adds per-frame work, a spawn, a light, a shader or a message | known: [Performance review](performance-review.md) (state the cost in a `## Cost` section; every run-time spawn frees itself or is pooled; measure a tick of the real night with the bots at the ceiling, counts first) |
| Test speed (hand ticks, settles, CI job time) | every suite that steps the game by hand | known: [Test speed](test-speed.md) |
| The headless (dummy) renderer | every GdUnit run in CI | known: [meshes are not safe to make from two threads](headless-renderer.md) |
| Worker threads (`WorkerThreadPool`: a group of cells, a bake, a load) | every job that runs a simulation off the main thread | known: [Worker threads](worker-threads.md) (the first use of shared state from several workers crashes silently: warm it on the calling thread, prove it in a cold child process) |
| Navigation in tests (a mesh of your own, errors caught, what the baked mesh closes) | every suite that asks for a path | known: [Navigation in tests](navigation-in-tests.md) |
| One mesh, two kinds of walkers (the dead's gaps that boards shut to a person) | every bot or stand-in that asks the map for a path | known: [Navigation layers](navigation-layers.md) (a region of the polygons across the barricades, on a layer only the dead ask for) |
| Fixed-step repeatability (two runs of one seed differ: where to look, the lot's age, waits on the navigation server) | every night, soak and replay that must repeat | known: [Fixed-step repeatability](fixed-step-repeatability.md) (trace hashes by part, find the first tick; wait for an age, not for an answer) |
| A tour that exits with 139 after saving its frames | every capture that sets a hook on the game | known: [Exit code 139](exit-code-139.md) (a lambda left in a static variable is freed after its script; clear the hook before `quit()`) |
| A probe that builds the game (`-s` or a scene, autoloads, fresh worktree) | every throwaway run that prints what it saw | known: [Probes and tools in headless Godot](headless-probes.md) (`-s` has no autoloads: write the probe as a scene) |
| The real `main.tscn` against a real sign-in, without the person's saves | every capture of what the game shows after a read from the backend | known: [A throwaway user folder](throwaway-user-folder.md) (`APPDATA` points at a folder of its own; seed it by a real sign-in; a harness run skips the start-up sign-in, so the capture makes that one call) |
| A script that will not parse (`--check-only --script`) | every "could not parse global class" error | known: [lesson](../../lessons/2026-11-03-a-parse-error-in-one-class-showed-up-as-errors-in-its-users.md) (the real message shows only when the script is loaded on its own) |
| Godot MCP | driving a live editor | known (`docs/studio/workspace.md#integrations`) |

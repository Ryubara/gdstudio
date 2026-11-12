# First-use hitches: shader compiles and loads in the Compatibility renderer

The first time something is drawn or sounded in a Godot game, the engine may stop the frame to build or read what it
needs. In a browser build (Compatibility renderer, WebGL2) this is the commonest cause of "it stutters the first time":
the first shot, the first enemy on screen, the first explosion. Measured in Deadnight (Godot 4.7.2, Chrome on Windows,
RTX 5080): about 290 GL programs were linked during the first 20 s of a night, and the worst frame was 390 to 540 ms
(six runs). After the fix below there were none in three runs, and the worst frame was 17 to 25 ms. The game's own
page, with the numbers and the method, is `docs/research/first-use-hitches.md` in Deadnight.

## What the engine does {#what-the-engine-does}

- **Programs are built on first draw.** The Compatibility renderer builds a GL program the first time a mesh is drawn
  with a material under a set of render conditions: the shader, the pass (colour, depth), instancing, and the
  *specialisation* the scene state asks for (whether a directional, omni or spot light reaches the mesh, fog, the
  radiance map...). Each combination is its own program, built and linked on the main thread; the browser then blocks
  at the first draw that uses it. One material seen with and without an omni light near it is two builds.
- **No precompilation exists for it.** The Godot docs say the pipeline-compilation page, ubershaders and pipeline
  precompilation apply to Forward+ and Mobile only: WebGL2 and GLES3 cannot do them. The **shader baker** (4.5) is
  Forward+ and Mobile only and is **not supported on the web**. For Compatibility the docs' own advice is the old one:
  show every material, shader and particle for at least one frame while the level loads
  ([Pipeline compilations](https://docs.godotengine.org/en/latest/tutorials/performance/pipeline_compilations.html)).
  The engine has no batch link either: it links one program and reads `LINK_STATUS` at once, so a cold browser waits
  for every program in turn. Linking a recorded list of them all at once from the page is what shortens that wait
  ([Linking every program at once](#prelink)).
- **A shader goes with the last material that uses it.** `BaseMaterial3D` shares one shader among all materials with
  the same settings and frees it when the last of them is freed. An effect that makes a new `StandardMaterial3D` for
  every flash and frees it a moment later frees the shader with it, and **every single use builds its programs again**.
  In Deadnight this was nearly all of the 290 builds (about 6 per shot). This is a hitch at *every* use, not only the
  first.
- **Resources load on first `load()`.** A resource nothing references is freed, and `load()` reads it again. Hold a
  reference to what the next minute needs.
  The same cost shows in code that runs every tick, not only at the first use: a `load()` of a `.tres` that nothing holds
  took 0.8 ms a call (2.7 microseconds held) in a headless server, so a value read from a catalogue resource inside a
  per-tick function is read once and kept.
- **Chrome keeps a program cache** in the browser profile, so a second visit on the same profile hides the problem.
  Measure with a fresh profile every run (Playwright's `launch` makes one).

## How to find it {#how-to-find-it}

Wrap WebGL in the page before the game loads and count what is linked while playing. A frame that links programs is a
frame that stutters, and "no program linked after the loading screen" is a clean, noise-free test:

```js
const link = WebGL2RenderingContext.prototype.linkProgram;
const param = WebGL2RenderingContext.prototype.getProgramParameter;
WebGL2RenderingContext.prototype.linkProgram = function (p) { p.__t = performance.now(); return link.call(this, p); };
WebGL2RenderingContext.prototype.getProgramParameter = function (p, n) {
  const r = param.call(this, p, n);
  if (n === this.LINK_STATUS && p.__t) { window.__links.push([p.__t, performance.now() - p.__t]); p.__t = 0; }
  return r;
};
```

Godot reads `LINK_STATUS` straight after linking, which is where the time goes. Recording `shaderSource` as well gives
the `#define` list of each program (`DISABLE_LIGHT_OMNI`, `USE_INSTANCING`, `MODE_RENDER_DEPTH`...), which says *why* a
second program for the same material was needed. Frame times alone (requestAnimationFrame deltas) show the hitches but
not their cause; headless Chrome with a real GPU (`channel="chrome"`) is enough, a software renderer is not.

- **Approach:** On a software renderer (SwiftShader, Playwright's default page) time every WebGL call per frame, not
  only `linkProgram`: there the link costs about 1 ms a program, the compile waits in `getShaderParameter`
  (`COMPILE_STATUS`, 100 to 480 ms a frame) and the drawing itself in the first call that waits on the GPU process
  (Godot's `getParameter(0x0C11)`, 100 to 1400 ms a frame), so a frame with no program linked can still be the
  longest. **Watch out for:** the browser gate's page hitched 0.3 to 0.9 s after joining with 0 to 16 programs linked
  in those frames; timing every `WebGL2RenderingContext` method, with the engine's markers logged to the console,
  showed the level's warm-up (`EffectEmitter`'s tour of the probes, 6 s past the seat), not the puppets. **Seen:**
  gdstudio #1106, 2026-11-11 (fix: the probe joins after `warmed`; `FRAME_WATCH` in `net_play_smoke.py`).
- **Approach:** Name each program linked after the loading screen by its fragment shader's `#define`s before warming
  anything up, and look for a second camera whose world draws without what the game camera has (fog, the sun): its
  view builds variants of its own. **Watch out for:** a browser's join linked 2 programs in the frame that first drew
  an AI puppet, read as the warm-up missing the dressed character; the defines (`DISABLE_FOG`,
  `DISABLE_LIGHT_DIRECTIONAL`) were the minimap's live camera drawing the body, and the bodies had just left its layer:
  a warm-up draw would have built nothing that counted. **Seen:** gdstudio #1218, 2026-11-11 (`late_programs` in
  `net_play_smoke.py`, which fails on any link after the seat).
- **Approach:** Warm up in every view that draws the level's world, each as it draws (its camera's environment and
  layers, its viewport's shadow atlas), where a first use happens there: where the player stands, in every probe and
  outside them, with a look round before each draw. **Watch out for:** the live minimap drew the first flash, sparks
  and mark in its own flat environment (no `USE_RADIANCE_MAP`): 6 to 7 programs, a 117 to 151 ms frame. Touring its
  view only at the probes left 2 to 3 (the open place was not one), and an unlit draw straight after a lit one missed
  a program in two runs of three. **Seen:** gdstudio #1297, 2026-11-11 (fix: `EffectEmitter.other_views()`; 0 programs
  in four runs after).

## The first draw of a shader builds four programs, two of them huge {#first-shader-draw}

Reading the engine (`ShaderGLES3::_version_bind_shader` and `_initialize_version`, 4.7) and measuring in Chrome
(ANGLE on Direct3D 11, RTX 5080, a small spike with one cube per material and a directional, an omni and a spot light):
the first time any shader (a `ShaderMaterial`'s, or the one the engine writes for a set of `StandardMaterial3D`
settings) is bound, the renderer builds **all four of its variants (colour, colour instanced, depth, depth instanced) at
the default specialisation**, in which nothing is disabled: directional, omni, spot and **area** lights, lightmaps,
fog. Then it builds the specialisation the draw really asked for. Only the last is ever drawn with, in most games.

| First bind of a shader | The two colour programs (default) | The depth programs | The program drawn with |
| --- | --- | --- | --- |
| `StandardMaterial3D`, Burley and GGX (the default) | 915 and 889 ms | 10 and 13 ms | 171 ms |
| Lambert, specular disabled (`ShaderMaterial` or standard) | 540 to 640 and 490 to 570 ms | 10 and 14 ms | 90 to 140 ms |
| per-vertex shading | 120 to 150 ms each | 15 and 18 ms | 111 to 128 ms |
| unshaded | 30 to 45 ms each | 10 ms each | 30 ms |

- So one lit shader's first draw is a frame of **1.1 to 2 s** whatever the mesh is, and no frame can be cut shorter than
  that: a browser cannot build part of a program. A lot with nine lit shaders drew them all in its first frame, 9 to
  12 s with nothing moving.
- `shadows_disabled`, `ambient_light_disabled`, `fog_disabled`, `force_lambert_over_burley`, the shadow filter quality
  and a lower `max_lights_per_object` / `max_renderable_lights` (4 and 8) change it by 0 to 20 %. Only specular off and
  Lambert (about 40 % less) or per-vertex shading (about 85 % less, a different look) change it much.
- What shortens the loading screen is **fewer lit shaders**, not fewer meshes: materials that differ in one setting
  (specular on or off, `cull_mode` disabled on one gun, an emission flag) are one more pair of huge programs each.

## Drawing the level in pieces {#drawing-the-level-in-pieces}

Hold what the level draws out of the picture and bring it back **one new kind of material at a time**, a frame each,
so the loading bar moves between the long frames and no frame meets two shaders:

- Turn the renderer's instance off, not the node (`RenderingServer.instance_set_visible(node.get_instance(), false)`):
  the node's own `visible` stays what the game set, and putting it back with `node.is_visible_in_tree()` respects
  anything the game hid meanwhile. Hide before the camera that draws it is made current.
- Order the pieces by the material each node draws with (the shader's file, or the settings of a standard material
  that change its shader): the most used material first; a node comes back at the step where the last of its materials
  is met first, so a step meets one new material at most.
- A `SubViewport` with a world of its own (a HUD portrait) draws the same shaders in its own first frame, whenever it
  likes: stop it with `RenderingServer.viewport_set_active(viewport.get_viewport_rid(), false)` and start it after the
  pieces are in, when its shaders are built.
- Draw each kind of effect in its own frame too (one weapon's flash, then the next), not all in one.
- Test the cut in the browser by counting programs linked in each page frame (a frame that links more than a dozen is
  too coarse). The count is the same on a software renderer and any GPU, so unlike a frame time it can fail CI.

## The warm-up {#the-warm-up}

Behind a loading screen, before the game starts:

1. **Load** every scene and resource (`ResourceLoader.load_threaded_request`, polled each frame so the bar moves;
   a single-threaded web export still loads them one at a time) and **keep the references**. Find them in the
   catalogues and from `ResourceLoader.get_dependencies(definition_path)` so a new weapon model needs no list edit.
2. **Draw everything once, in the real world.** Use the game's own world, lights, environment and fog: a camera of
   your own made current for the warm-up sees the same `WorldEnvironment` and the same lights, so the programs match.
   Draw the whole level from above (nothing is frustum-culled out), once with the lights on and once with them off
   (the program of a mesh depends on the lights that reach it, and the power can fail). On a stage far above the level
   draw each enemy near and far (visibility ranges), each effect through the *game's own code path* (replay a sample
   of every event the view handles), under **each light condition** the game has: no local light, an omni, a spot,
   both. Hold two frames for each shot and wait for `RenderingServer.frame_post_draw`.
3. **Keep the materials** the effects made (read them from the effect nodes before they free themselves) so the shaders
   stay alive for the whole session.
4. **Mute** the buses while sample events play; free the stage; make the player's camera current again.

Things that did not matter or cannot be done: a second `SubViewport` of your own is not needed (the main viewport
with a second camera is the same world); the headless renderer compiles nothing, so skip the warm-up there; a
`ShaderMaterial` shared through a scene file stays alive with the scene.

- **Approach:** Warm up every enemy, weapon, effect and shader behind a loading screen from the first playable night,
  and measure in a browser with a fresh profile, counting the GL programs linked during play. **Watch out for:** frame
  times were measured on desktop and with a warm browser profile, and nothing drew each effect once before play, so the
  deployed build hitched the first time a shot or a zombie appeared. **Seen:** Deadnight, 2026-11-01 (fix: the warm-up
  above, gated by a fresh-profile browser run that expects no program linked after the loading screen ([Testing
  it](#testing-it))).

- **Approach:** Give each new effect shader a warm-up chunk of its own (the splash alone before the events, the events
  with the numbers, the mark, the blast burst), held still with `set_process(false)`; resume paused viewports one per
  frame; run the web smoke through `gds quiet` before the push and read its three busiest loading frames
  (`loading.busiest_frames`). **Watch out for:** a shader's first draw builds four programs and then the one it is drawn
  with, so two new shaders and a label in one frame linked 15 programs, and a HUD viewport resumed with the weapon
  silhouettes' in one call linked 16; the unit tests stay green, only the browser run counts programs per frame (at
  most 12). **Seen:** Deadnight #648, 2026-11-02; Deadnight #713, 2026-11-03 (fix: chunks and resumes of their own, 15
  to 12 and 16 to 12).

## A warm-up on the CPU pays for every pixel {#a-warm-up-on-the-cpu-pays-for-every-pixel}

A renderer that draws on the CPU (SwiftShader in headless Chromium, a machine with no GPU) costs a warm-up frame in
proportion to the pixels, whatever the programs. A level drawn at 1280 x 720 for 100 frames took 30.5 s; at 640 x 360
14.3 s. A program does not depend on the size of the picture, so draw the warm-up into a small `SubViewport`
(`own_world_3d = false`, 160 x 90) that shares the level's world, turn the window's own 3D off meanwhile
(`Viewport.disable_3d`), and draw the real frame once at the end so anything only the window's drawing needs (the
tone-map and sky passes) is built behind the loading screen too. Measure that no program is linked while playing
(the page hook of `first_use.py`): in Deadnight the same 207 programs were linked as with the window's size.

Other things the load profile found (Deadnight #509, Compatibility, web):

- The engine builds the **default specialisation** of a lit shader at its first draw (colour and instanced colour
  with every light type, lightmaps and probes on): 0.6 to 1.0 s each with ANGLE on Direct3D 11, and nothing draws with
  it. So every lit `StandardMaterial3D` that differs in one setting costs 1.2 to 2 s. `specular_mode = DISABLED` is
  such a setting; `metallic_specular = 0` has the same look in an existing shader. Count the lit settings in a test.
- `force_lambert_over_burley` did not shorten the load.
- A loop in GDScript over every sample of every sound (decoding to 16-bit samples) is seconds in a browser: do it
  while a menu is up, a slice of each frame, not behind the loading bar.
- Replaying effects once per light condition is worth nothing when their materials are unlit: check the programs each
  condition links (0 here).

- **Approach:** Put a new family of sounds (a weapon, a voice, a map's set) in a bank with `deferred = true`: the
  loading bar only queues its files and the audio service reads and decodes them a few ms a frame while the night
  runs, a sound played first going to the front; a test caps the seconds decoded behind the bar. **Watch out for:**
  the bar read every sound file and decoded each short one to samples in a GDScript loop, 166 s of sound and then 297
  s, played or not, so the web job failed four times in a day (75 to 89 s against 72) on pull requests that loaded
  nothing new. **Seen:** Deadnight #828, 2026-11-03 (fix: weapons' and voices' banks deferred; a new exported property
  on a resource with a pinned tuning table needs that table's test run too).

## Particle systems: two programs of their own, and a sample that expires {#particle-programs}

A `GPUParticles3D` draws with two programs besides the level's: the one that **moves the particles** (built from its
`ParticleProcessMaterial`: 845 ms at its first run with ANGLE on Direct3D 11, and a second variant of it about 0.85 s
later) and the one that **draws each particle** (the draw pass's material: an unshaded standard material costs its four
variants at the default specialisation, plus the ones it is drawn with, 6 programs of 30 ms). Measured in Deadnight #502,
the first flare shot of a night in Chrome: 10 programs and a 1.8 s frame, and an 8-program hitch again at a flare thrown
after the first one's fire had burned out. Two things in a warm-up leave them out:

- **A sample effect that frees itself by the clock expires before it is drawn.** Effects count their life in frame
  deltas; a warm-up frame that builds a program takes seconds, so a sample made to live 0.2 s is freed on the first
  frame after it starts, before any frame draws it. Keep the sample alive for the frames you hold, and free it by hand.
- **Pins that skip particle systems.** Keeping every `MeshInstance3D`'s mesh and materials alive does not keep a
  `GPUParticles3D`'s `process_material` or its draw passes' meshes and materials: they go with the effect, and the
  shaders and programs go with them. Pin them (`get_draw_pass_mesh(i)` for `i < draw_passes`; reading `draw_pass_2` of a
  system with one pass is an engine error). A draw ledger must list particle systems by process material and draw
  material too, or a test cannot see this (a `GPUParticles3D` is not a `MeshInstance3D`).
- A system moves its particles in the frame after it starts and draws them in the one after, so hold the sample for
  three frames.

Test the fix by firing the effect in the browser three times (the first, one soon after, one after its fire is out) and
counting the programs linked in the seconds after each trigger (Deadnight `tools/web_smoke/flare_first.py`): 10, 0 and 8
programs before, 0, 0 and 0 after, and the worst frame after the first shot from 1.8 s to 7 to 36 ms.

## Reflection probes change the program, and draw over many frames {#reflection-probes}

<!-- new section: the warm-up sections say to draw under each light condition; none said a reflection probe is one,
     nor that a probe comes in frames after the level starts, which made a warm-up build the wrong programs -->

Read in the engine (`RendererSceneCull::render_probes` and `_render_reflection_probe_step`, `RasterizerSceneGLES3`
4.5 to 4.7) and measured in 3D Third Person (kit #946, Chrome on the GPU):

- **A probe is a specialisation.** A surface a `ReflectionProbe` reaches is drawn without `DISABLE_REFLECTION_PROBE`
  (with `SECOND_REFLECTION_PROBE` under two), so the same material in and out of a probe is two programs, as with an
  omni light. An unshaded material (a flash, a mark, dust) is specialised the same way.
- **A probe that updates once is drawn over about 15 frames**, one step a frame: six faces, then up to eight blur
  steps, and only one such probe at a time. Its surfaces change program at its first face (the probe has its atlas
  then), so whatever a warm-up draws in the first frames of a level is built without the probe and built again later.
- **Only a probe the camera sees is drawn** (it is queued from the camera's cull), so a probe in another room starts
  when the player first looks at it, and its surfaces build their programs then.
- So a warm-up waits for the probes in view before it draws: count the probes whose box meets the camera's frustum
  (`Camera3D.get_frustum()`, a box wholly over one plane is out) and wait 15 frames for each that updates once, one
  for each that updates always (3D Third Person's `EffectEmitter.probe_frames()`). Those frames also build the level's
  own probe programs behind the loading, which before were an 11-program, 1.2 s frame just after it.
- **What moves under a probe is drawn with its program too, and so is what has none.** A probe in view at the start is
  drawn then, and the walls inside it with it, but a character, an effect or a mark only builds its program for that
  probe (or for two, `SECOND_REFLECTION_PROBE`, in a room inside the outdoor probe's box) when it is first drawn there.
  In 3D Third Person walking into the room built the character's two lit programs (220 to 290 ms, a 120 to 157 ms
  frame) and the first shot there three or four more (sparks, dust, the mark: 64 to 87 ms). A part of the level that no
  probe reaches draws its effects without one, another program again. So a warm-up visits every probe and draws there
  every material a moving thing can bring (the effects, the marks, the characters' materials), and draws them once
  outside every probe ([the emitter's tour](effect-emitter.md#warm-up)): 0 programs in play after, for 13 more while
  the level starts.

- **Approach:** Start a warm-up only once the reflection probes in view have drawn, and draw every material a first
  use shows (effects, marks, decals), each under the same probes and lights as its real use; prove it with a fresh
  browser profile, counting programs linked after the level is up. **Watch out for:** a warm-up two frames into the
  level ran before the outdoor probe's first face, so the flash, its light and the dust were all built without the
  probe and built again at the first shot (2, 4 and 6 programs, up to 235 ms), and the bullet mark's shader was never
  drawn at all. **Seen:** gdstudio #888 and #946, 2026-11-10 (fix: `EffectEmitter` waits `probe_frames()` and draws
  `warm_material()` quads; 0 programs and 6.6 to 7 ms first frames after).
- **Approach:** Warm up inside every probe of the level, not only those in view, and draw there what moves (effects,
  marks, the characters' materials) as well as the level; then once outside every probe; measure with a run that walks
  into each kind of place and fires. **Watch out for:** the probes in view at the start were drawn and their walls
  built, so the outdoor check passed, while the character and the effects had never been drawn under the room's two
  probes (5 to 6 programs, up to 157 ms, on entering and the first shot there); and a tour of the probes alone still
  left an effect drawn without a probe now and then (1 program, about 35 ms) until it also drew outside them all.
  **Seen:** gdstudio #981, 2026-11-10 (fix: `EffectEmitter` visits every probe from a `SubViewport` of its own and
  draws `warm_up_groups` materials there; 0 programs in four runs after).

## Linking every program at once {#prelink}

<!-- new section: the page said no precompilation exists for Compatibility and only drew things in pieces behind a
     loading screen; nothing said the browser can link many programs in parallel, nor how to hand it the engine's -->

The engine links each program at its first draw and reads its `LINK_STATUS` straight away, so the GPU process links
them one after another while the page waits: 3D Third Person's 160 programs took 20 s of links on a fresh browser
profile (ANGLE on Direct3D 11, an RTX 5080), the level up 24 to 25 s after the page opened, in frames of up to 13.8 s
(kit #1164). The browser can do better on its own terms:

- **`KHR_parallel_shader_compile` links in parallel.** With every program's `linkProgram` sent first and the results
  read later (`COMPLETION_STATUS_KHR`, polled from a timer), the GPU process linked the same 165 programs in 2.6 s
  instead of 21 s, and the page's thread never waited. Chrome offers the extension on ANGLE's Direct3D 11, not on
  SwiftShader (which links in about 1 ms a program anyway), so there the list is skipped.
- **The GPU process keeps what it linked.** A later link of the same sources, attribute bindings and feedback varyings
  finds the program (165 links in 0.7 s), across contexts of one page, and the browser's disk cache keeps them for the
  next visit (a returning player). Losing the context or deleting the programs does not drop them.
- **Only in a context with the same extensions on.** A second context with only the extension it needed found
  nothing (the game's links took as long as before): Emscripten turns on every WebGL extension it knows in the engine's
  context, and extensions such as `OES_sample_variables` change how a shader is translated. Linking in the engine's
  own context (`canvas.getContext('webgl2')` gives it back) needs no list of extensions, and binding nothing leaves
  its state alone.
- **The sources are the engine's.** A page that wraps `shaderSource`, `attachShader`, `bindAttribLocation`,
  `transformFeedbackVaryings` and `linkProgram` records them; SwiftShader records the same programs as a GPU (150 of
  154 alike in two runs, the rest the warm-up's timing), so a list can be recorded on any machine. 154 programs are
  15 MB of source; written once each with runs of earlier lines they are 220 KB of JSON (50 KB compressed).

`ShaderPrelink` (`addons/gds_game/shader_prelink/`) does it: the template's menu scene reads the list
(`MenuScene.shader_programs`, `assets/shaders/web/shader_programs.json`), the page decodes it and links it in the
engine's context, and the game waits for it before it draws the level (a straight route) or behind the loading bar
(the menu's Play). The list is recorded by `tools/web_smoke/shader_programs.py --write` from the web build, which also
measures a cold page with and without it. A list of another Godot is skipped whole (the template's suite fails on
it); a program it lacks is linked at its first draw as before. Measured with that script (Chrome, a fresh profile
each run, `?play`):

| Page | Links, ms | Programs the list lacked | Last link, s after the page opened | Slowest frames, ms |
| --- | ---: | ---: | ---: | --- |
| GPU, cold, before (`--off`, three runs) | 19 954 to 20 459 | 7 to 9 | 23.8 to 25.4 | 13 079 to 13 763, 4 557 to 4 735 |
| GPU, cold, after (three runs) | 2 339 to 2 604 | 5 | 8.1 to 8.8 | 3 206 to 3 571, 767 to 1 630 |
| GPU, cold, after, the list recorded again on a later main (157 programs, two runs) | 1 760 to 1 904 | 2 | 7.1 to 7.5 | 2 513 to 2 790, 1 696 to 1 749 |
| GPU, warm profile, before / after | 337 / 166 to 182 | 7 / 5 | 3.3 / 3.2 to 3.8 | 869 / 803 to 1 090 |

The list itself linked in 2.0 to 2.4 s on the GPU. The online game's cold join (`online.py --gpu --warm-up 0 --pages 1
--bots 1`) seated 6.5 to 7.3 s after the page opened in four runs, against 21 to 22 s with a new socket after the
server's hang-up before. SwiftShader skips the list (last link 8.6 to 8.7 s with it, 8.6 to 8.9 without; the online
join 5.5 to 5.6 s with it, 4.1 to 5.6 without). What is left of the cold page is two programs the engine links at
boot, before any script runs (the copy shader and the default material, about 1 s each), and the level's own load;
a straight route shows the clear colour while it waits for the list (about 2 s). Both went when the page started the
list itself ([The page starts it](#prelink-page)).

- **Approach:** Shorten a cold browser's shader wait by linking a recorded list of the engine's programs at once in
  the engine's own WebGL context (`ShaderPrelink`), and check a cache hit by timing the game's links after it, not the
  list's. **Watch out for:** the first try linked the list in a second context of its own: it finished in 2.4 s and
  the game's links still took 20 s, because a context with other extensions on shares no linked program with the
  engine's; a page of two contexts with all extensions on both showed it in one run. **Seen:** gdstudio #1164,
  2026-11-11 (21 to 8.5 s to the last link on a cold GPU profile).

### The page starts it {#prelink-page}

<!-- new section: the list was started by the menu scene once the engine ran; nothing said how a page starts it before
     the engine boots, nor what that costs or saves -->

The menu scene starts the list only once the engine runs (about 2.6 s after a local page opened), after the engine
linked its two boot programs alone (0.7 s each) and with the clear colour on screen while the list links. A page can
start it itself: with the `gds_game` editor plugin on (the templates turn it on), a web export copies the list
(`ShaderPrelink.list_path()`, the project setting `gds_game/shader_prelink/list`) beside `index.html` and writes the page
script into its head (`ShaderPrelinkExport`, `ShaderPrelink.with_page_start`). The page fetches the list at once and,
once the document is parsed, makes the canvas's WebGL context itself:

- **With the attributes Godot asks for**, so the engine's own `getContext` gets that context back (a second request's
  attributes are ignored): `alpha` from `display/window/per_pixel_transparency/allowed`, depth, no stencil, no
  antialias, premultiplied alpha and a kept drawing buffer (Emscripten's offscreen back buffer asks for it). The page
  wraps the canvas's `getContext` and reports any attribute the engine asks for differently (`gdsPrelink.mismatch`),
  which fails `shader_programs.py`.
- **With every extension on that Emscripten turns on**: all the context offers but `lose_context` and `debug`, so the
  list is translated as the engine's shaders will be.
- **Only where it pays**: a throwaway context asks first whether the browser offers `KHR_parallel_shader_compile`;
  without it (SwiftShader) the canvas is left alone.

`ShaderPrelink.start` then follows the page's links (`gdsPrelink.from` is `page`) instead of reading the file from the
pack. A game made before turns the plugin on under `[editor_plugins]`; without it the menu scene starts the list as
before. Measured with `tools/web_smoke/shader_programs.py` (a fresh profile each run, `?play`, three runs each, the
list of 157 programs; throttled: Chrome's network emulation at 50 Mbit/s and 20 ms, on the uncompressed files):

| Page | Links, ms | Links over 100 ms | Engine's first link, s | Last link, s | Slowest frames, ms |
| --- | ---: | ---: | ---: | ---: | --- |
| GPU, cold, menu scene starts it | 1 695 to 1 778 | 2 (0.7 s each, at boot) | 0.4 to 0.5 | 6.7 to 7.4 | 2 426 to 2 507 |
| GPU, cold, page starts it | 195 to 242 | 0 | 2.5 to 3.1 | 5.5 to 6.4 | 1 971 to 1 991 |
| GPU, cold, throttled, menu scene | 1 749 to 1 783 | 2 | 8.3 to 8.5 | 15.0 to 15.5 | 2 455 to 2 552 |
| GPU, cold, throttled, page | 222 to 237 | 0 | 9.7 to 9.9 | 13.0 to 13.4 | 1 848 to 1 941 |
| GPU, warm profile, menu scene / page | 141 to 180 / 131 to 136 | 0 / 0 | 0.1 to 0.4 / 0.4 | 3.3 to 3.6 / 2.7 to 3.3 | 599 to 630 / 827 to 859 |
| SwiftShader, menu scene / page (skipped) | 183 to 201 / 190 to 205 | 0 / 0 | 0.3 / 0.3 | 7.9 to 8.1 / 7.7 to 8.2 | 1 447 to 1 486 / 1 446 to 1 545 |

The list links in 2.1 s from about 0.1 s, the engine's boot programs and the level's are then found built, and the
straight route no longer waits on the clear colour (the Godot splash shows until the engine draws the level at about
4.2 s, against a blank page until 5.1 s). Two costs: the engine's first GL call waits for the GPU process to take the
list, so on a local page it boots about 2 s later (and still draws the level sooner); and on the throttled page the
downloads ended about 1.5 s later while the GPU process linked (the pack at 3.7 s instead of 2.3 s, the wasm at 9.5 s
instead of 8.0 s), so the engine's splash shows longer. Sending the list in batches of 16 kept the download's pace
(first link 9.0 s, last 12.4 s throttled), but on a local page the engine then booted mid-list and its links took
8.9 s: the list goes at once.

- **Approach:** Compile each program's shaders just before its link, in the list's order (the recorder writes the
  engine's boot programs first), so the GPU process's workers finish the first programs first. **Watch out for:** the
  first page start compiled all 300 shaders before any link: the list took 7.3 s instead of 2.1 and the engine's two
  boot links waited 0.8 s each behind it (4 links over 100 ms, the last at 9.4 s). **Seen:** gdstudio #1183,
  2026-11-11.

### Keeping the list current {#prelink-check}

<!-- new section: nothing checked the committed list against the build, so a new material left programs out silently -->

A program the list lacks is linked at its first draw, up to a second's wait on a cold GPU browser, and nothing else
says the list is out of date. The template job of the kit's CI (and a game's own `ci`) plays the exported page on
SwiftShader, which records the same programs as a GPU, and fails when it links more than 10 programs the list lacks:
`shader_programs.py build/web out --list assets/shaders/web/shader_programs.json --max-missed 10` (it also fails on an
attribute `mismatch`, and the step first checks that the export served the list and wrote the page's start). A current
list lacks 0 to 4 (the warm-up's timing); with 20 of its 157 programs taken out the check counted 23 and exited 1. When
it fails, record the list again with `--write <list> --merge` and commit it. A change to the warm-up counts too:
touring the minimap's view (kit #1297) left the list 12 programs short, and recording it again (`--merge`, the page
plain and with `?play`) took it from 157 to 169, after which the check missed 0 and 1.

- **Approach:** a change that adds anything drawn to a template (a pickup, a capture scene, a level prop) records the
  list again before its push: `uv run --project <worktree>/python gds template test <name> --keep --suite <one suite>`
  makes the game, export it for Web, run the probe through `gds quiet` with `--write <the template's list> --merge`, then
  check a fresh export with `--list ... --max-missed 10`. **Watch out for:** `gds template test` copies the template of
  the kit its `--project` names; run from the main checkout, it measured main's template (2 programs added, CI missed
  13). Check the kept game has your files first. **Seen:** gdstudio #1258, 2026-11-11 (the rifle pickup and hold).

## Testing it {#testing-it}

- **No program linked after the loading screen** in a browser run (the counter above) is the real test.
- A unit test can compare what the night draws with what the warm-up drew. Key each mesh by its kind (plain, skinned,
  multimesh, text, CSG) and its material (a shader's file, or the settings of a `StandardMaterial3D` that change its
  shader), and each light by its type; play the game with a bot for a minute and assert the played set is inside the
  warmed set. Add a test that a new effect with a new material makes that check fail, or the check proves nothing.

## Sources {#sources}

- Godot docs, [Pipeline compilations](https://docs.godotengine.org/en/latest/tutorials/performance/pipeline_compilations.html)
  (Forward+/Mobile only; shader baker not on the web; preload for Compatibility).
- Deadnight, `docs/research/first-use-hitches.md` (the measurements) and `gameplay/night/warmup/` (the implementation).

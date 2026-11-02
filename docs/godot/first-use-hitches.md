# First-use hitches: shader compiles and loads in the Compatibility renderer

The first time something is drawn or sounded in a Godot game, the engine may stop the frame to build or read what it
needs. In a browser build (Compatibility renderer, WebGL2) this is the commonest cause of "it stutters the first time":
the first shot, the first enemy on screen, the first explosion. Measured in Deadnight (Godot 4.7.2, Chrome on Windows,
RTX 5080): about 290 GL programs were linked during the first 20 s of a night, and the worst frame was 390 to 540 ms
(six runs). After the fix below there were none in three runs, and the worst frame was 17 to 25 ms. The game's own
page, with the numbers and the method, is `docs/research/first-use-hitches.md` in Deadnight.

## What the engine does

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
- **A shader goes with the last material that uses it.** `BaseMaterial3D` shares one shader among all materials with
  the same settings and frees it when the last of them is freed. An effect that makes a new `StandardMaterial3D` for
  every flash and frees it a moment later frees the shader with it, and **every single use builds its programs again**.
  In Deadnight this was nearly all of the 290 builds (about 6 per shot). This is a hitch at *every* use, not only the
  first.
- **Resources load on first `load()`.** A resource nothing references is freed, and `load()` reads it again. Hold a
  reference to what the next minute needs.
- **Chrome keeps a program cache** in the browser profile, so a second visit on the same profile hides the problem.
  Measure with a fresh profile every run (Playwright's `launch` makes one).

## How to find it

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

## The first draw of a shader builds four programs, two of them huge

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

## Drawing the level in pieces

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

## The warm-up

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

## A warm-up on the CPU pays for every pixel

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

## Particle systems: two programs of their own, and a sample that expires

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

## Testing it

- **No program linked after the loading screen** in a browser run (the counter above) is the real test.
- A unit test can compare what the night draws with what the warm-up drew. Key each mesh by its kind (plain, skinned,
  multimesh, text, CSG) and its material (a shader's file, or the settings of a `StandardMaterial3D` that change its
  shader), and each light by its type; play the game with a bot for a minute and assert the played set is inside the
  warmed set. Add a test that a new effect with a new material makes that check fail, or the check proves nothing.

## Sources

- Godot docs, [Pipeline compilations](https://docs.godotengine.org/en/latest/tutorials/performance/pipeline_compilations.html)
  (Forward+/Mobile only; shader baker not on the web; preload for Compatibility).
- Deadnight, `docs/research/first-use-hitches.md` (the measurements) and `gameplay/night/warmup/` (the implementation).

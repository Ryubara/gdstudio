# Compatibility lighting and post-processing

A spike (kit issue #8) on what the Compatibility renderer (OpenGL, the WebGL2 web build) does for a dark night scene
lit by a big screen, neon and lamps: LightmapGI baking, Environment features, dynamic light counts and one full-screen
post shader. The throwaway project is `sandbox/compat-lighting/`; the captures are attached to the pull request.

## How it was measured

- **Scene:** a 60 m lot (6 x 6 ground tiles), an 18 x 8 m emissive screen, 15 box "cars", a lamp post, a neon sign;
  three base lights (lamp, neon, screen glow); about 69 draw calls and 5 500 triangles. Deliberately small.
- **Hardware:** NVIDIA GeForce RTX 5080, Godot 4.7.2, `gl_compatibility`, desktop, Windows. **This is a very fast GPU,
  so absolute numbers are tiny and are not web numbers.** Read them as *relative* cost, and as an upper bound on how
  cheap things can be. Run-to-run noise is about +-0.01 ms at 1080p and +-0.02 ms at 2160p (the same setup measured
  0.029, 0.030 and 0.038 ms in three runs).
- **Method:** the scene renders in a `SubViewport` of 1920 x 1080 or 3840 x 2160 (the 4K run is a stress test that
  makes cost visible), 120 warm-up frames then 300 measured, vsync off.
  GPU time is `RenderingServer.viewport_get_measured_render_time_gpu` (works in Compatibility). Whole-frame time sat at
  0.8 to 1.3 ms for every setup (CPU and present bound), so it does not separate the setups; it is in the logs only.
- **Not measured:** a real browser, a weak GPU, a phone. Do those before trusting any cost below for the web build.

## Environment features

GPU ms are for the whole viewport, base scene = 0.044 (1080p) / 0.105 (2160p).

| Feature | Works in Compatibility | 1080p ms | 2160p ms | Notes |
| --- | --- | --- | --- | --- |
| Tonemap: linear, reinhard, filmic, ACES, AgX | yes | 0.035 to 0.050 | 0.100 to 0.120 | free (inside noise). ACES and AgX turn bright emissive to white (neon looks white). Filmic and Reinhard keep the neon pink. |
| Glow | yes | 0.121 | 0.325 | about +0.08 / +0.22 ms; +18 MB video memory. Neon, lamp and tail lights get a halo: the best single mood gain. It also lifts the whole dark background a little. |
| Fog (exponential, `fog_density` 0.025) | yes | 0.056 | 0.137 | cheap, adds depth haze. |
| Adjustments (brightness, contrast, saturation) | yes | 0.099 | 0.216 | about +0.05 / +0.11 ms and +16 MB, so not free; post shader grading is the alternative. |
| SSAO | accepted, **no visible change** | 0.155 | 0.436 | costs time and 24 MB for nothing we could see. The docs list SSAO as supported, our night scene showed no difference. Leave it off. |
| Volumetric fog | **no** (silently ignored) | 0.050 | 0.095 | no change in the image. Fake a beam with a mesh (see below). |
| SSR, SDFGI | **no** (silently ignored) | 0.035 | 0.100 | no change in the image. |
| Filmic + glow + fog + adjustments together | yes | 0.138 | 0.354 | roughly the sum. |

## Dynamic lights

Extra lights on top of the three base lights, no shadows, 1.6 to 3 energy, range 9 to 12 m, spread over the lot.

| Setup | 1080p ms | 2160p ms | Draw calls |
| --- | --- | --- | --- |
| base (3 lights) | 0.044 | 0.105 | 69 |
| +4 OmniLight3D | 0.046 | 0.135 | 69 |
| +8 OmniLight3D | 0.059 | 0.150 | 69 |
| +16 OmniLight3D | 0.064 | 0.209 | 69 |
| +16 OmniLight3D, one big ground mesh | 0.065 | 0.239 | 44 |
| +8 SpotLight3D | 0.075 | 0.173 | 69 |
| +16 SpotLight3D | 0.071 | 0.264 | 69 |
| 1 shadowed SpotLight3D | 0.047 | 0.135 | 69 |
| 1 shadowed OmniLight3D | 0.046 | 0.131 | 69 |
| shadowed DirectionalLight3D ("moon") | 0.105 | 0.213 | 197 |
| spot with `light_projector` texture | 0.047 | 0.135 | 69 |

- **Up to 19 lights total (3 + 16) cost about 0.02 ms at 1080p** here: cost scales with covered pixels, so it shows at
  4K (+0.1 ms) and will show on a weak GPU. Every light is evaluated per pixel it touches, in one forward pass.
- **Limit of 8 lights per mesh** (Godot docs: "8 per mesh. Can be increased"): a mesh touched by more lights drops
  some. We saw it on one 60 m ground plane (it lost some of the 16 pools) but the effect was subtle with our
  lights. The cure, splitting the ground into tiles, cost +25 draw calls (44 vs 69). Keep big surfaces tiled to the
  size of a light's range, or keep overlapping lights to 8 near any one mesh. The limit is a project setting
  (`rendering/limits/opengl/max_lights_per_object`).
- **Shadows work** (spot, omni and directional all drew visible, correct shadows) and were not measurable on this GPU.
  The docs say lights with shadows use a multi-pass approach in Compatibility, and the directional shadow doubled the
  draw count (197 vs 69). On the web a few shadowed lights is the budget, not dozens. Use one shadowed light at most
  per view (the projector beam) and unshadowed lights for the rest.
- **Light projector textures are not supported** in Compatibility (docs): the `projector` capture lit a patch but showed
  no pattern. A cheap "film beam" is a transparent additive cone mesh, not a projected light.

## Full-screen post shader

A `ColorRect` on a `CanvasLayer` with a canvas_item shader (colour grade + vignette + grain).

| Setup | 1080p ms | 2160p ms | Video memory |
| --- | --- | --- | --- |
| base | 0.044 | 0.105 | 29.3 MB |
| `post_overlay`: vignette and grain as a translucent overlay (no screen read) | 0.068 | 0.159 | 31.4 MB |
| `post_grade`: reads `hint_screen_texture` (grade + vignette + grain) | 0.224 | 0.317 | 41.9 MB |

- Reading the screen costs a back-buffer copy: about **+0.18 ms at 1080p, +0.21 ms at 4K**, +12 MB. That is 4 to
  5 times the overlay version. The overlay version can darken and add noise but cannot grade colour.
- The grade shader does the job the Environment adjustments do, for a bit more; use one or the other.

## Combined

| Setup | 1080p ms | 2160p ms |
| --- | --- | --- |
| filmic + glow + fog + 8 omni + post overlay | 0.175 | 0.480 |
| filmic + glow + fog + 8 omni + post grade | 0.271 | 0.590 |
| lightmap + filmic + glow + fog + adjustments + post grade | 0.330 | 0.612 |

Even the heaviest is 0.33 ms at 1080p on the RTX 5080: roughly 7 times the base scene's cost, but 2 percent of a
16.7 ms frame. Multiply by whatever ratio your weakest web target has to this GPU (often 10 to 30 times slower).

## LightmapGI

| Quality | Bake time | Bake file | Atlas |
| --- | --- | --- | --- |
| low | 1.8 s | 58 KB `.lmbake` | 256 x 1024 EXR, 432 KB source, 256 KB imported (BC6H) |
| medium | 1.3 s | 58 KB | same |
| high | 5.9 s | 58 KB | same |
| ultra | 5.4 s | 58 KB | same |
| low, texel scale 0.5 | 1.2 s | 58 KB | 98 KB imported |
| low, texel scale 2 | 1.8 s | 58 KB | 1.5 MB source, 768 KB imported |
| ultra, bounces 8 | 3.3 s | 58 KB | 256 KB imported |

- **Baking works only from a Vulkan editor.** The Compatibility editor presses "Bake Lightmaps" and returns after 0 s
  with no file and no console error (the bake needs a RenderingDevice, and the docs say so). `LightmapGI.bake()` is also
  not exposed to scripts. We drove the editor's own button from a tool plugin
  (`sandbox/compat-lighting/addons/bake_driver/`) launched as `godot --editor --rendering-method forward_plus`. The
  baked data then renders fine in the Compatibility game.
- The `LightmapGI` node must have a saved `light_data` before the button bakes in place; with none it opens a file
  dialog and nothing happens from a script.
- Meshes need UV2 (`add_uv2` on a primitive mesh, or unwrap on import) and `gi_mode` Static. Bake time here is
  tiny and not monotonic in quality (the scene is too small and the GPU too fast): do not read a trend into it.
  A real lot will take far longer.
- Runtime cost: **free**. A lightmapped scene with no dynamic lights measured 0.03 to 0.05 ms at 1080p, below the
  dynamic base scene, and adds 0.4 MB video memory. A lightmap plus 8 or 16 dynamic lights costs the same as the
  dynamic lights alone (0.058 / 0.068 ms).
- Imported as BC6H (`s3tc_bptc`, desktop) at 1 byte per texel. Web needs a mobile format; we did not check how the
  web export compresses an HDR lightmap. **Open question.**
- **The result looked bad and we could not explain it.** At default settings the baked ground was a flat blue-grey
  fill with no readable lamp, neon or screen pools; changing only texel scale or bounces gave near-black ground
  (`lm_ultra_texel2`, `lm_low_b0`) rather than a quality ladder. Baked Static lights no longer light the scene at runtime,
  so a vanished pool means the bake failed to capture it. Setting `environment_mode` to custom colour did not change
  the bake output we measured (identical file sizes), and we did not isolate why in the time box. Until a follow-up
  spike gets a bake that matches the dynamic look, **do not plan the drive-in's mood on LightmapGI.**

## Night mood: honest judgement

- **Works:** filmic tonemap + glow + fog + a handful of coloured omni lights + emissive meshes gives a convincing
  neon-and-screen night. The neon sign, lamp bulb and tail lights bloom; the screen reads as the light source; fog
  separates the far cars. See `sheet_recommended.png`.
- **Weak:** the ground away from any light is pure black, and unlit cars vanish into it. With a dark ambient colour
  (0.05, 0.06, 0.11) the lot is unreadable beyond about 10 m from a light. The mood needs a gentle moon fill (shadowed
  directional light at 0.5 was the single most readable setup: ground, cars and shadows all legible) or a brighter
  ambient, which costs contrast.
- The screen is flat: it lights the lot only as an omni point at its base, so there is no cast of changing screen colour
  on car roofs. A fake (animated omni colour, or an emissive floor decal) will be needed.
- Film grain and vignette from the overlay shader read as cheap-film mood without damaging the dark scene.
  The grade shader (desaturated, blue-tinted shadows) is the more graded look but cost 4 times as much.

## Recommendations for the drive-in

1. **Light the lot with dynamic lights, not LightmapGI,** until a follow-up spike makes baked lighting look right.
   Budget: 3 to 8 unshadowed omni/spot lights near the camera (lamps, neon, screen glow), at most 16 on the whole map
   with each mesh seeing 8. Tile the ground.
2. **One shadowed light per view:** a dim directional "moon" (energy about 0.5) for fill and readable shadows, or the
   projector spot, not both on the web until measured on a browser.
3. **Environment:** `tonemap_mode` filmic or reinhard (not ACES/AgX: they whiten neon), glow on with `glow_hdr_threshold`
   near 1 so only emissives bloom, exponential fog dark blue, brightness/contrast through the grade or adjustments, not
   both. Leave SSAO, SSR, SDFGI and volumetric fog off: they do nothing or do nothing visible.
4. **Post:** the overlay (vignette + grain) always, as it costs 0.02 ms; the screen-reading grade only if we want colour
   grade and can afford about 0.2 ms on the weakest device. Offer it as a quality setting.
5. **Fake the beam and the screen light:** an additive transparent cone mesh for the projector, an emissive mesh
   for the screen, plus glow. Light projector textures and volumetric fog do not exist in Compatibility.
6. **A clean console proves nothing here:** unsupported features (volumetric fog, SSR, SDFGI) and a failed bake both
   print no error. Verify with a capture.
7. **Before committing to any of this, measure on a real browser and a weak GPU,** and re-run the matrix there
   (`sandbox/compat-lighting/run.sh`).

## Reproducing

```text
GODOT=$(uv run --project python gds tool path godot)
cd sandbox/compat-lighting
$GODOT --editor --rendering-method forward_plus --path . -- --bake=low      # writes bakes/ (not committed)
./run.sh tm_filmic+glow+fog+omni8+post_overlay                              # 1080p + 2160p, RESULT lines
```

A setup is `+`-joined tokens: `tm_filmic|aces|agx|reinhard|linear`, `glow`, `fog`, `adj`, `volfog`, `ssao`, `ssr`,
`sdfgi`, `omniN`, `spotN`, `bigground`, `shadow_spot|omni|moon`, `projector`, `post_grade`, `post_overlay`,
`lm_<bake name>`. `--sway` moves the camera for Movie Maker captures.

## Sources

- [Compatibility renderer feature list](https://docs.godotengine.org/en/latest/tutorials/rendering/renderers.html)
- [Using LightmapGI](https://docs.godotengine.org/en/latest/tutorials/3d/global_illumination/using_lightmap_gi.html)

## Lamps in a game: what looks like light and what is light

What a lighting pass on Deadnight's lot (a night with about 30 lamps, a screen, neon and a projector, web build) taught;
the game's own page is `docs/research/night-environment.md` there.

- **Pools of light are additive quads, not light range.** The 8 lights per mesh cap makes a bigger `omni_range` a
  worse idea than it looks: 14 m instead of 11 m put 11 lights on one 24 m ground tile. A flat `QuadMesh`
  (`orientation = FACE_Y`) with an `unshaded`, `blend_add` shader and a radial falloff gives a visible pool on the asphalt
  for one transparent quad and no light slot. The same shader as a billboard (`MODELVIEW_MATRIX` rebuilt from
  `INV_VIEW_MATRIX`) is the halo round a bulb, a sign or a breaker lamp, which is what glow post-processing would add
  for +0.08 ms of full-screen cost.
- **A projector beam is a cone mesh**, not a light: an elliptical cone with smooth normals, an additive shader, vertex
  colour for the fade from the lens, and `abs(dot(NORMAL, VIEW))` to fade at the silhouette. Flat faces show their seams.
  Give it an `extra_cull_margin` if it spans the map.
- **Make what glows follow the light, not the rules.** A `LightFollower` node reads the lamp's `light_energy` over its
  scene energy (0 when the light is hidden) and draws that: the circuit, a failing tank and an afterglow reach every
  glow through the one lamp, with no second path to keep in step. Flicker as a function of an accumulated phase, never
  `TIME`, so Movie Maker and tests see the same light.
- **Test the cap.** With every light on, count per mesh the lights whose sphere (omni) or cone box (spot) reaches its
  AABB; fail above 8. It found a tile that no visual check would. Walk every shaded mesh (each CSG root,
  `MeshInstance3D` and `MultiMeshInstance3D` with a lit surface, props and cars included), not only the level's boxes,
  and read the cap from the project setting. A cone is counted by the box of its widest end (`range * tan(angle)`),
  so an 85 degree spot of 10 m range is a box 114 m wide: it took a crane spot at the other end of the lot over the
  cap (Deadnight #852). Keep a spot's cone narrow (60 degrees: 17 m) when its corner is quiet.
- **Keep room for the lights of a fight.** Muzzle flashes, blasts and grenades are run-time omni lights, so the level's
  own lights may reach a mesh with at most the cap minus 2. A test that greps the project's scripts and scenes for
  light nodes and fails on one not accounted for catches the forgotten source. Known overruns go in a ratchet table:
  the test fails if one grows, or if one no longer needs its entry.
- **Cut big ground tiles along the lights that reach them.** A lamp reaches a whole mesh when it reaches any corner, so
  a 16 m tile under two lamp rows counts both. Search the cuts that keep every piece at or under the cap minus 2, and
  re-run the search when a light lands beside the mesh. Deadnight cut its field into 12 pieces and its stand's floor
  and roof into four: 12 more draw calls, no measurable cost on the web.
- **Emissive swatches of a shared palette atlas** are lit by an emission texture of the same layout painted in code
  (black but for the swatches), on a duplicated material set as the surface override: one model, one material, only the
  asked-for colours glow.
- **A flat glow or window quad needs `cull_disabled`.** A `QuadMesh` on a `StandardMaterial3D` culls its back face by
  default, so a lit window pane glowed from the field and was a hole from the room (Deadnight #701). The lot's glow
  shader already said `cull_disabled`; only the one standard-material pane did not. An additive pane draws one face per
  viewer, so two sides do not double the glow, but a two-sided pane that overlaps a wall shines through it: place it in
  its opening. Test every flat see-through mesh (smaller than a few cm on one axis, transparency or a blend) for
  `cull_disabled`; a closed vessel such as a soda glass keeps back-face culling.
- **A billboard glow reaches as far as its half-size, in every direction.** A camera-facing additive quad turns about
  its centre, so a 9 x 4 m halo 0.4 m off a wall lay across the wall's plane seen from the side: 4 m of it behind the
  wall (a pink bloom in the room) and the rest hanging past the wall's ends (Deadnight #703, the maintainer's hand fix:
  `billboard = false`, lower energy, higher falloff). Compare a glow's half-size with its distance to each wall near
  it, and capture it from the room behind the wall and along the wall with the glow hidden and shown. Compatibility
  has no shadows, so the sign's `OmniLight3D` also lights the room through the same wall: keep its energy in step
  with what the room can take. A halo's `energy` in the scene is only its first value when a script drives it.
- **A glow or a light has a side: clip the card, face the light.** The depth test is a glow card's only wall and a light's
  sphere its only limit (Deadnight #832, after #703). Give a card up to two world-space clip planes (a `clip_a` and
  `clip_b` uniform vec4 in the glow shader, discard where `dot(world, n) > w`) found from the wall boxes beside its lamp,
  and make a lamp on the outside of a wall a `SpotLight3D` facing out (its cone never passes its apex plane). Test every
  additive card against the walls (a point behind a wall seen from its lamp; a wall-mounted card hanging past its wall)
  and every light against the floors, roofs and walls it reaches through a wall. What stays is a room lamp reaching the
  next room by its range (0.2 to 0.7 energy at 5 to 9 m): a light layer per room stops it (the next bullet).
- **A light layer per room is the shadow Compatibility does not have, for free.** A light lights only the meshes whose
  `layers` share a bit with its `light_cull_mask` (checked in a Compatibility scene: a box on layer 2 is lit by a lamp
  with mask 1|2, a box on layer 4 stays black), so a lamp that names the default layer and its room's lights the dead and
  the props (on layer 1) and its room's floor, ceiling and walls, and not the next room's. It is two integers in the
  scene: no draw call, no light, no shader program (Deadnight #841: the stand's, the booth's and the second map's lamps,
  0.2 to 0.7 energy through walls cut to what is left below, frame cost unchanged within the spread). What to know:
  `layers` is the camera's too (a box off layer 1 still draws: the camera sees 1 to 20); a lamp must keep bit 1 or it
  leaves the dead standing in a lit room dark; a mask belongs to a whole mesh, so one box that is a wall of two storeys
  or a floor and the terrace past a wall takes the light of both sides (splitting it costs a draw call); an opening in
  the wall no longer passes the lamp's light, so a doorway's spill is the glow card's job. Move only the surfaces that
  are lit through a wall, not every box, and test both ways: no lamp reaches a surface through a wall beyond a table of
  reasons, and no lamp loses a surface it could see beyond a second table (the cost shows in that table, not in the
  leak one). A downward `SpotLight3D` for a ceiling lamp (cone under 90 degrees) cures the wall above it but takes the
  light off the ceiling over it, which changes how the room looks.
- **A spot's forward is its -Z, and its reach is the box of its cone.** A builder's `yaw 180` faced a projector's spot at
  the road, not the screen, for the life of a map (Deadnight #840): print `-global_basis.z` of every spot and test where
  it points. Turned right, the cone aimed at the screen's middle dipped under a roof 20 m away and put a seventh light on
  the stand. Set the pitch equal to the half-angle so the cone's lower edge runs level at the light's own height: nothing
  lower (roofs, cars, the ground) is in its box. A screen drawn by an unshaded shader takes no light from it: the spot
  shows on the frame and the posts only.
- **A lamp placed by hand can push a tile over the cap.** Twenty posts added in the editor (Deadnight #703) put five
  ground and roof meshes at 7 or 8 lights. Search the cuts instead of loosening the cap: dump every light (position and
  range, and the crane's lamp at each of its places) and every mesh box to JSON, then try cut lines on a 0.5 to 1 m grid
  in Python with the test's own reach rule (sphere against the box, cone box for a spot) and keep the fewest tiles with
  none above the budget. It took one cut moved for the midway, fewer tiles for the back lot (4 to 3) and the yard
  (4 to 2), and one more roof cut. Put the hand-set numbers into the scene's builder first, or the next run of it
  writes the old map.
- **A global class name clash is silent until export.** `class_name NeonSign` in the lot hid the UI skin's `NeonSign`;
  the editor and a headless run were fine and the web export printed `Class "NeonSign" hides a global script class`.
  Grep `class_name` before naming one.

## Light cards indoors: moon shafts, door glow, chalk

What the second Deadnight map's lamps taught (Deadnight #636; its page is `docs/research/maps/small-map-art.md` there).
Indoors the Compatibility renderer's gaps show more than on an open lot: nothing casts a shadow, so the moon lights
every floor under a roof and a lamp lights the next room through the wall.

- **Keep the directional moon low indoors** (0.1 against the lot's 0.36) and let cards carry the moonlight: with no
  shadow it lifts every floor under the roof evenly and lowers the shafts' contrast.
- **A new map's scene joins the light cap from its first commit.** A generator borrowed from an outdoor map brings
  its lamps and its 0.36 moon: list the scene where the project's light check looks (Deadnight's `LIGHT_SCENES`),
  give it a suite that counts its lamps per mesh against the cap less the fight's two, and set the moon low.
- **A moon shaft is the opening projected along the moon's direction**: each point of the opening plus `t` times the
  direction until it meets the floor (or a wall ahead, whichever is nearer). Built in rows along the opening's height,
  a patch that runs onto a wall bends at the corner. Two sheets from the opening to the patch are the haze. The bars'
  shadows are stripes in the card's shader (`fract` of U times the bar count, a soft step), not a texture, and because
  U and V run across the opening they land where the real shadow would.
- **Extend a shader with uniforms rather than writing a new one.** A program is per shader file: a `card` mode, bar
  stripes and a greyscale mask added to the lot's glow shader (defaults leave the old picture) gave the shafts, the
  door glow and the chalk lettering with no GL program the warm-up did not already build (kit
  [first-use hitches](first-use-hitches.md)).
- **Additive chalk shows only where light falls**: a lettering mask drawn additively in the chalk colour reads in a
  moon patch or under a lamp and fades into the dark wall elsewhere, which is where the writing should be read anyway.
- **What they cost:** a room with eleven cards and three cones in view, 0.1 ms in Chrome on an RTX 5080 (2.30 to
  2.42 ms a frame, unpaced), no GL program linked while playing.
- **Fade haze near the camera.** Players walk under ceiling lamps; from inside a haze cone every face looks at the
  camera and the screen washes. `smoothstep(0.2 * near, near, -VERTEX.z)` on the haze removes it within a couple of
  metres.
- **A light under a door is two cards**: one filling the opening on the far side, brightest at the floor (it shows
  through the planks' cracks and over a debris blocker, depth-tested by the door), and a trapezoid on the near floor
  fading into the room.

## A backdrop past the playable bounds

What the outside of Deadnight's indoor map taught (Deadnight #638; its page is `docs/research/maps/small-map-art.md`
there): the drive-in seen through windows and broken walls, 20 to 150 m out, never walked.

- **Dense indoor fog sinks the outside.** A small map's fog (0.035) puts everything past 40 m at the fog colour. The far
  models write their own haze: the scene's density near, capped (0.5 at 20 m rising to 0.82 at 150 m) and brightening
  toward the horizon far off, so the layers part. A node copies the environment's fog, ambient and moon into the
  materials every frame, so a round's darkening reaches them.
- **Make the far models unshaded and light them in the shader** (ambient plus the moon's `N.L`): no light pass per
  mesh, no slot in the 8-light cap, and no lamp indoors lights the outside. Writing the `FOG` output of a lit shader
  gave black and blown-out results in Compatibility.
- **Pass colours as they are.** Compatibility takes a colour uniform as is (as if it lit in sRGB space): the fog
  colour through `srgb_to_linear` drew ten times too dark
  ([lesson](../lessons/2026-11-03-a-backdrop-colour-passed-as-linear-drew-ten-times-too-dark.md)).
- **One `MultiMeshInstance3D` per model.** A `.tscn` cannot point into an imported glTF scene, so the multimesh names
  the scene in metadata and a node takes its first mesh at load; models exported as `.obj` are plain meshes. 330
  copies in 37 drawing nodes, 62k triangles.
- **Glow by atlas cell**: emission where `floor(UV * 5)` is a bulb or neon cell (Godot's UV starts at the image's top,
  [lesson](../lessons/2026-11-03-an-atlas-cell-read-from-uv-was-upside-down.md)); fires and halos are glow quads, no
  light.
- **Cost on the web**: 34 more draw calls and about 0.4 ms a frame in Chrome on an RTX 5080 (1280 x 720, unpaced,
  alternating 50-frame blocks with and without in one page), about 10 % on SwiftShader.
- **Prove it from the player's camera** in a blockout room and outside it, with a hidden floor under every spot
  ([lesson](../lessons/2026-11-03-a-capture-spot-outside-the-room-had-no-floor.md)).

## A lamp near a wall

Compatibility draws no shadows, so a lamp reaches through a wall by its light's range and by the size of its ground pool
(a flat additive card): a post 2.4 m from a fence lit and glowed the room behind it (Deadnight #851: 28,000 to 330,000
pixels of the next room, measured with each part hidden and shown from the player's camera on the far side).

- **A spot cannot pass its apex's plane.** Swap the omni for a spot (the same slot in the 8-light cap) aimed down and away
  from the wall: a cone of half angle `a` tilted `t` from straight down stays off a wall's side when
  `sin(t) * c >= sin(a)`, `c` being the cosine of the angle between the aim and the wall's normal (1 for one wall,
  0.71 in a corner). A 30 degree cone needs 32 degrees of tilt by one wall and 47 in a corner; a steeper cone or tilt reaches
  more meshes and can break the light budget (a 38 degree cone tilted 65 reached one more tile).
- **Shrink the pool and move it away.** A pool of half-size `h` moved `h/2` away from a wall at distance `d` stops short
  of it when `h <= d / (1 - c/2)`. The halo stays: it is the bulb's, and the bulb is seen over the wall.
- **Measure it hidden and shown**, from behind the wall, with a hide the game does not undo (`light_cull_mask = 0`,
  `layers = 0`, never `visible`;
  [lesson](../lessons/2026-11-03-hiding-a-lamp-part-to-measure-it-was-undone-by-the-lamps-own-update.md)).
- **A flickering lamp never goes dark**: keep its energy above 0 so the light stays `visible`; a light that toggles
  changes a mesh's set of lights.

## A column of light has a length from what is above it

A beam, a shaft or a pillar of additive haze drawn as a fixed-length mesh shows through every floor and roof over its
source: the depth test only hides the part of it that lies behind a surface from the camera, never the part past the
surface on the camera's side, so from the floor above (or a roof) it rises out of the slab (Deadnight #911: the prize
crane's 36 m beam through the concession's roof and the second map's upper floor). Cut its length where it is placed,
with one ray up from its foot on the world layer (`PrizeCrane.beam_length_over`): shorten the same cone (same taper, a
`cut` uniform on the same shader) and fade the last metre or so, with no new mesh, light or program. Outdoors the ray
meets nothing and the beam keeps its full length. A test casts the same ray from every spot of every map and checks
nothing solid stands inside the beam, and a capture is taken from the first solid over each spot, looking at where the
beam rises through it.

# Prototype surfaces and daylight

How the 3D Blank template's level is painted and lit with no texture or sky file, and what Godot did while we tuned it
(kit issue #773). The level is described in the game's own docs (`docs/design/prototype-level.md` in a game made from
the template); this page is how the engine behaves. Since #821 3D Blank holds only the floor and walls on this
surface, and since #831 they are `ProtoBlock` nodes (resize one in the inspector); the prototype map and the six
components described below are in 3D Third Person ([The 3D Third Person template](third-person-template.md)), and the
sections here still describe both. Everything here was measured
in the Compatibility renderer, on the desktop and in headless Chromium (SwiftShader) with the web export, and looked
the same in both.

## A grid with no texture {#a-grid-with-no-texture}

`templates/3d-blank/game/assets/shaders/prototype/prototype_grid.gdshader` draws the grid in the fragment shader from
the world position, three planes (x, y, z) blended by the normal raised to the eighth power. The cell size and the
major-line spacing are not material parameters: they are two shader globals (`prototype_cell_size`, 1.0 m, and
`prototype_major_every`, 8, in Project Settings > Shader Globals), so every colour material agrees, and the
`prototype_grid` editor plugin sets the 3D editor's translate snap to the same cell size when the project opens or the
value changes: a block moved with snap on lands on the grid lines (blocks of even size put their faces on them).

| Question | Answer |
| --- | --- |
| Why world space | A `CSGBox3D`'s UVs do not grow with its size, so a texture would stretch whenever a block is resized in the inspector. A world-space cell is 1 m on every face at any scale, and neighbouring blocks line up. |
| Why three planes and a blend | The ramp is a slope: a dominant-axis pick shows a seam where it passes 45 degrees. The blend costs three pattern evaluations a pixel and no texture read ([Surface materials](surface-materials.md) measured the texture-reading triplanar as slower; this one was not measured against it). It is a prototype shader: a level that ships bakes its look into textures. |
| Lines that do not shimmer | `fwidth` of the cell coordinate is the footprint of a pixel; a line fades out where the footprint passes a third of a cell, so a far floor is a calm tone. It is `fwidth` in the fragment stage, so it cannot sit inside a branch. |
| Licence | None needed: no file. The icon is our own SVG. |
| Blocks | Solids are `ProtoBlock` nodes (`world/blocks/`), not CSG: a mesh that carries UV2 for the lightmap and a `StaticBody3D` made from one `size`, so the grid still has 1 m cells at any size. |

## Daylight in the Compatibility renderer {#daylight-in-the-compatibility-renderer}

Numbers that gave the template's look, in `world/lighting/`:

- **Sky ambient is too blue and too bright.** With `ambient_light_source` set to Sky and a saturated
  `ProceduralSkyMaterial` top colour, a floor in shadow rendered about (0.35, 0.6, 0.85): a bright, saturated blue,
  not a shade. The template uses an ambient colour
  (0.62, 0.68, 0.78) at energy 0.8 with 0.15 of the sky mixed in.
- **A directional light is strong.** With the filmic tonemap, mid-grey albedo (about 0.46) and a single sun, energy
  1.0 clipped the sunlit floor to white; 0.6 keeps the grid readable. Tune the sun last, against the ambient.
- **Specular whitens a far floor.** A grazing view of a rough floor still reflects the sky (Fresnel): `SPECULAR` 0.12
  in the shader stops the far floor and walls turning white and keeps the surfaces matte.
- **The sky below the horizon shows past the walls.** A dark `ground_bottom_color` read as a cliff behind the
  boundary walls. Ground colours close to the horizon haze make the arena sit in mist.
- **Walls make shadow.** The near walls' shadows fill strips of the floor in front of the camera; 4 m walls rather
  than 6 m shrank them. One shadowed directional light, orthogonal, with `directional_shadow_max_distance` 60 m, is
  the budget ([Compatibility lighting](compat-lighting.md#dynamic-lights)). Shadow edges step visibly at the
  default size; `soft_shadow_filter_quality` 3 made little difference in Compatibility.

## Smaller findings {#smaller-findings}

- **CSG collides one frame late.** `use_collision` builds the collider when the CSG tree updates, so a test that drops
  a body onto a fresh level waits physics frames before judging where it landed (120 frames: the crate rests at 0.5 m).
  The level has used `ProtoBlock` instead since #788; the note holds for any CSG level.
- **A flat `Label3D`** reads from the +z side when rotated (-90, 0, 0); (-90, 180, 0) reads from the -z side, the
  side a player standing in the middle of the level looking at the jump blocks sees.
- **Movie Maker is one frame behind `_process`.** The frame written is the state `_process` left on the previous call,
  so a tour that cuts to a new view every N frames sets the first view in `_ready` and chooses each view one frame
  ahead; otherwise frame 0 is the default camera and every cut shows late.
- **The synced `gds_ui` addon's demo does not parse without the `UIRouter` autoload.** Import, a run and the tests
  are clean, but the editor and `--export-release` load every script and printed parse errors for the five demo
  scripts. Registering the autoload and the plugin in the template's `project.godot` fixed it (gdstudio #814); the
  first answer, excluding `addons/gds_ui/demo/*` from the export, hid the cause and left the editor errors.
- **GdUnit4's `-rd <folder>` takes an absolute path on Windows only.** A path that starts with `/` is read as `res://`
  plus the path (`make_qualified_path`), so on a Linux runner `-rd "$RUNNER_TEMP/reports"` wrote `game/home/runner/...`
  inside the project. Godot runs in the project folder, so a relative path starts there: `-rd reports` made
  `game/reports`, and `-rd ../../../reports` (from `repos/<game>/game`) lands in the work folder, outside the
  repository; keep a final `git status --porcelain` step after the tests, which caught this and an import that left
  uids behind (Deadnight, 2026-11-07).
- **`gdformat` writes CRLF on Windows**; run `sed -i 's/\r$//'` over the scripts it touched
  ([The shell](../../studio/shell.md#line-endings)).

## Measured on the export {#measured-on-the-export}

The 3D Blank web export (`--export-release Web`, Compatibility, no threads) is a 154 KB `index.pck` (the level and
the synced `gds_ui` addon, no demo) and a 39.5 MB `index.wasm` (the engine); it holds the level and no file of `tests/`
or `tools/`. Opened in headless Chromium with SwiftShader it drew the level, shadows and labels with no console
error, page error or failed request.

## Web first, Forward+ as a layer {#web-first-rework}

<!-- new section: the page covered the Compatibility-only level; nothing said how one level serves both
     renderers or what it costs -->

Kit issue #788 reworked the template into one level that is lit for the Compatibility renderer and gets Forward+
extras on a desktop. What was built and measured (Windows, RTX 5080, Godot 4.7.2):

| Part | What it is |
| --- | --- |
| Renderer by platform | `rendering_method` Forward+; `.web` and `.mobile` overrides Compatibility. The test reads all three. |
| Baked light | `LightmapGI` (medium, 3 bounces) over 50 `ProtoBlock` meshes; the sun stays Dynamic (bounce baked, shadows real-time); a baked static `OmniLight3D` lights the room. Bake 0.9 to 2.0 s; `.lmbake` 45 KB, atlas 256 x 256 x 2 layers (EXR 278 KB). |
| Reflection probes | Two, at `reflection_size` 64: 84 MB of texture memory in Compatibility, 325 MB at the default 256 ([Compatibility lighting](compat-lighting.md#lightmapgi)). |
| `GraphicsProfile` | A node set in the inspector (SSAO, SSIL, SSR, volumetric fog, SDFGI instead of the lightmap, four shadow cascades, an exposure match); it does nothing unless the renderer is Forward+. |
| Map components | `Door`, `Pickup`, `TriggerZone`, `MovingPlatform`, `SpawnPoint`, `PhysicsProp` in `gameplay/`, each working alone from the inspector, with signals. |

| Measure | Before (CSG, no bake) | After |
| --- | --- | --- |
| Compatibility draw calls in a frame (overview camera) | 60 | 148 (shadow pass included) |
| Compatibility texture memory | 68 MB | 84 MB |
| Compatibility CPU / GPU time, RTX 5080, vsync off | 0.20 / 0.16 ms | 0.32 / 0.18 ms |
| Forward+ draw calls / texture memory | 60 / 163 MB | 241 / 348 MB (profile on) |
| Web export `index.pck` | 188 KB | 524 KB (the saved meshes and the lightmap) |
| Web frame, headless Chromium on SwiftShader, 960 x 540, mean of three runs of 8 s | about 46 ms | about 55 ms |

SwiftShader draws on the CPU, so it only says "runs with no GPU and no console or page error"; a real phone was not
tried. In Forward+ the same scene reads darker than in Compatibility, so the profile lifts the tonemap exposure by
1.35 (it also lifts the sky, so the sky ends a little brighter than the web build's).

- **Approach:** Make a shader's grid size one project value (a `global uniform` and a shader global) and set the editor
  snap from it with a tool plugin that confirms the 3D editor's own Snap Settings dialog. **Watch out for:** the
  translate snap is not an editor setting but project metadata kept by that dialog (three `EditorSpinSlider`s, not
  line edits), so there is no property to set; the dialog is found by class and its first slider is the translate
  step, which a Godot update can move. **Seen:** gdstudio #788, 2026-11-08 (the plugin set the dialog to 0.5 and the
  project metadata read 0.5).

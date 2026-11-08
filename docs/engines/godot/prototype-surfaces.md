# Prototype surfaces and daylight

How the 3D Blank template's level is painted and lit with no texture or sky file, and what Godot did while we tuned
it (kit issue #773). The level is described in the game's own docs (`docs/design/prototype-level.md` in a game made
from the template); this page is how the engine behaves. Everything here was measured in the Compatibility renderer,
on the desktop and in headless Chromium (SwiftShader) with the web export, and looked the same in both.

## A grid with no texture {#a-grid-with-no-texture}

`templates/3d-blank/game/assets/shaders/prototype/prototype_grid.gdshader` draws the grid in the fragment shader from
the world position, three planes (x, y, z) blended by the normal raised to the eighth power.

| Question | Answer |
| --- | --- |
| Why world space | A `CSGBox3D`'s UVs do not grow with its size, so a texture would stretch whenever a block is resized in the inspector. A world-space cell is 1 m on every face at any scale, and neighbouring blocks line up. |
| Why three planes and a blend | The ramp is a slope: a dominant-axis pick shows a seam where it passes 45 degrees. The blend costs three pattern evaluations a pixel and no texture read ([Surface materials](surface-materials.md) measured the texture-reading triplanar as slower; this one was not measured against it). It is a prototype shader: a level that ships bakes its look into textures. |
| Lines that do not shimmer | `fwidth` of the cell coordinate is the footprint of a pixel; a line fades out where the footprint passes a third of a cell, so a far floor is a calm tone. It is `fwidth` in the fragment stage, so it cannot sit inside a branch. |
| Licence | None needed: no file. The icon is our own SVG. |

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
- **A `CSGPolygon3D` profile** is in the x-y plane, extruded along local -z by `depth`; the stairs' twelve steps are one
  polygon walked clockwise, which Godot builds with outward faces.
- **A flat `Label3D`** reads from the +z side when rotated (-90, 0, 0); (-90, 180, 0) reads from the -z side, the
  side a player standing in the middle of the level looking at the jump blocks sees.
- **Movie Maker is one frame behind `_process`.** The frame written is the state `_process` left on the previous call,
  so a tour that cuts to a new view every N frames sets the first view in `_ready` and chooses each view one frame
  ahead; otherwise frame 0 is the default camera and every cut shows late.
- **The synced `gds_ui` addon's demo does not export without the `UIRouter` autoload.** Import, a run and the tests
  are clean, but `--export-release` loads every script and printed 20 lines of parse errors for the five demo
  scripts; the preset excludes `addons/gds_ui/demo/*`.
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

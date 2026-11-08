# Prototype level

The level in `game/world/prototype/prototype_level.tscn` is a space to build in: a 50 m square floor with four 4 m
walls on the prototype grid, lit by a sun and a sky and by baked bounce light. `game/main.tscn` instances it and looks
at it through one camera.

## What is in it

| Part | Where | What it is for |
| --- | --- | --- |
| Floor and four walls | `Boundary/` | The edge of the space. The floor's top is the ground, `y = 0`. |
| Sun, sky, bounce light | `Daylight`, `LightmapGI` | One real-time sun, a procedural sky and baked bounce light. |
| Graphics profile | `GraphicsProfile` | Forward+ extras, set in the inspector (below). |

## The camera {#camera}

`game/main.tscn` has a `Camera3D` with a `PhantomCameraHost` under it, and a `ViewCamera`, a `PhantomCamera3D` that stands
still and looks at the floor. The host moves the camera to the `PhantomCamera3D` with the highest `priority`: to look
from somewhere else, add another `PhantomCamera3D`, or give this one a follow target and a follow mode (the addon's
docs are at <https://phantom-camera.dev>). The addon is committed in `game/addons/phantom_camera/` with its licence
entry.

## Materials {#materials}

The surfaces use one shader, `game/assets/shaders/prototype/prototype_grid.gdshader`, and a material per colour in
`game/assets/materials/prototype/`. The grid is drawn in world space (a cell is 1 m on a wall, a floor and a ramp, at any
scale), blended by the surface's normal so a slope has no seam, and fades where a pixel can no longer resolve it. There
is no texture file: nothing to license, nothing to import, the same on the web as on the desktop.

| Material | Colour | Use it for |
| --- | --- | --- |
| `prototype_floor` | grey | ground |
| `prototype_wall` | light grey | walls and anything that should recede |
| `prototype_dark` | charcoal | columns, platforms and trim |
| `prototype_orange` | orange | cover and things the player moves or shoots |
| `prototype_blue` | blue | places to reach |
| `prototype_green` | green | slopes and safe ground |
| `prototype_red` | red | hazards and measurements |

A new colour is a copy of one of these with its own `base_color`; the line strengths are shader parameters on the
material. The cell size (`prototype_cell_size`, 1 m) and the heavier line every 8 cells (`prototype_major_every`) are
shader globals in Project Settings > Shader Globals, shared by every material and by the editor's snap step.

## Lighting {#lighting}

The web build runs the Compatibility renderer (WebGL 2) and a desktop runs Forward+; one level serves both
(`rendering_method` is Forward+ with `.web` and `.mobile` overrides to Compatibility).

- **Lit for the web first.** A `ProceduralSkyMaterial` sky, one real-time sun with shadows (set to Dynamic, so its
  bounce is baked and its shadows are not) and a `LightmapGI` bake for soft bounce light, which costs nothing at run
  time.
- **Baking again.** After you move or resize a piece, select `LightmapGI` and press "Bake Lightmaps" (Forward+ editor).
  Only the editor can build a mesh's lightmap UVs, so a piece needs a mesh saved in the scene with UV2.
- **Forward+ extras.** `GraphicsProfile` turns on SSAO, SSIL, SSR, volumetric fog, finer sun shadows and, if you
  choose, SDFGI instead of the baked light, all from the inspector. On the web it does nothing.
- Filmic tonemap, a touch of contrast and saturation, and a thin haze.

## Looking at it

`game/tools/capture/level_tour.tscn` flies a camera through three views; record it for a pull request with
`gds capture frames --project game --scene res://tools/capture/level_tour.tscn --seconds 1.5 --fps 10`.

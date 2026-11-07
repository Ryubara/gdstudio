# Prototype level

The level in `game/world/prototype/prototype_level.tscn` is a space to build in, not a map: a 50 m square floor
with walls, and a few shapes that answer the questions a first prototype asks (how high can I step, how steep is a
ramp, how wide is a door). `game/main.tscn` instances it and looks at it through one camera.

## What is in it

| Part | Where | What it is for |
| --- | --- | --- |
| Floor and four walls | `Boundary/` | The edge of the space: 4 m walls. The floor's top is the ground, `y = 0`. |
| Tower platform and stairs | `Landings/` | A 3 m platform reached by twelve steps (0.25 m rise, 0.45 m run). |
| Ramp and platform | `Landings/` | A 9.5 degree slope up to a 1.5 m platform. |
| Dais | `Landings/` | A low square in the middle: the natural start for a character. |
| Crates and low walls | `Cover/` | 1 m crates, a 2 m crate and 1.2 m walls: cover and climbing practice. |
| Jump blocks | `Steps/` | Blocks of 0.5, 1, 1.5 and 2 m, each labelled with its height. |
| Columns | `Columns/` | Four round pillars: something to walk around and to see shadows on. |
| Divider with a doorway | `Divider/` | A wall with a 2 m by 2.6 m door cut out of it (a subtracted CSG box). |
| Sun and sky | `Daylight` | One shadowed directional light and a procedural sky. |

Everything solid is a `CSGBox3D`, `CSGPolygon3D` or `CSGCylinder3D` with `use_collision` on, so a shape is resized in
the inspector and collides at once. CSG is for prototyping: when a shape is final, replace it with a mesh and a
collision shape.

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

A new colour is a copy of one of these with its own `base_color`; the grid size and line strengths are shader
parameters on the material.

## Lighting {#lighting}

`game/world/lighting/daylight.tscn` is the whole rig, so another map (or a night one) instances a different scene
and nothing else changes. It is set up for the Compatibility renderer:

- A `ProceduralSkyMaterial` sky (no sky file) lights the ambient colour a little and fills the background.
- One directional light with shadows: a single shadowed light is the web build's budget ([Compatibility
  lighting](https://{KIT_PAGES}/godot/compat-lighting/)).
- Filmic tonemap, a touch of contrast and saturation, and a thin haze. SSAO, SSR and volumetric fog are left off:
  the Compatibility renderer ignores them.

## Looking at it

`game/tools/capture/level_tour.tscn` flies a camera through seven views; record it for a pull request with
`gds capture frames --project game --scene res://tools/capture/level_tour.tscn --seconds 3.5 --fps 10`.

# Prototype level

The level in `game/world/prototype/prototype_level.tscn` is a space to build in, and a map that shows what the
components do: a 50 m square floor with walls, shapes that answer a first prototype's questions (how high can I step,
how steep is a ramp, how wide is a door) and a few of each component. `game/world/world.tscn` instances it and
`game/main.tscn` adds [the character](character.md) (at its spawn point, seen through a third-person Phantom Camera),
the HUD and the menus. The shapes are sized for the character's default tuning: the jump blocks are a jump apart, the
twelve steps are lower than its step height and the ramp is gentler than its slope limit.

## What is in it

| Part | Where | What it is for |
| --- | --- | --- |
| Floor and four walls | `Boundary/` | The edge of the space: 5 m walls, over what the character can climb from anything it stands on near them. The floor's top is the ground, `y = 0`. A doorway 4 m wide and 3 m high in the west and the east wall leads to a [map section](map-sections.md). |
| Tower platform and stairs, bridge, ramp | `Landings/` | A 3 m platform reached by twelve steps, two raised blocks and a ramp up to them. |
| A room with a roof opening | `Room/` | A closed room with a doorway and a baked lamp: the lightmap in a dark place. |
| Cover, jump blocks, columns | `Cover/`, `Steps/`, `Columns/` | Crates and low walls, blocks of 0.5 to 2 m, round pillars. |
| Doors, pressure pad | `Doors/`, `Triggers/` | A `Door` that opens when the pad's `TriggerZone` is stepped on, and one that opens when a body comes near. Online the server senses the pad and every screen paints its plate from the server's word (the pad's `NetEntity` child, `trigger_zone_net.tscn`). |
| Moving platform | `Platforms/` | A `MovingPlatform` that carries what stands on it. |
| Pickups | `Pickups/` | `Pickup` coins and gems that spin, say who took them and may come back. |
| Spawn points | `Spawns/` | `SpawnPoint` markers in groups (`player`, `wave`). The character starts at the first `player` one: on the dais, facing into the map. |
| Camera views | `CameraViews/` | A `TriggerZone` by the jump blocks and a fixed Phantom Camera: a `CameraZone` hands the view to it while the character stands in the zone, and back (a blend over the camera's tween). |
| Crouch course | `CrouchCourse/` | A tunnel 1.25 m high with a coin in it, a low ceiling on four posts at 1.3 m (let go of crouch under it and the character stays crouched until it walks out), a 2.4 m wall with a gap under a red bar at 1.2 m and a coin behind it. Each place is lower than the standing capsule (1.8 m) and higher than the crouched one (1.1 m); a test holds that. |
| Range | `Targets/` | Four `Target` boards on posts in front of the bar wall, 15 m north of the dais: aim with the right mouse button and shoot. |
| Push cubes | `PushCubes/` | Four 60 kg cubes with a grip of 0.5 at the south, with 8 m of floor to push them across. A cube is pushed at 1.2 m/s (its `push_speed`), so the push clip plays for as long as the character walks. |
| Props | `Props/` | `PhysicsProp` crates, barrels and two chrome balls (they show the reflection probes). |
| Sun, sky, bounce light | `Daylight`, `LightmapGI`, `Probes/`, `Lamps/` | One real-time sun, a procedural sky, baked bounce light and two reflection probes. |
| Graphics profile | `GraphicsProfile` | Forward+ extras, set in the inspector (below). |

Every solid is a `ProtoBlock`: pick its kind (box, cylinder, ramp, stairs) and its `size` in the inspector and the
mesh and the collision follow. Blocks snap onto the grid when the editor's snap is on (the `prototype_grid` plugin
sets its step to the grid's cell size).

## Materials {#materials}

The surfaces use one shader, `game/assets/shaders/prototype/prototype_grid.gdshader`, and a material per colour in
`game/assets/materials/prototype/`. The grid is drawn in world space (a cell is 1 m on a wall, a floor and a ramp, at
any scale), blended by the surface's normal so a slope has no seam, and fades where a pixel can no longer resolve it.
There is no texture file: nothing to license, nothing to import, the same on the web as on the desktop.

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
  bounce is baked and its shadows are not) and a `LightmapGI` bake for soft bounce light and room light, which cost
  nothing at run time. Two reflection probes (`reflection_size` 64 in the project settings keeps their memory low).
- **Baking again.** After you move or resize a block, select `LightmapGI` and press "Bake Lightmaps" (Forward+ editor),
  or run `game/tools/map_bake/` (its header says how), which bakes the level and both sections. Only the editor can
  build a block's lightmap UVs, so the editor saves each block's mesh in the scene; a running game builds only the
  collision. `tests/world/test_map_lighting.gd` fails on a block left out of the bake.
- **Forward+ extras.** `GraphicsProfile` turns on SSAO, SSIL, SSR, volumetric fog, finer sun shadows and, if you
  choose, SDFGI instead of the baked light, all from the inspector. On the web it does nothing.
- Filmic tonemap, a touch of contrast and saturation, and a thin haze.

## Looking at it

`game/tools/capture/level_tour.tscn` flies a camera through six views; record it for a pull request with
`gds capture frames --project game --scene res://tools/capture/level_tour.tscn --seconds 3.5 --fps 10`.

`game/tools/capture/walkthrough.tscn` plays the character through the map by pressing the input actions (a route of
waypoints over the gate, the jump blocks, the props and the room's door), for a clip:
`gds capture frames --project game --scene res://tools/capture/walkthrough.tscn --seconds 40 --fps 30`.

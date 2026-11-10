# Map sections

Two spaces behind the prototype level's outer wall, each reached through a 4 m wide, 3 m high doorway: an **AI
section** to the west, where enemies and friendlies are introduced and seen or not seen, and a **pathing section** to
the east, a course of routes, heights, gaps, a door and moving obstacles for walking agents. Neither holds any AI: they
are the places an AI is built and tested in, with their spawn points, markers and baked navigation mesh named so a test
can ask for them.

Each section is its own scene, instanced in `game/world/world.tscn`; work on a section changes only its folder:

| Section | Scene | In `world.tscn` |
| --- | --- | --- |
| AI | `game/world/prototype/ai_section/ai_section.tscn` | `AISection`, at (-25, 0, -9) |
| Pathing | `game/world/prototype/pathing_section/pathing_section.tscn` | `PathingSection`, at (25, 0, -6) |

A section's origin is the middle of its doorway on the floor, on the outer face of the map's wall: the AI section lies
toward its -X, the pathing section toward its +X. Each folder also holds the section's lightmap (`.lmbake`, `.exr`)
and its navigation mesh (`*_navmesh.tres`). A section has no sun or sky of its own: the map's light it where it stands.

## The AI section

34 by 30 m inside 5 m walls. The friendly side is by the doorway, the enemy side at the far (west) end behind a screen
of three orange walls 2.2 m high, so an enemy that spawns cannot be seen from the doorway and comes out through the
screen's gaps. Between them, open ground with cover.

| Part | Node | What it is for |
| --- | --- | --- |
| Floor, walls | `Navigation/Boundary/` | The edge; the floor's top is `y = 0`. |
| Screen | `Navigation/Screen/` | Hides the enemy spawns; enemies leave by its gaps and its ends. |
| Cover | `Navigation/Cover/` | Four blue low walls (1 m, cover to crouch behind), an orange tall cover (2.2 m, cover to hide behind), two round columns (3 m). |
| Shed | `Navigation/Shed/` | A red shed with a roof and a 2 m doorway that faces the friendly side: a place to hide. A baked lamp lights it. |
| Window wall | `Navigation/WindowWall/` | A wall with a window between 1 and 2 m: seen through at eye height, never walked through. |
| Enemy spawns | `Spawns/Enemy1` to `Enemy6` | `SpawnPoint`s in the group `enemy`, behind the screen, facing the friendly side (+X). |
| Friendly spawns | `Spawns/Friendly1` to `Friendly4` | `SpawnPoint`s in the group `friendly`, by the doorway, facing in (-X). |
| Perception markers | `Perception/` | `Marker3D`s for sight tests (below). |
| Navigation | `Navigation` | A `NavigationRegion3D`; its children are the mesh's source. |

`SpawnPoint.pick(get_tree(), &"enemy", rng)` picks an enemy spawn; `spawn_transform(rng)` gives the place and the
facing. The perception markers stand on the floor; a test looks from 1.55 m over a watch post (the character's eye):

| Marker | What a test holds |
| --- | --- |
| `WatchNorth`, `WatchMiddle` | where a watcher stands (in the long north lane, and in front of the screen) |
| `SeenInLane` | seen from `WatchNorth`, 18 m down the lane |
| `SeenThroughWindow` | seen from `WatchNorth` through the window |
| `SeenInOpen` | seen from `WatchMiddle`, past the tall cover's end |
| `HiddenInShed` | hidden from both, at the head, chest and knee |
| `HiddenBehindCover` | hidden from both behind the tall cover |
| `HiddenBehindScreen` | hidden from both behind the screen |

The shed's roof is on the walking mesh as a piece of its own that no path reaches: the reach test counts it as a top
the character can get onto (from the column beside it), and an agent cannot.

## The pathing section

40 by 40 m inside 5 m walls, cut in two by a 4 m divider with four ways through it, and a course on the far side.

| Part | Node | What it tests |
| --- | --- | --- |
| Divider | `Navigation/Divider/` | A wide way (4 m), a narrow one (1.5 m), a tight gap (0.9 m: the character fits, the agent does not, so the mesh has no way through) and a doorway. |
| Door | `Doors/Door` | A `Door` that slides aside when a character comes within 2.5 m and closes 1.5 s after. It is not in the mesh's source: the mesh runs through the doorway, the door opens for whoever walks the path. |
| Ramp, stairs, steep ramp | `Navigation/Heights/` | A walkable ramp (14 degrees) and stairs (six steps of 0.25 m) up to a deck 1.5 m high, and a red ramp too steep for the agent (56 degrees). |
| Decks and the gap | `Navigation/Heights/DeckA`, `DeckB`, `GapLink` | Two decks with a 2 m gap; a `NavigationLink3D` joins them both ways, and is the only way onto the far deck. |
| The drop | `DropLink` | A one-way `NavigationLink3D` from the far deck down to the floor. |
| Kerb | `Navigation/Heights/Kerb` | A 0.2 m step up, under the agent's climb. |
| Moving obstacles | `Obstacles/MoverA`, `MoverB` | Two `MovingPlatform` blocks (1.5 m, 2 m high) sweeping 10 m back and forth across the way to the door, each with a `NavigationObstacle3D` (radius 1.1 m) for avoidance. Not in the mesh. |
| Routes | `Routes/<Name>/Start`, `End` | `Marker3D` pairs for path tests (below). |

| Route | Its path |
| --- | --- |
| `Wide`, `Narrow`, `Door` | straight through that way in the divider |
| `Tight` | round the tight gap, by another way (more than 6 m longer than the straight line) |
| `Ramp`, `Stairs` | up the ramp, up the stairs |
| `Steep` | round the steep ramp and up the walkable one |
| `Gap` | across the gap by `GapLink` |
| `Drop` | down by `DropLink`; from its end back to its start, the long way up the ramp and over the gap |
| `Obstacles` | across the two movers' lane |
| `Kerb` | up the kerb |
| `Across` | from the doorway to the far corner |

`tests/world/test_sections.gd` holds each line of these tables; `tests/world/test_section_walks.gd` walks the character
along every route on its path, and to every marker and enemy spawn of the AI section, by pressing the move actions.

## The navigation mesh

Each section's `NavigationRegion3D` bakes from its own children (its `ProtoBlock` colliders), for an agent the size of
the character: radius 0.5 m, height 1.8 m, climb 0.3 m, slope 45 degrees, cells of 0.25 by 0.1 m (the project's
navigation cell height is 0.1 m, `navigation/3d/default_cell_height`). Ledge spans are filtered, so the side of a ramp
is no way up. The baked surface floats about 0.2 m over the floor (the baker lifts it by two cells); ask a path between
points on the floor and compare where it ends on the ground plane.

## Changing a section

Move or add blocks in the section's scene, then bake again: the blocks' meshes (with their lightmap UVs), the
navigation mesh and the lightmap. `game/tools/map_bake/` does all three for the map and both sections the way a
person does in the editor; its header says how to run it. The suites fail on a stale bake: a block whose mesh is not its
size, a block missing from its scene's lightmap, a lightmap with no light in it, a navigation mesh unlike a fresh bake.

The walls are 5 m (the map's too): the character climbs a 1.35 m ledge from the floor and crosses a 3 m gap onto a top
1.35 m higher, so a 3 m platform beside a 4 m wall was a way out. `tests/world/test_map_reach.gd` holds every wall
over what the character can stand on near it, and `tests/world/test_escape_sweep.gd` runs the character at the walls
from everything it can stand on. A new block near a wall has to pass both.

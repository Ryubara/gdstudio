# Map sections

<!-- new section: third-person-template.md is at its size limit, and nothing held how a map grows by sections or how a
     section's navigation, light and reach are proved -->

Kit #885 added two spaces behind the prototype map's outer wall, each its own scene so that later AI work changes only
its folder: an AI section (enemies and friendlies, cover, places to hide, lines of sight) and a pathing section (a
baked navigation mesh and a course of ways, heights, links, a door and moving obstacles). Neither has AI in it. The
game's `docs/design/map-sections.md` lists every node, spawn group, marker and route by name, with what a test holds
for each; this page is how they are built and proved, for any GDStudio map that grows the same way.

| What | How it is done | Why |
| --- | --- | --- |
| A section | A `Node3D` scene whose origin is the middle of its doorway on the floor, on the map wall's outer face; `world/world.tscn` instances it there. The map's wall gets the opening (two pieces and a lintel). | The map scene does not change when a section does, and a section is placed by its doorway. |
| Its light | Its own `LightmapGI` with the map's settings, no sun or sky of its own: the map's sun lights it where it stands, and `tools/map_bake/` adds the map's daylight for the length of the bake. | One look across the doorway; a second sun would light it twice. |
| Its navigation | A `NavigationRegion3D` whose children are the mesh's source (static colliders), its mesh in its own `.tres`, baked with the section's scene alone at the origin. A door, the movers and the markers are outside the region. | The mesh runs through a door that opens for whoever walks the path; obstacles that move stay out of a baked mesh. |
| Agent size | Radius 0.5 m, height 1.8 m, climb 0.3 m, slope 45 degrees, cells 0.25 by 0.1 m (`navigation/3d/default_cell_height = 0.1` in the project), ledge spans filtered. | The agent goes where the character goes, and a stair of 0.25 m steps stays on the mesh. |
| Proof | `test_sections.gd` (doorways a body fits through, closed walls, spawns, sight lines, routes, a fresh bake equal to the saved one), `test_section_walks.gd` (the character walks every route on its path), `test_map_lighting.gd`, `test_map_reach.gd`, `test_escape_sweep.gd`, `test_jump_reach.gd`. | A space is proved by the real body and by numbers, not by its look. |

Measured (Godot 4.7.2): the character climbs 1.35 m from the floor (its jump is 1.25 m) and sprint-jumps a 3 m gap onto
a top 1.35 m higher, 4.5 m onto one 1 m higher and 5.75 m onto one at its own height (`ReachBench`, pinned); the walls
were raised from 4 to 5 m for it. The section bakes take about 1 s each; the lightmaps are a 256 x 256 and a 256 x 512
atlas (109 and 123 KB EXR), the navigation meshes 135 and 106 polygons. In Compatibility (RTX 5080, vsync off,
1600 x 900, 300 frames) the view from the start draws 124 calls against 106 without the sections (0.36 against 0.34 ms
CPU, 0.21 against 0.20 ms GPU, 0.5 MB more texture memory); inside the AI section 58 calls, inside the pathing
section 43. The only parts that move are the pathing section's door and its two movers, stepped in the physics tick.

## What the bakes and the walk found {#what-the-bakes-found}

<!-- new section: the entries of the page's first task, kept apart from its how-to -->

- **Approach:** Bake a section's navigation mesh in the section's own scene, at the origin, and compare a test's fresh
  bake made the same way. **Watch out for:** the bake's cells lie on the world's grid, so the same pathing section
  baked 77 polygons at the origin and 81 where `main.tscn` puts it, and a test that baked it in place called the saved
  mesh stale. **Seen:** gdstudio #885, 2026-11-10.
- **Approach:** Give the navigation map a cell height a stair's step is a whole number of (0.1 m), set the agent to the
  character's numbers and filter ledge spans, and make a stair's run at least two cells deep (0.5 m). **Watch out
  for:** with 0.25 m cells the surface floated 0.5 m over the floor, so a shed doorway under a 2.2 m lintel was shut to
  a 2 m agent; without the ledge filter a path climbed the side of a ramp where the body met a 0.44 m edge and stopped;
  with it, stairs of 0.4 m steps left the mesh (a cell between a lower and a higher step reads as a ledge). **Seen:**
  gdstudio #885, 2026-11-10 (`test_section_walks.gd` found the first two, `test_sections.gd` the third).
- **Approach:** Walk the real character along each path the mesh gives, by pressing the move actions, and jump where a
  link's stretch begins and the floor ends ahead (`RouteWalker`). **Watch out for:** a path query marks only a link's
  first point as the link's (`path_types` of `[0, 1, 0, 0]` across a gap), so a walker that waited for two marked
  points never jumped and fell into the gap. **Seen:** gdstudio #885, 2026-11-10.

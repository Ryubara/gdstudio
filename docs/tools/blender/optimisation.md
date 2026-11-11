# Optimisation

<!-- new section: triangle budgets and levels of detail were only in the weapons and variants pages and Deadnight's style
bible; nothing gave the budget per asset class or how decimation and LOD are done and checked -->

How GDStudio keeps assets light enough for a web build on a phone: a triangle budget per asset class that the build
script enforces, collapse decimation for heavy sources, a far level of detail where an asset is seen from afar, and few
meshes per object. Godot's side (draw calls, visibility ranges, merging at run time) is on
[Performance budgets](../../engines/godot/performance-budgets.md), [Crowds](../../engines/godot/crowds.md) and
[Merging meshes at run time](../../engines/godot/merging-meshes-at-runtime.md).

## Triangle budgets {#budgets}

The budgets Deadnight proposed for the web and built to (its style bible), near level and far level:

| Class | Near | Far | Built |
| --- | --- | --- | --- |
| Player character | 6,000, one material | 2,000 | presets 4,490 to 5,080 near, 1,407 to 1,787 far |
| Enemy (zombie) | 4,000 | 1,500 | 3,999 to 4,000 and 1,500 |
| Boss | 8,000 | 3,000 | 8,314 |
| First-person weapon | 3,000 | | |
| Held or world weapon | 1,500 | 500 | guns 524 to 1,236 near, 260 to 428 far; melee 432 to 920, 108 to 218 |
| Prop under 1 m | 800 | 300 | |
| Prop of 1 to 3 m | 1,500 | 500 | |
| Prop over 3 m, building | 5,000 | 1,500 | the broken car decimated to 2,327 |
| Kit piece (wall, opening) | 1,500 | | 108 to 992; stairs 1,308 to 1,612 |
| Vehicle | 1,500 (the helicopter's build) | | 1,264 |
| Backdrop repeat | | 300 | an `.obj` for a MultiMesh ([Modular kits](modular-kits.md)) |

A game copies this table into its style bible and changes it there. Count triangles after triangulating and dropping
zero-area faces, and make the build fail over budget before it exports ([Build scripts](build-scripts.md#checks)).
Hidden meshes count too: a soldier of 136 meshes with most hidden was made 11 to 15 ([Variants](variants.md#modular-parts)).

## Decimation {#decimation}

A heavy source (a kit prop over budget, a sculpt) is brought down with Blender's collapse Decimate modifier, applied,
to a ratio solved from the target (`ratio = target * 0.97 / triangles`, `use_collapse_triangulate=True`): the Quaternius
tires went from 1,776 to under 1,500 and the zombie from 7,822 to 4,000 and 1,500 with every palette cell kept in place
([Variants](variants.md)). Collapse keeps a closed mesh closed, its UVs on their cells and its silhouette, as long as
the mesh is welded.

- **Approach:** Weld a mesh imported from glTF (merge by distance, about 0.1 mm) before decimating it or computing
  anything from its topology, and check the result for open edges. **Watch out for:** glTF splits a vertex at every
  hard edge and UV seam, so a flat-shaded import is a heap of separate triangles: a collapse Decimate of one tore it
  into 2,228 open edges and a shape 14% of its size off the original. **Seen:** gdstudio #774, 2026-11-07 (fix: the
  eval's boulder is smooth-shaded, the checks weld before measuring, and the `decimate-boulder` eval counts open edges).

- **Approach:** After a collapse Decimate of a static prop, snap the vertices of its flat bottom back to the floor,
  then remove folds near the far level's budget with a few edge flips and vertex nudges toward the source while the
  outermost vertices stay locked; shade it smooth with only the bottom's edge hard. **Watch out for:** collapse shrank
  the bounds 0.63% and kept 54% of the flat bottom's area at 500 triangles, left small faces turned away from the
  source, and a pass that pulled every vertex in pushed the bounds past 1%; sharp edges split by angle (45 degrees)
  cut a noisy rock into dark wedges. **Seen:** gdstudio #774, 2026-11-07 (the `decimate-boulder` baseline run).

Measure a decimated mesh against its source, not by eye: the mean and largest distance between the two surfaces over
the bounding-box diagonal, the bounds, the lowest vertex (a flat bottom stays on the floor) and the area that ended up
facing the wrong way.

## Levels of detail {#lod}

Where an asset is seen from afar, build a far level from the same script: a decimated copy for organic shapes (the
soldier's parts at one solved ratio, 0.284, parts of 260 triangles or fewer kept whole and none below 0.2), or the same
parts with no chamfers, half the sides and the detail parts dropped for hard surfaces, at 24 to 50% of the near count
([Variants](variants.md#modular-parts), [Weapons](weapons.md)). Godot switches levels with visibility ranges (18 m for
Deadnight's zombies, both levels on one skeleton); its import option `meshes/generate_lods` covers static props and map
pieces, and it makes no levels for skinned meshes ([Crowds](../../engines/godot/crowds.md)).

- **Approach:** Turn `meshes/generate_lods` off for a kitbashed hard-surface model (a weapon of separate closed parts)
  and give it the far level built from the same description, swapped by each mesh's visibility range; look at the
  model at 4, 8, 15 and 30 m through the game's field of view before trusting the importer's levels. **Watch out for:**
  Godot's levels for the template rifle (1,112 triangles to 456 and 88) dropped the hand guard at 15 m and pieces of
  the receiver at 30 m, and the lowest level kept only the barrel, the magazine and the stock; the far level (420
  triangles) kept the outline at every distance; the pistol's levels (692 triangles) changed nothing visible there.
  **Seen:** gdstudio #886, 2026-11-10 (fix: `generate_lods=false` and `rifle.tscn`, near to 10 m and far after it).
- **Approach:** Give the levels' visibility ranges no margins (each level's end is the next one's begin), and look
  at the model in a real render at the distance the game's camera stands. **Watch out for:** with a begin and end
  margin, a body that starts inside the band between two levels is drawn at neither: bodies at 8.7 m, with the
  levels meeting at 9 m and margins of 0.75 m, were invisible while every headless test passed. **Seen:** gdstudio
  #1149 (PR #1172), 2026-11-11 (fix: no margins, and a test asserts it).

## Fewer meshes {#merging}

Each mesh is a draw call. Join what is always drawn together (the zombie's eyelids into its body: a second mesh cost
30% of the browser's frame at 80 zombies) and keep one material per asset family on its atlas, so Godot can merge a
family's props into one mesh at run time ([Merging meshes](../../engines/godot/merging-meshes-at-runtime.md)).

## The decimation eval {#eval}

The `decimate-boulder` eval ([Agent evals](../../studio/agent-evals.md)) turns a 20,480-triangle sculpt into a near and
a far level and measures the budgets, the surface distances, the bounds, the flat bottom, open edges and flipped area.

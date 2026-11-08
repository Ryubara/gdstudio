# Modelling

<!-- new section: the Blender pages covered weapons, kit pieces and variants one asset class at a time; nothing held the
modelling rules every asset shares (scale, bevels, origins, normals, measuring the style) -->

How GDStudio builds a low-poly model in Blender by script: the scale it works at, the bevel it uses, where the origin
goes and how its faces are checked, so a new asset sits beside the CC0 kits a game uses and imports into Godot without
surprises. The asset classes have their own pages ([weapons](weapons.md), [kit pieces and props](modular-kits.md),
[character variants](variants.md)); the triangle budgets are on [Optimisation](optimisation.md).

## Measure the style first {#measure-the-style}

Before making anything, measure the kit it sits beside and write the numbers in the game's style bible, so the next
asset follows numbers instead of an impression. Deadnight's style bible (`docs/design/style.md` in Deadnight) holds what
was measured on the Quaternius Toon Shooter kit: characters about 3 heads tall (2.8 to 3.3), the head 36% of the
height, hips at 38 to 43%; one-segment chamfers of 15 to 25 mm on characters and weapons; flat atlas colour. The arm is
measured as on [Variants](variants.md#proportions-measure-the-arm).

Measure with a script that prints numbers (triangles, bounds, bevel widths, the palette cells used) and a contact sheet
rendered at the same scale as a kit reference ([Key art](key-art.md#files) has the render setup). A number nobody wrote
down is measured again by the next agent; Deadnight's `measure_kit.py` and `render_sheet.py` are the scripts to start
from (the commands are at the end of its style bible).

## Scale and units {#scale}

One Blender unit is one metre, and a model is built at its size in the game, with its object transform applied (scale
1, rotation 0) before export. Third-party kits do not follow this: the Quaternius characters import at about 2.2 m and
are scaled 0.8 in Godot; the raw files carry a scale of 100 on the armature ([Rig sharing](rig-sharing.md)). Build an
original asset at the game's size rather than the kit file's, and stage it beside a game character to judge it
([Modular kits](modular-kits.md)).

## Bevels {#bevels}

The soft look of the kits comes from chunky shapes and one-segment chamfers, not from smoothing or subdivision. Use one
segment: 15 to 25 mm on characters and held weapons, about 30 mm on props of 1 to 3 m, 60 to 100 mm on buildings and
big pieces. Chamfer only what is big and seen: a chamfered box costs 44 triangles against 12, and a 12-sided cylinder 92
against 44 ([Build scripts](build-scripts.md#checks)). Chamfer only the edges that turn (`calc_face_angle() > 0.05`), so
an outline that is already flat is not cut ([Modular kits](modular-kits.md)).

## Kitbashing {#kitbashing}

Build a hard-surface asset from closed parts that overlap, never welded together: Deadnight's weapons are 8 to 49 parts
each, round parts 8 to 16-sided cylinders, and a weapon is drawn at real size and then fattened 1.4 to 1.5 times across
so it reads from a shoulder camera ([Weapons](weapons.md)). Overlapping closed parts cost no extra triangles and keep
every part's normals simple. A measuring script that welds coincident vertices (to undo the splits glTF makes, below)
also joins parts that touch, so it counts an edge shared by two parts as more than two faces: that is not a fault in a
kitbashed model.

## Building with bmesh {#bmesh}

Build scripts make geometry with `bmesh.ops`, which do less than the operators of the same name in the interface: they
return the new geometry and leave the old in place.

- **Approach:** After `bmesh.ops.extrude_face_region`, delete the original faces yourself
  (`bmesh.ops.delete(bm, geom=faces, context="FACES_ONLY")`), give `bmesh.ops.inset_individual` and `inset_region`
  `use_even_offset=True`, and count open and over-shared edges in the build before export. **Watch out for:** the
  extrude keeps the face it extruded, so every recess of a crate's panels left three faces on each rim edge (32 bad
  edges), and an inset of 0.1 m without even offset came out at about 0.071 m. **Seen:** gdstudio #774, 2026-11-07
  (fix: the `model-crate` baseline run's second build; the eval counts open edges).

## Origins and axes {#origins}

The origin is where the game holds or places the asset: a gun at its grip, a melee weapon near the handle's end, a prop
at the middle of its footprint on the ground, a vehicle on the ground under its centre. A weapon's muzzle points along
-X with +Z up ([Weapons](weapons.md#axes-origin-and-the-hold)). Blender's axes become Godot's as (x, y, z) to
(x, z, -y), so an empty's +Y points along Godot's -Z ([Export](export.md#axes)).

## Normals and faces {#normals}

Every model is flat-shaded (`use_smooth = False` on every face), which is what the kit does and what keeps glTF from
blending normals across a chamfer. Check that each closed part faces out by its signed volume in Blender, not by
looking at Godot's triangles (Godot winds them the other way). A mirrored piece is its own mesh: Godot's physics refuses
a negative scale ([Modular kits](modular-kits.md#building-props)).

Orient the faces a script makes yourself: `holes_fill` and `recalc_face_normals` have turned thin parts inside out,
and a review render without backface culling hides it ([Variants](variants.md#closed-and-fitting-in-every-combination)).

## The model eval {#eval}

The `model-crate` eval ([Agent evals](../../studio/agent-evals.md)) measures these rules on one prop: size, origin,
applied transform, open edges, inside-out parts, a shape that is more than a box, a triangle budget and a script that
rebuilds it.

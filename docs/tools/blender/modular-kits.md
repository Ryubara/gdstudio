# Modular kits

How to plan and block out a modular building kit (walls, openings, stairs, props) for a third-person GDStudio game,
learned on Deadnight's second map (Deadnight #623, `docs/research/maps/small-map-art.md` there).

## Planning the kit

- **Measure the reference against the player.** In a level first-person screenshot the horizon is the eye's height,
  so a thing on the far wall is (its pixels above the floor line) / (the eye's pixels above it) x the eye height.
  Cross-check with a stair's riser count. Write estimates as ranges: screenshots are not plans.
- **Model only what has a shape.** Plain walls, floors and ceilings are boxes with a world-space pattern shader
  (Deadnight's lot shader). The kit is the openings, frames, pillars, stairs, broken pieces and props. That keeps the
  parts list to what needs Blender, and a box can be cut per room for the Compatibility renderer's light cap.
- **Grow the existing atlas, do not start a new one.** Put new swatches in the empty cells of the game's palette grid:
  every older prop's UVs stay valid and one texture serves both.
- **Check the kit's sizes against the design's targets first.** A map built to a formula page (areas, ceiling,
  camera passages) can overrule the sizes read off reference images: Deadnight's second map took a 3.4 m storey
  and 2.0 m doors and stairs from its formula over the kit's 3.0 m and 1.4 m.
- **List coverage per part**: exists, a material on a box, a model, or an engine job (light cards, shaders). Group
  the models so the groups share only the palette module, and agents can build them in parallel.

## Sizing openings for a shoulder camera

- A camera whose shoulder offset is swept sideways (it slides in behind the player at a wall) fits doorways far
  narrower than the "two shoulder offsets plus air" rule that open ground needs. Deadnight's 1.4 m doorway works with
  a 0.6 m offset. Prove it with camera probes in every doorway and on every stair.
- A low ceiling shortens the arm when the player looks down: the lens rises by arm x sin(pitch). With a pivot at
  1.6 m, an arm of 2.3 m and a 0.25 m lens margin, a 2.8 m ceiling starts to cut in at about 24 degrees down.
- A sill under the jump height needs a player-only blocker in the opening that is always there, even when the boards
  are down.
- Stairs walk on one hidden ramp: fifteen step-ups bob the view ([below](#stairs-rails-and-blockers)).

## Building the pieces

Learned on Deadnight's walls, openings and floors (Deadnight #633, `tools/blender/build_smallmap_walls.py` there).

- **A wall with an opening is one outline, not boxes.** Butted boxes each chamfered leave a V-groove at every joint.
  Fill the face's outline and holes with `bmesh.ops.triangle_fill(edges=<outer loop and hole loops>)` (it honours
  holes), push it through with `extrude_face_region`, then chamfer only the edges whose faces meet at an angle
  (`e.calc_face_angle() > 0.05`). The seams inside the face stay flat. A segmental arch is the same outline with its
  facets in it; a broken wall is a ragged outline and a ragged hole.
- **Keep the clear opening exact.** Cut the masonry hole as the clear size plus the frame's lining on each side, so a
  1.4 x 2.4 m doorway measures 1.4 x 2.4 m between the linings, and test it against the fixture's collision.
- **Colour the broken faces apart.** After the merge, set the swatch of the faces in the wall's plane that are not its
  module ends (a function of the face's centre and normal): the reveal of a hole reads as the wall's core.
- **Collision that some things pass.** When the navigation is baked from CSG only, an opening the dead use but
  players must not (a window with its sill under the jump height) gets a StaticBody3D on a player-only layer; an
  opening nobody walks but shots cross (bars, a hole) gets CSG on that layer.
- **Write the palette's sRGB values into the image.** A byte image's `pixels` are what the PNG stores; converting to
  linear first saves every swatch far too dark ([lesson](../../lessons/2026-11-02-a-palette-written-as-linear-came-out-dark.md)).
  Read a cell of the saved PNG back once.
- **Keep `.bin` out of the text hooks.** A small glTF buffer can pass as text, and the end-of-file fixer appends a
  byte to it ([lesson](../../lessons/2026-11-03-the-end-of-file-hook-appended-a-newline-to-a-gltf-buffer.md)).
- **Prove it twice:** a Workbench sheet of the exported files beside the game's characters, and a Godot capture of a
  room built from the fixtures under the game's own night environment, the characters at the game's scales.

## Stairs, rails and blockers

Learned on Deadnight's stairs (Deadnight #634, `tools/blender/build_kit_stairs.py` there):

- **One ramp per flight, through the treads' middles.** The top of a hidden box runs at R/2 + u R/T (u from the first
  riser), from half a tread before the first riser to the top level half a tread past the last, then a flat strip to
  the top edge. Through the nosings instead, the body floats a riser over the treads' backs; through the backs, its
  feet sink into the nosings. The 0.1 m either way is under the capsule's round foot.
- **Seams are where a step hides.** A landing's box starts where the lower ramp reaches its height, and the upper ramp
  starts half a tread into the landing; a box that starts at the landing's drawn edge is a 0.1 m ledge over the ramp,
  and the player's step-up fires on it. Walk the corner diagonally in the test as well as the middle.
- **Write the collision from the build script.** The script that makes the mesh writes the fixture scene's CSG boxes
  from the same numbers, so a tread change moves the ramp too. Godot's `Transform3D(...)` in a `.tscn` lists the
  basis by rows; check the convention with a ray down onto each tread.
- **Test with the real body:** walk up and down, at a run, a sprint and across corners; assert no tick with a step-up
  and none off the floor, bound the dip at a slope's crest (the capsule settles 4-8 mm there,
  [lesson](../../lessons/2026-11-02-a-stair-walk-test-failed-on-the-ramps-crest.md)), and keep a control flight with
  its treads as collision that does step.
- **Rails are player-only collision** (Deadnight's boards' layer): a thin pipe stops a player but not a shot or the
  shoulder camera. A rail that may sit on either side of a straight flight is two nodes and a switch on the fixture.
- **A mirrored piece is its own model.** Godot's physics does not take a negative scale, so a right-turning L stair is
  built mirrored in Blender (the normals recalculated), never placed with scale x = -1.
- **A blocker that comes away in pieces** is one node per piece named in the order they go (`Part1_...`), each with
  its origin at its own middle so it can be moved on its own, over one collision box for the whole opening.

## Building props

Learned on Deadnight's cover and clutter (Deadnight #635, `tools/blender/build_smallmap_props.py` there).

- **Sandbags are full pillows that sag onto each other.** Make each bag taller than its course (0.22 m on 0.17 m) and
  gather its ends sideways only. Thin bags pinched in both directions, with a gap between courses, read as stacked
  logs ([lesson](../../lessons/2026-11-02-sandbags-read-as-logs.md)). Alternate header courses (bags across) with
  stretcher courses, and keep a 2 m line near 1.3k triangles.
- **Write the fixtures from the build script.** Give each piece a collision spec in Blender metres (its bounding box,
  boxes, or a cone) and write the `.tscn` with Blender (x, y, z) as Godot (x, z, -y). Walk-over dressing under the
  step height gets none, as a game's papers and debris. A rerun then keeps model and collision together.
- **Each group's test reads its own build report.** Kit groups share the asset and fixture folders, so a test lists
  its pieces from its report's keys, never from the folder's files
  ([lesson](../../lessons/2026-11-03-a-kit-test-claimed-every-file-in-a-shared-folder.md)).
- **Mark where a game node goes later.** A cabinet that holds a wall buy carries a `Marker3D` turned so the game's
  existing plaque node, put under it unchanged, stands on end in the recess. Test that the plaque's box sits inside
  the model.
- **Check normals in Blender, not from Godot's triangles.** Godot's front faces wind clockwise, so a cross product of
  an index triangle points inward on a correct mesh. Sum the signed volume per island of the exported file in Blender
  instead ([lesson](../../lessons/2026-11-02-a-normal-check-on-godot-triangles-flagged-every-face.md)).
- **Tune colours only once the palette reads right.** Read a cell of the saved PNG back before changing a swatch for
  looking dark ([the palette lesson](../../lessons/2026-11-02-a-palette-written-as-linear-came-out-dark.md)).
- **Show an encoding fix before and after from the same cameras.** A fixed atlas changes a look that may have been
  approved dark: capture the night with the old atlas put back and imported, then the new one, from a seeded tour
  (old file: `git show <rev>:<path> | git lfs smudge`,
  [lesson](../../lessons/2026-11-01-git-show-of-an-lfs-file-gives-a-pointer-not-the-model.md)). On Deadnight's drive-in
  (#651) 0-5 % of each lot view changed and up to 24 % of a close prop view; under the night's lights nothing read
  washed out, so no swatch was tuned.

## Roof and outside

Learned on Deadnight's roof and backdrop (Deadnight #638, `tools/blender/build_smallmap_outside.py` there).

- **A roof in bays along the ridge** sits on the walls as wall modules do: the origin on the wall tops, the rafters'
  undersides resting on the wall plates (lift the rafters' plane by the plate's height plus the rafter depth over the
  pitch's cosine). Boards at a bay's end lap 20 mm into the next, or the sky shows through every joint
  ([lesson](../../lessons/2026-11-03-modular-roof-bays-showed-the-sky-through-their-joints.md)).
- **A broken bay** is the courses with a rectangle left out, short boards of different lengths into the hole, battens
  across it and a snapped rafter hanging; seen from below it reads at once.
- **What the backdrop repeats gets a far level of detail** of 300 triangles or fewer (four-sided limbs, no caps, no
  barbs) and an `.obj` copy for a MultiMesh. A wire is a run of three-sided tubes along a parabola; its span is its own
  piece, from one pole's insulators to the next's.
- The backdrop itself (haze, unshaded, multimeshes, cost) is on
  [Compatibility lighting](../../engines/godot/compat-lighting.md#a-backdrop-past-the-playable-bounds).

## Staging game characters for scale

The scale sheet and room render put the game's own characters beside the pieces. Two traps in Blender 5:

- **An action plays only through a slot.** Setting `animation_data.action` leaves the clip the import chose (often
  the file's first, a Crawl) playing. Set `animation_data.action_slot = action.slots[0]` too, then `frame_set` the
  action's first frame, before measuring a height.
- **glTF roots import in quaternion mode.** `rotation_euler` is ignored there. Turn and place a root through
  `matrix_world = Translation @ Rotation @ matrix_world`, or set `rotation_mode = "XYZ"` first.

Look at every render before believing it: both traps produced a plausible image with the wrong pose or facing
([lesson](../../lessons/2026-11-02-an-imported-character-kept-its-import-pose-and-facing.md)).

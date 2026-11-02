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
- Stairs walk on one hidden ramp: fifteen step-ups bob the view.

## Staging game characters for scale

The scale sheet and room render put the game's own characters beside the pieces. Two traps in Blender 5:

- **An action plays only through a slot.** Setting `animation_data.action` leaves the clip the import chose (often
  the file's first, a Crawl) playing. Set `animation_data.action_slot = action.slots[0]` too, then `frame_set` the
  action's first frame, before measuring a height.
- **glTF roots import in quaternion mode.** `rotation_euler` is ignored there. Turn and place a root through
  `matrix_world = Translation @ Rotation @ matrix_world`, or set `rotation_mode = "XYZ"` first.

Look at every render before believing it: both traps produced a plausible image with the wrong pose or facing
([lesson](../lessons/2026-11-02-an-imported-character-kept-its-import-pose-and-facing.md)).

# Measuring an effect on the screen

An effect the player must read (a muzzle flash, a hit marker, a pickup glint, a warning) is judged by what it does to
the pixels the player sees, from the player's camera, in the renderer the player plays in: not by its parameters and
not by a close-up capture of the effect on its own (Deadnight #408, [lesson](../../lessons/2026-11-02-a-flash-in-the-guns-plane-was-hidden-by-the-gun.md)).

## Method {#method}

- To measure what an effect does to the picture, in the renderer in use: after the frame is drawn
  (`RenderingServer.frame_post_draw`), read the viewport (`get_texture().get_image()`), hide the effect, call
  `RenderingServer.force_draw(false)`, read again, and compare. Each `force_draw` ends in `frame_post_draw` again: guard
  with a flag. Restore, and draw once more so Movie Maker's file is the frame with the effect. Works windowed and in the
  web build (WebGL2); a headless run draws nothing.
- `Camera3D.unproject_position` answers in the window's stretch units (1920 by 1080 here), the image is in real pixels
  (`--resolution 1280x720`): scale by image size over `get_visible_rect().size`.
- A node's `physics_interpolation_mode` and `get_global_transform_interpolated()`: for something placed by hand every
  drawn frame, switch interpolation off and add the offset of the parent's interpolated origin.
- The Compatibility renderer lights a mesh from the first lights it finds up to the cap of 8, and a light below a surface
  lights none of that surface: place a flash light above the floor.
- Measured in headless Chrome on an RTX 5080 (ANGLE, Direct3D 11), Godot 4.7.2.

- **Approach:** A capture or plan view restores only the nodes it hid itself (it keeps the list), and a scene that
  hides parts on purpose is checked in the player's view, not by a probe of the tree alone. **Watch out for:** a
  plan-view script set every `VisualInstance3D` and CSG shape visible again when it was done, undoing what the level
  hides on purpose: a hidden collision box drew over the kit's pillar and stair rails the scene had switched off came
  back, while `is_visible_in_tree()` said false. **Seen:** Deadnight, 2026-11-03 (fix: restore only what the capture
  hid; the second map's views were taken again).

- **Approach:** Measure a readable effect on the screen before and after (draw the frame again without it), from the
  real camera, hip and aimed, desktop and browser, hold the numbers as floors in a test, and turn quads near the
  player's own mesh toward the camera. **Watch out for:** an effect is judged by its pixels from the player's camera,
  not its parameters: the muzzle flash covered 0.02 to 0.14 % of the screen for 2 frames, its quads lay in the muzzle's
  plane so the gun, hand and arm hid 25 to 87 % of them, and its light went under the floor when the gun pointed down.
  **Seen:** Deadnight #408, 2026-11-01 (fix: deadnight #448
  ([lesson](../../lessons/2026-11-02-a-flash-in-the-guns-plane-was-hidden-by-the-gun.md))).

## A held weapon from the shoulder camera

The same method answers "does the player see this action at all": hide the weapon (and whatever the hands carry),
draw again, and count the pixels that change (above 0.08 in any channel, every other pixel in both directions, times
four). From a shoulder camera 0.6 m right and 2.3 m behind a chibi Soldier, a gun held at the hip is behind his head:
Deadnight's tommy gun showed 284 pixels of 2.07 million at rest and **0** during the reload that tilted it 35 degrees
down (#383), the rifle about 300 throughout. A reload carried out to the right of the head and up showed 6,700 to
8,700 for the long guns and 2,700 to 3,700 for the pistols (Deadnight #683,
[lesson](../../lessons/2026-11-02-a-reload-tilt-was-hidden-behind-the-head.md)). So for any action on a held item:

- measure it from the camera the player has, at rest and in the middle of the action, and keep the numbers as floors;
- expect the space in front of the chest to be the head's, and move what must read to the right of the head (the
  camera's side) or above it; turn the chest (left shoulder forward) so the short left arm still reaches;
- a test of the pose (an angle, a distance) is not a test of what is seen: the #383 tilt passed its pitch test and
  was invisible.

Deadnight's capture: `game/tests/captures/reload_sheet.tscn --measure`.

## A reveal from where the player stands

A prop that shows the player something (a prize, a pickup, a sign that changes) is read from the spot where its use
prompt appears, through the player's resting camera with the player's own body in the frame, not from a capture placed
to show the whole prop (Deadnight #830, [lesson](../../lessons/2026-11-03-a-prize-reveal-was-filmed-from-a-spot-no-player-stands-on.md)).
Deadnight's prize crane floated its prize 3.25 m up, turning: from the marker (0.8 m from the glass, camera 2.3 m
behind and 0.6 m right of a 1.4 m Soldier, level, FOV 60) it was at the frame's top edge and end on half the time,
while the Soldier's head covers the machine's middle below about 1.65 m. The prize now slides out at 1.72 to 2.18 m,
side on: whole on screen, 14 to 24 % of a 1920-pixel width, 0 % behind the body; at grab height (1.35 m) 79 to 98 % of
it was behind the head.

To hold it in a headless test:

- project into a `SubViewport` sized like the screen (a headless root viewport is 1920 x 1920) with a `Camera3D` that
  copies the player camera's global transform and FOV; `unproject_position` needs no drawing;
- make the body a box round the head bone (Deadnight's Soldier: the hair's top 0.36 m over `Head`, 0.7 m across), not
  the skinned meshes' boxes, which in a test that never animates are the rest pose's;
- place the camera rig at rest twice after turning it (the first placement kept the old transform), and run the test
  once with the bad layout to see it fail.

Deadnight's checks: `game/tests/night/test_crane_view.gd`; the screenshots, `game/tests/captures/crane_prize_view.tscn`.

## A soft rim, and which node it is

An additive wall (a beam, a cone of haze, a shaft) reads as a solid object when its edge is a hard step. Whether it does
is measured, not judged by eye (Deadnight #854):

- Draw the view with the column shown, then hidden, in a frozen frame: `get_tree().paused = true` with the capture node
  on `PROCESS_MODE_ALWAYS`, the player's body hidden in both (its own edges are not the column's), and read both
  pictures. Hide the column with `layers = 0`, not `visible`: an owner that sets `visible` itself every frame (the
  prize crane's beam) puts it back between two reads.
- On each row the column spans, count the pixels the added brightness takes to rise from 10 % to 90 % of that row's
  brightest, from each edge, as a share of the row's width; the median over rows is the rim's softness. Deadnight's
  prize crane beam was 0.00 from 2 to 8 m (a hard step: the pale column), its pendant haze cones 0.08 to 0.39 from 1 to
  4 m, the beam after a fade by the surface's facing to the eye (`pow(abs(dot(NORMAL, VIEW)), 2)`) and a 2.5 m near
  fade 0.23 to 0.34 from 2 to 4 m (a hard edge reads under 0.04, a soft fade 0.2 or more). Read bytes (`Image.get_data()`)
  and sample every fourth row: `get_pixel` over 2 million pixels takes minutes.
- To learn which node draws a thing in a report's picture, hide the named node in the same view and look at whether the
  thing goes, or hide every node on the shader one at a time and count the pixels that change in its region. The
  issue's "haze cones" were warm and soft; the pale shell was another node's.

Deadnight's capture: `game/tests/captures/smallmap_haze_cones.tscn`, its measure and a synthetic test of it:
`game/tests/world/test_haze_rims.gd`.

# Measuring an effect on the screen

An effect the player must read (a muzzle flash, a hit marker, a pickup glint, a warning) is judged by what it does to
the pixels the player sees, from the player's camera, in the renderer the player plays in: not by its parameters and
not by a close-up capture of the effect on its own (Deadnight #408, [lesson](../lessons/2026-11-02-a-flash-in-the-guns-plane-was-hidden-by-the-gun.md)).

## Method

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

## A held weapon from the shoulder camera

The same method answers "does the player see this action at all": hide the weapon (and whatever the hands carry),
draw again, and count the pixels that change (above 0.08 in any channel, every other pixel in both directions, times
four). From a shoulder camera 0.6 m right and 2.3 m behind a chibi Soldier, a gun held at the hip is behind his head:
Deadnight's tommy gun showed 284 pixels of 2.07 million at rest and **0** during the reload that tilted it 35 degrees
down (#383), the rifle about 300 throughout. A reload carried out to the right of the head and up showed 6,700 to
8,700 for the long guns and 2,700 to 3,700 for the pistols (Deadnight #683,
[lesson](../lessons/2026-11-02-a-reload-tilt-was-hidden-behind-the-head.md)). So for any action on a held item:

- measure it from the camera the player has, at rest and in the middle of the action, and keep the numbers as floors;
- expect the space in front of the chest to be the head's, and move what must read to the right of the head (the
  camera's side) or above it; turn the chest (left shoulder forward) so the short left arm still reaches;
- a test of the pose (an angle, a distance) is not a test of what is seen: the #383 tilt passed its pitch test and
  was invisible.

Deadnight's capture: `game/tests/captures/reload_sheet.tscn --measure`.

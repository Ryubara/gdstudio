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

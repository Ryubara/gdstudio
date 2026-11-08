# Key art and icons

Rendering a game's app icon and key art in the pinned Blender, headless (`-b -P`), with Cycles on the GPU, from the
game's own models. Learned on Deadnight's branding (Deadnight #438): six shots, icon masters at 2048 px and key art at
3840 x 2160, 33 to 225 s each on the GPU.

## Building the shot from the game {#building-the-shot-from-the-game}

- Load the game's own `.glb` characters, weapons and props; build anything else (a fence, a screen) from the game's
  numbers, so the art shows the game players get.
- Pose characters with a frame of a real clip (an aim clip at frame 0) and hold the weapon as the game does: the same
  hand bone, hold transform and grip numbers.
- glTF-imported bones have Blender axes, not the file's. To use Godot's hold transform `HOLD` on a bone, compute the
  rest correction from the `.glb`'s own node tree, `C = bone.matrix_local^-1 @ (M_gl @ node_rest)`, then place the
  weapon at `arm.matrix_world @ pose_bone.matrix @ C @ HOLD @ M_gl^-1`: the game's numbers on Blender's bone as
  they are put the weapon at the wrong angle.

## Light, camera and compositor {#light-camera-and-compositor}

- Cycles light linking (`light.light_linking.receiver_collection`) gives each character its own key and rim light
  without lighting the set; a rim from behind makes the dead read as silhouettes.
- A camera aimed by where a subject should sit on screen needs Euler order `XYZ` (yaw outermost), set before the
  angles: in `ZXY` the pitch is applied outside the yaw, so the camera rolls and points away from the subject.
- Blender 5's compositor is a node group (`scene.compositing_node_group`) and the Glare node's settings are input
  sockets; `scene.use_nodes` and `scene.node_tree` are gone. Check the pinned version's API, not memory.

## Files {#files}

- Generated images (masks, a sky) packed into the `.blend` need `pixels.foreach_set` and a pack at save: packed
  right after writing `image.pixels`, the image was stored before the pixels reached it and came back empty.
- Pass absolute output paths: Blender resolves a relative path itself, not the shell that started it, and do not
  edit a bash render script while it runs ([Build scripts](build-scripts.md#running)).
- Export each icon master to every platform size (1024 down to 16) with rounded-square and circle mask previews and a
  check sheet on dark and light grounds, so the pick is made at the sizes players see.

## Title art and store sizes {#title-art-and-store-sizes}

Learned on Deadnight's title art: five compositions with the title, each a 3840 x 2160 and a 2400 x 3600 master,
cut into every Discord, Steam, itch.io and social size (the table is in the game's `docs/design/branding.md`).

- Render the art without text and lay the wordmark over each crop afterwards: one render then serves every target,
  the title sits inside each target's own safe area, and the Steam library hero (which forbids text) is the same
  art.
- Compose for the title: keep a dark, quiet band (the night sky) above the action, and keep the action in the
  middle 4:3 so the narrow crops (itch.io's 5:4 cover, Discord's 13:11 shelf crop) keep it.
- Render a separate 2:3 master for the vertical and library capsules rather than cropping the 16:9 one; give it a
  longer lens. With `sensor_fit = "AUTO"` the 36 mm sensor fits the frame's long side, so a tall frame covers 36 mm
  up and down with the same lens (84 degrees at 20 mm) and the players sat small under two thirds of sky: take the
  landscape lens times about 1.35 and the subject a little lower, or `sensor_fit = "HORIZONTAL"` when the width
  must match.
- Build the wordmark from the game's display face in plain Python (Pillow, NumPy, SciPy): close the face's inline
  hairline with a distance-transform closing to get the solid letter, sweep it for a block shadow, grow it for a
  keyline.
- The smallest capsule (Steam's 462 x 174, shown down to 184 x 69) cannot hold the whole scene under a full-width
  title: the players vanish behind the letters. Crop tight on the subject at one side and set the stacked lockup
  at the other, about 85 % of the height; the letters come out larger than the wide lockup at full width.
- A prop's palette swatch can be lit in the render (a marquee's bulbs) by an emission driven by the distance of the
  texture colour from that swatch.
- A video preview (Discord asks for 640 x 360, at most 0.5 MB and 10 s): bake each walker's clip into one action of its
  own (`Video_<armature>`), assigned with its slot after each frame's pose and before any depsgraph update, then key the
  bones (with no action `keyframe_insert` makes a new one each call, and putting the clip back replaces the keys); stop
  each walker short of the subject (dead walking toward it pile up in front of it within seconds), render about 5 s, and
  encode two-pass H.264 at the bitrate the size cap allows; denoised frames compress far better than noisy ones. A 5 s
  1920 x 1080 copy also fits under 0.5 MB.

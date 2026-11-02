# Key art and icons

Rendering a game's app icon and key art in the pinned Blender, headless (`-b -P`), with Cycles on the GPU, from the
game's own models. Learned on Deadnight's branding (Deadnight #438): six shots, icon masters at 2048 px and key art at
3840 x 2160, 33 to 225 s each on the GPU.

## Building the shot from the game

- Load the game's own `.glb` characters, weapons and props; build anything else (a fence, a screen) from the game's
  numbers, so the art shows the game players get.
- Pose characters with a frame of a real clip (an aim clip at frame 0) and hold the weapon as the game does: the same
  hand bone, hold transform and grip numbers.
- glTF-imported bones have Blender axes, not the file's. To use Godot's hold transform `HOLD` on a bone, compute the
  rest correction from the `.glb`'s own node tree, `C = bone.matrix_local^-1 @ (M_gl @ node_rest)`, then place the
  weapon at `arm.matrix_world @ pose_bone.matrix @ C @ HOLD @ M_gl^-1`
  ([lesson](../lessons/2026-11-01-gltf-bones-in-blender-do-not-have-the-files-axes.md)).

## Light, camera and compositor

- Cycles light linking (`light.light_linking.receiver_collection`) gives each character its own key and rim light
  without lighting the set; a rim from behind makes the dead read as silhouettes.
- A camera aimed by where a subject should sit on screen needs Euler order `XYZ` (yaw outermost); `ZXY` spins it
  ([lesson](../lessons/2026-11-01-a-camera-in-zxy-order-spun-off-its-subject.md)).
- Blender 5's compositor is a node group (`scene.compositing_node_group`) and the Glare node's settings are input
  sockets; `scene.use_nodes` and `scene.node_tree` are gone
  ([lesson](../lessons/2026-11-01-blender-5-moved-the-compositor-to-a-node-group.md)).

## Files

- Generated images (masks, a sky) packed into the `.blend` need `pixels.foreach_set` and a pack at save
  ([lesson](../lessons/2026-11-01-a-packed-generated-image-lost-its-pixels.md)).
- Pass absolute output paths: Blender resolves a relative path itself
  ([lesson](../lessons/2026-11-01-blender-resolved-a-relative-out-path-itself.md)).
- Do not edit a bash render script while it runs
  ([lesson](../lessons/2026-11-01-editing-a-running-bash-script-corrupted-the-run.md)).
- Export each icon master to every platform size (1024 down to 16) with rounded-square and circle mask previews and a
  check sheet on dark and light grounds, so the pick is made at the sizes players see.

# Physics interpolation (3D)

What turning on 3D physics interpolation taught us in Deadnight (the game's page is `docs/research/physics-interpolation.md`
there, with the numbers). Godot 4.7.2, Compatibility renderer (desktop measured; it is a scene-side feature, the same
code for every renderer).

## Why {#why}

Physics runs at a fixed rate (60 ticks a second), the screen at any rate. A body drawn at its last tick position is still
for two or three frames at 144 Hz, then jumps: from the side it looks doubled and blurry. At 60 Hz frames and ticks
coincide and nothing shows, so only players with a fast screen see it. Glenn Fiedler's "Fix Your Timestep" is the idea:
draw the blend of the last two ticks.

## Using it {#using-it}

- Turn on `physics/common/physics_interpolation` (the Physics > Common section). It blends every node that
  moves in `_physics_process`, on the render side: scripts still see the tick transform.
- Move things in the tick. A node moved in `_process` or by a tween is blended against a tick-old position and is drawn
  late and unevenly; set its `physics_interpolation_mode` to `PHYSICS_INTERPOLATION_MODE_OFF` (children inherit).
- A camera or rig that you blend by hand is OFF as well: the two blends stack and the body still wanders (11 px in our
  measure, against 0.0).
- A capture camera that cuts between spots is OFF from the moment it is made: with it on, the saved frames show where
  the last ticks left it, tens of metres from the printed position, and the log has the one line `[Physics
  interpolation] Interpolated Camera3D triggered from outside physics process`.
- A camera that renders an off-screen view and is set in `_process` (the minimap's `SubViewport` camera, a baker) is OFF
  too: left on, it was blended with its transform a tick ago and a point unprojected through it was up to 0.65 of the
  picture away from the maths that placed it (gdstudio #884; [Minimap](minimap.md#drawing)).
- After you set a new transform on a node that must not slide in (a teleport, a spawn, a pooled node reused), call
  `reset_physics_interpolation()` once the transform is set.
- Skinned bones are not interpolated: the skin draws the bones of this frame's update. A `BoneAttachment3D` child (a
  weapon in a hand) is drawn with them (0.0 mm in gdstudio #1473's test, the pistol through a sprint, a slide and an
  aim). A ragdoll's bones are written once a tick by its `PhysicalBoneSimulator3D`, so its skin steps while its
  `PhysicalBone3D` nodes glide: draw the bones from the bodies' interpolated transforms
  ([Drawing between ticks](ragdoll.md#drawing)).
- A node a skeleton modifier or `skeleton_updated` places every frame (a two-hand weapon placed from the chest, a hand
  target on it) is OFF, as the engine makes every `BoneAttachment3D` (its constructor sets the mode, and the editor
  warns on one turned back on). Left on, the engine draws it between where it was at the last two ticks
  (`SceneTreeFTI`: the local transform at the tick, against the one set since), while the skin it rides is drawn
  with this frame's bones: the 3D Third Person rifle was drawn 145 mm from both hands at each landing, though the pose
  read in `skeleton_updated` had them 0.0 mm apart (gdstudio #1464). OFF, it is drawn at its parent's blended place
  times its own transform of this frame, which is how the skin is drawn too.

- The mode is inherited down the tree, and a `Control` is not physics-interpolated: a 3D world under a UI screen is
  drawn at the last tick whatever the project setting says. Set the world's root to `PHYSICS_INTERPOLATION_MODE_ON`
  (an explicit ON overrides an inherited OFF), and prove it in the tree the game builds
  (`Node.is_physics_interpolated_and_enabled()` on the body), not in a test room under a plain `Node`.

- **Approach:** Turn on physics interpolation in the first playable build, and test the on-screen position at 144 fps
  over 60 ticks. **Watch out for:** fixed-step physics needs drawing between ticks; the camera blended the last two
  ticks by hand with interpolation off, so a smooth camera framed a body that stepped every two or three frames on a
  120-165 Hz screen, which a 60 Hz screen never shows. **Seen:** Deadnight, 2026-11-01 (fix: interpolation on, the hand
  blend off, and the 144 fps measure ([below](#measuring-it))).
- **Approach:** Turn interpolation off on any camera a script moves from place to place (a warm-up's or a capture's),
  in the line that makes it, and test what the camera does at its first place. **Watch out for:** an interpolated
  camera answers `get_frustum()` (and culls) from where the last tick left it: a warm-up camera put at a probe the
  player had not seen reported the frustum of its last place, so it found no probe there and waited for none, and only
  the suite's frame count showed it. **Seen:** gdstudio #981, 2026-11-10 (fix: `PHYSICS_INTERPOLATION_MODE_OFF` on the
  emitter's tour camera).
- **Approach:** Turn physics interpolation off on a node that is placed from the skeleton's pose while the skeleton
  updates (a held gun's pivot set by a modifier), in its scene, and test where it is drawn against the drawn skin on
  every frame of the fast moves, not only the one where it showed ([below](#measuring-it)). **Watch out for:** the lag
  is there on every frame, not only at a landing: the rifle trailed the hands by a frame of the pose's movement, 14 to
  35 mm at a sprint and 0.7 m on the frame a slide's end jumped to the crouch, though every read in script had the
  hands on it at 0 mm. **Seen:** gdstudio #1464 and #1473, 2026-11-13 (`Pivot` in `two_hand_hold.tscn`, PR #1475; the
  pistol's `BoneAttachment3D` was in step).
- **Approach:** Assert `is_physics_interpolated_and_enabled()` on the real body inside the real screen. **Watch out
  for:** a setting a node inherits holds only in the tree the game builds: interpolation was measured in a test room
  under a plain `Node`, while in the game the night hangs under a `Control`, which switched it off below, and the web
  measure was split into a follow-up nobody started. **Seen:** Deadnight #344, #353, 2026-11-01 (fix: the world's root
  is set ON and asserted in the game's tree, and the reported fix is proved on the live web build
  ([proof](../../studio/starting-work.md#stopping-and-finishing))).

## Measuring it {#measuring-it}

- **Approach:** To read where a node is drawn on every frame at the suites' own rate (60 frames and 60 ticks), read
  `get_global_transform_interpolated()` after the frame and before the next tick, once the frame-end pass has run:
  the 3D Third Person template's `AfterFrameReader` queues an input event no action uses in the frame, and the engine
  hands it out at the start of the next loop, before the tick, headless too. Compare a held thing with the skin as
  `drawn skeleton * the bone's pose of this update`. **Watch out for:** reads in the frame (`_process`,
  `skeleton_updated`, `process_frame`, a modifier) come before that frame's end pass, and a read in the tick gets the
  plain transform, so all of them showed the rifle on the hands while it was drawn a frame behind; a rendered check
  (additive markers, one skinned to the hand bone, one on the gun, alone on a black frame) agreed to the pixel. A
  `skeleton_updated` measure of a drawn pose is only the pose: the pistol's pages pointed there before. **Seen:**
  gdstudio #1473, 2026-11-13 (`tests/gameplay/test_held_weapon_drawn.gd`: 0.7 m before, 0.0 mm after; the slower
  ticks' way is the last entry here).
- The node's `global_transform` shows the tick, never the blend: measure where the renderer draws. In a headless test,
  `Node3D.get_global_transform_interpolated()` through `Camera3D.unproject_position()`; in a capture, find a marker ball
  in the rendered image (unshaded, `no_depth_test`).
- Run at a frame rate that is not a multiple of the tick rate: `--fixed-fps 144` with 60 ticks gives 2, 2, 3 frames per
  tick, the same on every machine. A viewport with `canvas_items` stretch returns `unproject_position` in the base size,
  not the image's.
- The metric: a steady mover at a constant lag from a smooth camera holds one screen position; peak-to-peak of that
  position, or the RMS of the second difference `x[i+1] - 2 x[i] + x[i-1]`, is the judder.
- A frame that is long (over 1.45 ticks) moves the body by more than a tick at once for the camera and the body alike,
  and a spring camera takes half a second to follow: a test under load must skip such a stretch, not fail on it.

- On the web: expose the body's interpolated screen position per drawn frame to the page and compare a stretch of
  steady movement against the straight line between neighbouring frames at their own times (unevenness). Chrome with
  the GPU and `--disable-gpu-vsync --disable-frame-rate-limit` for an unpaced run (Deadnight `tools/web_smoke/judder.py`).
  Wrap `requestAnimationFrame` to `drawImage` the canvas right after the game's frame for real pixels.
- **Approach:** To place a child of a physics-interpolated body on every drawn frame (a model held level while its body
  rises), take it out of interpolation for the move (`top_level`, `physics_interpolation_mode` off), place it from the
  drawn time (the last tick less `1 - Engine.get_physics_interpolation_fraction()` of a tick), give it back with
  `reset_physics_interpolation()`, and have a test read that node's own transform. **Watch out for:** in a headless test
  `get_global_transform_interpolated()` did not show the per-frame placement, and the fraction is 0 through a short
  `--fixed-fps` run and near 1 after minutes of suites, so a result that depends on it differs between a suite run alone
  and the full run. **Seen:** gdstudio #1037 (PR #1239), 2026-11-11 (the vault's held model).
- **Approach:** To test what the engine draws for a node placed in the drawn frame against a skin, read
  `get_global_transform_interpolated()` of the node and of the skeleton on `SceneTree.process_frame` of the frame
  after the skeleton's update, only when `Engine.get_physics_frames()` has not moved since that update, with the
  bones the skin got in it (read in `skeleton_updated`) and the physics ticking slower than the frames (20 ticks at 60
  frames: two frames in three qualify). **Watch out for:** a tick in between makes the node's last and
  current transforms one and hides the lag. Read inside `skeleton_updated`, the node's place and the
  bone agreed to 0.0 mm on the frames that drew them 145 mm apart. **Seen:** gdstudio #1464, 2026-11-13
  (`test_rifle_drawn_hands.gd`: 145 mm before, 0.2 mm after).

# Physics interpolation (3D)

What turning on 3D physics interpolation taught us in Deadnight (the game's page is `docs/research/physics-interpolation.md`
there, with the numbers). Godot 4.7.2, Compatibility renderer (desktop measured; it is a scene-side feature, the same
code for every renderer).

## Why

Physics runs at a fixed rate (60 ticks a second), the screen at any rate. A body drawn at its last tick position is still
for two or three frames at 144 Hz, then jumps: from the side it looks doubled and blurry. At 60 Hz frames and ticks
coincide and nothing shows, so only players with a fast screen see it. Glenn Fiedler's "Fix Your Timestep" is the idea:
draw the blend of the last two ticks.

## Using it

- Turn on `physics/common/physics_interpolation` (the Physics > Common section). It blends every node that
  moves in `_physics_process`, on the render side: scripts still see the tick transform.
- Move things in the tick. A node moved in `_process` or by a tween is blended against a tick-old position and is drawn
  late and unevenly; set its `physics_interpolation_mode` to `PHYSICS_INTERPOLATION_MODE_OFF` (children inherit).
- A camera or rig that you blend by hand is OFF as well: the two blends stack and the body still wanders (11 px in our
  measure, against 0.0).
- After you set a new transform on a node that must not slide in (a teleport, a spawn, a pooled node reused), call
  `reset_physics_interpolation()` once the transform is set.
- Skinned bones are not interpolated; a `BoneAttachment3D` child (a weapon in a hand) moved with a drawn-frame animation
  was smooth in our measure.

- The mode is inherited down the tree, and a `Control` is not physics-interpolated: a 3D world under a UI screen is
  drawn at the last tick whatever the project setting says. Set the world's root to `PHYSICS_INTERPOLATION_MODE_ON`
  (an explicit ON overrides an inherited OFF), and prove it in the tree the game builds
  (`Node.is_physics_interpolated_and_enabled()` on the body), not in a test room under a plain `Node`.

## Measuring it

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

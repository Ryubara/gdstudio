# Third-person camera: springs, interpolation and walls

What building Deadnight's shoulder camera taught us (the game's page is `docs/research/shoulder-camera.md` in the
Deadnight repository, with the numbers). Godot 4.7.2.

## Smoothing that feels the same at any frame rate

- `lerp(a, b, k)` with a constant `k` per frame, and an Euler spring, both feel different at 30, 60 and 144 frames a
  second, and in Movie Maker (a fixed 0.1 s delta at 10 fps, with six physics ticks in each frame). Use the closed-form
  **critically damped spring** (Ryan Juckett, "Damped Springs"): with `e = exp(-w dt)`, offset `x` and velocity `v`
  from the target, `x' = (x (1 + w dt) + v dt) e` and `v' = (v (1 - w dt) - x w w dt) e`. It is exact for any `dt`.
- The error falls as `(1 + w t) e^(-w t)`; 95 percent is gone at `w t` of about 4.75, so a settle time `T` needs
  `w = 4.75 / T`.
- It keeps its velocity, so reversing a half-done aim zoom has no kink; an exponential ease starts at full speed.
- Following a body that moves steadily, a critically damped spring trails it by `2 v / w`, not `v / w`. Pick the
  follow rate by the lag you can accept at a run, not by the settle time.

## Physics ticks and render frames

A camera that reads the body in `_process` sees it jump once per physics tick. Record the body after each tick and
draw `previous.lerp(current, Engine.get_physics_interpolation_fraction())`. Make the camera's step a function of
`(delta, fraction)` so a test drives it with fixed numbers: no wall time, the same result everywhere. With a spring on
top, the unblended jitter is already small (2.7 percent of the travel at 144 Hz over a 60 Hz run in our test); the
blend takes it to zero.

## Walls

- `PhysicsDirectSpaceState3D.cast_motion` **ignores a body the shape already starts inside**, so start every sweep
  from a point known to be clear. A `SpringArm3D` covers only the boom; sweep sideways to the shoulder first, then back
  along the view, then straight from the head to the lens (the two legs can pass either side of a corner).
- Pull the camera in at once and let it out slowly; a spring on the way in lets the lens into the wall.
- CSG boxes with `use_collision` are concave: `intersect_shape` and `intersect_point` do not report a shape lying
  inside a thin wall. To sample "places a body can stand", take points from a baked navigation mesh, not from "a
  capsule fits here".
- Hide the body by the lens-to-head distance (with a hysteresis margin), not by the arm length: a wall at the shoulder
  puts the lens in the head with a full arm.

## Shake and sway

- **Rotation only, on the lens node**, while the rig keeps the unshaken transform that the aim reads, so shots stay on
  the crosshair (firing shake: [Shot feedback](shot-feedback.md)).
- **Count a sprint sway in footfalls, not seconds**: phase = distance travelled / step length, the same step the
  footstep sounds use, so the sway stays on the gait at any speed. Bob once per footfall, roll and yaw once per two.
  Ease it in and out, and gate it on ground speed and on sprint, not on the input.
- **Combine the two** by multiplying the turns, and let the sway give way while a shot's shake is up.
- **"Very subtle" is a number.** Deadnight settled on sway peaks of 0.3 degrees pitch, 0.15 yaw and 0.2 roll, and at
  most 0.5 degrees for any shot; a test holds each bound, and a player setting scales both to zero.

## Projecting world points to the HUD

From Deadnight's world markers and teammate names (#430):

- `Camera3D.unproject_position` returns coordinates in the viewport's visible rect; divide by its size for a share of
  the screen.
- Behind the lens it divides by a negative depth, so a point straight behind lands near the middle of the screen. Use
  `is_position_behind`, and pin an off-screen marker to the edge from camera-space `x` and `|z|` instead.
- Project the drawn body (`get_global_transform_interpolated()`), and run the projection at a late
  `process_priority` so it follows a camera that places itself in `_process`.
- A test that reads what a `_process` pushed awaits two idle frames: `await get_tree().process_frame` returns before
  that frame's `_process` calls.
- Another `Camera3D` entering the tree (a second body in the same process) can become current; call `make_current()`
  after any join ([lesson](../lessons/2026-11-01-a-second-body-took-the-current-camera.md)).

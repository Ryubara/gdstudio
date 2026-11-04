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
- Another `Camera3D` entering the tree (a second body in the same process) can become current
  ([lesson](../lessons/2026-11-01-a-second-body-took-the-current-camera.md)); see the next section for the fix.

## One current camera per viewport

From Deadnight #702 (a bot's body had the view):

- A `Camera3D` with `current = true` in a scene takes the viewport's view **each time an instance enters the tree**,
  and a camera with `current = false` takes it too when it is the first camera in the viewport (Godot's
  `Camera3D` makes the first camera of a viewport current). So N instances of a scene with a current camera
  leave the view on the last one that joined.
- Do not fix that in the capture or test code (`make_current()` after the join): the game then still looks through
  the wrong body. Decide who owns the view where the bodies are made: every body that is not the person's sets
  `camera.current = false` before `add_child` (Deadnight: `Player.release_view()`).
- Test it on the engine's answer, `get_viewport().get_camera_3d()`, mapped back to the body that owns it, and on every
  other body's `camera.current` being false; check after each event that adds a body: the spawn, a late seat, a
  revive. A test that reads only the person's own camera node passes while the view is elsewhere.
- `release_view()` leaves the camera node in place, since the rig uses it for aiming; only the `current` flag goes.

## A rig no one looks through

From Deadnight #938. Every body of a night owned a rig that eased its springs and swept the world in every drawn
frame (16 to 43 us a step), whether anyone looked through it or not: the bots', the puppets', a game server's.

- **Do not run it.** A body no one looks through rests its rig (`rest()`: `_process` off, `_resting` kept in a flag).
  What reads the rig (the weapon's pose reads `yaw`, `pitch` and `aim_transform()`) is told the look in each physics
  tick with `aim_along(head, yaw, pitch)`, under a microsecond. A bot's aim never came from its rig: the command
  carries the origin and the direction. Say which bodies rest where they are made (a bot, a body that draws
  nothing), not from `local_input`, which is also false for a body driven by hand or filmed.
- **Switch it off in `_ready()`.** `set_process(false)` before the node is in the tree is undone when it is ready
  (probe: one call a frame still), so the rig re-asserts its flag in `_ready()`
  ([lesson](../lessons/2026-11-03-a-process-switch-set-before-the-tree-was-undone-on-ready.md)). Prove it by counting
  `is_processing()` nodes in the built scene.
- **The bodies a sweep passes through** are kept in a static list (added on `tree_entered`, removed on
  `tree_exiting`), not found with `get_nodes_in_group` and a new Array in every step (1.2 to 1.8 us down to 0.2 us
  with four bodies); the list is shared, so a sweep reads it and never changes it.
- A rig that ran for no view also read the wrong look: nothing set a bot's `yaw` and `pitch` (a probe printed 0 for a
  night's worth of turns while the body turned), so its weapon's pose read the spawn heading and the lens the
  body-hidden check measured sat behind that. The look from the command is what the pose should read.

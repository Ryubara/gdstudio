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

## Walls {#walls}

- `PhysicsDirectSpaceState3D.cast_motion` **ignores a body the shape already starts inside**, so start every sweep
  from a point known to be clear. A `SpringArm3D` covers only the boom; sweep sideways to the shoulder first, then back
  along the view, then straight from the head to the lens (the two legs can pass either side of a corner).
- Pull the camera in at once and let it out slowly; a spring on the way in lets the lens into the wall.
- CSG boxes with `use_collision` are concave: `intersect_shape` and `intersect_point` do not report a shape lying
  inside a thin wall. To sample "places a body can stand", take points from a baked navigation mesh, not from "a
  capsule fits here".
- Hide the body by the lens-to-head distance (with a hysteresis margin), not by the arm length: a wall at the shoulder
  puts the lens in the head with a full arm.

- **Approach:** Stand a capture spot at least the arm's length (2.8 m) clear of any closed door or wall behind it, set
  the body's facing to the camera's yaw when posing it, and look at the first frame of each spot before taking numbers
  from it. **Watch out for:** a "from the yard's gate" capture stood the player 1 m in front of a shut door whose slab
  is solid; the spring arm hit it and pulled the camera in to his face, which also changes draw counts, and the body
  kept its spawn facing and looked at the camera. **Seen:** Deadnight #853, 2026-11-03 (fix: spots are placed clear of
  doors and walls and the pose sets `state.facing` and `rotation.y`).

## Reading a rotation {#rotations}

<!-- new section: the page held smoothing, walls and projection but nothing on reading a turn back from a transform -->

- **Approach:** Read the turn about the up axis from where an axis points, `atan2(basis.z.x, basis.z.z)`, never from
  `rotation.y` or a YXZ Euler triple. **Watch out for:** Euler angles in YXZ order are ambiguous near a quarter turn
  about Y, so the engine may return the same rotation as another triple and `rotation.y` is not the turn you set: a
  prop placed from a marker's yaw landed 0.05 m off for markers turned 90 or 270 degrees. **Seen:** Deadnight,
  2026-11-01 (fix: the yaw is read from the basis).

## Shake and sway {#shake-and-sway}

- **Rotation only, on the lens node**, while the rig keeps the unshaken transform that the aim reads, so shots stay on
  the crosshair (firing shake: [Shot feedback](shot-feedback.md)).
- **Count a sprint sway in footfalls, not seconds**: phase = distance travelled / step length, the same step the
  footstep sounds use, so the sway stays on the gait at any speed. Bob once per footfall, roll and yaw once per two.
  Ease it in and out, and gate it on ground speed and on sprint, not on the input.
- **Combine the two** by multiplying the turns, and let the sway give way while a shot's shake is up.
- **"Very subtle" is a number.** Deadnight settled on sway peaks of 0.3 degrees pitch, 0.15 yaw and 0.2 roll, and at
  most 0.5 degrees for any shot; a test holds each bound, and a player setting scales both to zero.

- **Approach:** Key any camera motion that follows steps to the grounded state, with a test that steps it through the
  first airborne tick; capture camera numbers in a sprint, a sprint-jump and long play; restate a feel request that can
  be read two ways as a number and a visible result, and confirm it before building. **Watch out for:**
  `SprintSway.step` took only the sprint flag and speed, which stay set in the air, so a sprint-jump swayed as on the
  ground; and a field of view meant to sit closer was first widened (70 to 77), the opposite of the ask. **Seen:**
  Deadnight #405, 2026-11-01 (fix: the rig takes `on_floor`; FOV 60, aim 40, sprint 63, sway halved (Deadnight #426)).

## Projecting world points to the HUD {#projecting-world-points-to-the-hud}

From Deadnight's world markers and teammate names (#430):

- `Camera3D.unproject_position` returns coordinates in the viewport's visible rect; divide by its size for a share of
  the screen.
- Behind the lens it divides by a negative depth, so a point straight behind lands near the middle of the screen. Use
  `is_position_behind`, and pin an off-screen marker to the edge from camera-space `x` and `|z|` instead.
- Project the drawn body (`get_global_transform_interpolated()`), and run the projection at a late
  `process_priority` so it follows a camera that places itself in `_process`.
- A test that reads what a `_process` pushed awaits two idle frames: `await get_tree().process_frame` returns before
  that frame's `_process` calls.
- Another `Camera3D` entering the tree (a second body in the same process) can become current; see the next
  section for the fix.

- **Approach:** Draw anything "at the centre of the screen" from the viewport, never from an inset container, and test
  aim end to end: the shot's end projected through the camera against the reticle's drawn centre, with an uneven safe
  area, near to far, hip and aimed, mouse and touch, on the phone canvas and in the browser. **Watch out for:** the HUD
  is inset to the phone's safe area and the reticle sat in the middle of the inset rectangle, 1.8 degrees above the
  shots on an iPhone; every aim test ran with zero insets and compared the shot with the camera, never the reticle.
  **Seen:** Deadnight #601, 2026-11-02 (fix: the reticle is placed from the viewport).

## One current camera per viewport {#one-current-camera-per-viewport}

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

- **Approach:** In a capture, make the rig's own camera current (`rig.find_children("*", "Camera3D", true,
  false)[0].make_current()`), and read the capture's log for `SCRIPT ERROR` before looking at its frames. **Watch out
  for:** a player's `camera_rig` is the `Node3D` that places the lens, not the `Camera3D` it moves: `make_current` is
  a nonexistent function there, and the Movie Maker frames stayed on the overview camera. **Seen:** Deadnight #634,
  2026-11-02 (fix: the rig's camera made current).

- **Approach:** Fix a fault found twice where the thing is made, not in each caller, and have camera tests read
  `get_viewport().get_camera_3d()` in the real Solo-with-bots flow. **Watch out for:** every body is `player.tscn` with
  its Camera3D saved as current, so the last body seated took the view; the first fix (Deadnight #430) went into twenty
  capture scripts as `make_current()`, and tests read the person's camera node, never the viewport's. **Seen:**
  Deadnight #430; Deadnight #702, 2026-11-03 (fix: the viewport test above).

## A rig no one looks through

From Deadnight #938. Every body of a night owned a rig that eased its springs and swept the world in every drawn
frame (16 to 43 us a step), whether anyone looked through it or not: the bots', the puppets', a game server's.

- **Do not run it.** A body no one looks through rests its rig (`rest()`: `_process` off, `_resting` kept in a flag).
  What reads the rig (the weapon's pose reads `yaw`, `pitch` and `aim_transform()`) is told the look in each physics
  tick with `aim_along(head, yaw, pitch)`, under a microsecond. A bot's aim never came from its rig: the command
  carries the origin and the direction. Say which bodies rest where they are made (a bot, a body that draws
  nothing), not from `local_input`, which is also false for a body driven by hand or filmed.
- **Switch it off in `_ready()`.** `set_process(false)` before the node is in the tree is undone when it is ready
  (probe: one call a frame still), so the rig re-asserts its flag in `_ready()`. Prove it by counting
  `is_processing()` nodes in the built scene.
- **The bodies a sweep passes through** are kept in a static list (added on `tree_entered`, removed on
  `tree_exiting`), not found with `get_nodes_in_group` and a new Array in every step (1.2 to 1.8 us down to 0.2 us
  with four bodies); the list is shared, so a sweep reads it and never changes it.
- A rig that ran for no view also read the wrong look: nothing set a bot's `yaw` and `pitch` (a probe printed 0 for a
  night's worth of turns while the body turned), so its weapon's pose read the spawn heading and the lens the
  body-hidden check measured sat behind that. The look from the command is what the pose should read.

## A fly-over that starts on the player's own lens

From Deadnight #973 (the end of a night: a slow pull-back from each player's camera, then cuts between authored angles
of the map; the game's page is `docs/research/end-of-night.md`):

- **Start on the lens the player had**: copy its `global_transform` and `fov` when the sequence begins and ease both
  to the first target (`smoothstep` on progress, a quaternion `slerp` for the turn), so the first frame is the frame
  the player was looking at and there is no cut at the start. Make the new camera current once; it is the only one
  that joins afterwards.
- **A pull-back needs a way that has room, not a fixed one.** Straight back and up is a ceiling in an interior. Try
  several ways (turns from straight back, at several heights), sweep each as the shoulder camera does (from the player
  to the wanted place, then from the lens to what that reached), and take the one that gets farthest, preferring the
  straight one on a tie: open ground gets the full pull, a low room gets a way along it.
- **Authored angles are data and are tested, not trusted.** A shot is a lens drifting from A to B while it looks at a
  point; a test steps along every shot and rejects it when a ray burst from the lens meets a solid within the lens's
  clearance (26 rays: a point inside a **concave** CSG wall is not reported by `intersect_point` or
  `intersect_shape`, but every ray from inside meets the wall's back face at once), when the view is blocked within
  1.5 m, or when a sphere sweep along the drift stops. Look at the frames too: the test cannot say a shot is dull.
- **Time is a number** (`seek(seconds)`): the same pose at any frame rate, and a capture or test places the camera at
  any moment without waiting.
- **A plan of a closed building**: put the camera high and set `near` so far out that everything above the cut is
  clipped (`near` of 56.4 from 60 m up shows what is below 3.6 m).

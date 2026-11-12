# Third-person camera: springs, interpolation and walls

What building Deadnight's shoulder camera taught us (the game's page is `docs/research/shoulder-camera.md` in the
Deadnight repository, with the numbers). Godot 4.7.2.

## Templates use Phantom Camera {#phantom-camera}

<!-- new section: the page covered a hand-built camera; nothing said which camera the kit's templates ship with -->

The kit's templates ship with the Phantom Camera addon (MIT, one pinned release), in the shared `3d-blank` base so
every template inherits it. A template's cameras are `PhantomCamera3D` nodes under one `PhantomCameraHost`: follow,
framing and hand-offs by priority come from the addon, and a template's own camera node only groups the settings a
developer tunes. A template's camera node is the one place to tune its camera: nobody needs to open the Phantom Camera
node. The springs, interpolation and wall notes below still apply when a game tunes or extends it.

- **Approach:** Build a template's camera on Phantom Camera, with its main settings (follow mode, distance, damping,
  look-at offset, wall collision, orbit input) grouped in the inspector with ranges and tooltips and defaults that play
  well, and show one priority hand-off between two cameras in the sample map. **Watch out for:** a hand-rolled spring
  arm was planned for 3D Third Person until the maintainer asked for Phantom Camera with inspector-level settings in
  every template. **Seen:** gdstudio #821, 2026-11-08.
- **Approach:** Give every export a wrapper forwards to a Phantom Camera a setter that applies it (`spring_length`,
  `follow_offset`, `camera_3d_resource.fov`, damping, `collision_mask`, `margin`), and keep only what the addon needs
  before its `_ready` (follow mode, target, a new `Camera3DResource`) in `_enter_tree`; test it by changing each export
  on the running scene and reading the Phantom Camera and, frames later, the real `Camera3D`. **Watch out for:** a
  wrapper that copies once in `_enter_tree` ignores a run-time change (the remote inspector), and the host overwrites
  the real `Camera`'s own FOV. **Seen:** gdstudio #830, 2026-11-08 (fix: setters and a test per export).
- **Approach:** Make the wrapper a `@tool` script too, so a change to distance or field of view moves the Phantom Camera
  in the editor: `_ready`, `_process` and `_unhandled_input` return at once there, the wrapper exports the camera it
  drives (`follow_camera`, since the addon moves the node under its spring arm at run time), and in
  `NOTIFICATION_EDITOR_PRE_SAVE` it puts the addon's defaults back on every property it forwards
  (`get_script().get_property_default_value`), resets the transform and drops the lens resource, then forwards again in
  `..._POST_SAVE`. **Watch out for:** saving `main.tscn` without that wrote spring length, margin, damping, offset and a
  transform computed from the distance onto the `FollowCamera`. **Seen:** gdstudio #831, 2026-11-08 (proved by saving
  the scene in the editor and reading the file).

- **Approach:** Give the wrapper every Phantom Camera property the template relies on and a developer would tune: the
  arm's start as a `Vector3` (world axes: the shoulder is not x, see the next entry), distance, field of view, near and
  far clip, damping, priority, the blend (duration, transition, ease), and the wall mask, shape and margin. Forward each
  through a setter, and in `PRE_SAVE` put the addon's defaults back (a fresh `PhantomCameraTween.new()` gives the
  blend's). **Watch out for:** the Framing group exposed only a `height`, which fed `follow_offset.y`, so a shoulder
  offset (x) or a depth (z) meant opening the Phantom Camera node, a second place with the same settings. Look-at, dead
  zones and axis locks are not forwarded: Third Person follow mode does not use them. **Seen:** gdstudio #831,
  2026-11-08.
- **Approach:** Keep the over-the-shoulder framing in one place on the wrapper: a `shoulder` choice (left, center,
  right), a `shoulder_offset` and a vertical offset that it writes to the **Camera node's own** `h_offset` and
  `v_offset`, over a `shoulder_time` when the side changes; keep the wrapper's `offset` for the arm's start. **Watch out
  for:** #831 built an `offset` Vector3 on the wrapper that fed `follow_offset`, which is in world axes and moves the
  arm and its wall cast (the "shoulder" was always toward world +X), where the request was the Camera node's H and V
  Offset, which shift the view along the camera's own axes without moving the camera or its cast. **Seen:** gdstudio
  #856, 2026-11-08 (maintainer correction, [log](../../studio/maintainer-corrections.md)).
- **Approach:** Make the wrapper the only writer of the Camera node's `h_offset` and `v_offset` and keep the Phantom
  Camera's `Camera3DResource` equal to what it writes, with a test that changes the field of view, the near clip and
  the sprint zoom and reads the node's offsets after; take them off the node in `NOTIFICATION_EDITOR_PRE_SAVE` too.
  **Watch out for:** the host copies the active camera's whole lens resource, offsets included, onto the `Camera3D` on
  every write of `fov`, `near` or `far`, so an offset typed on the Camera node alone is reset to the resource's 0 by the
  next zoom, and in the editor the host puts back any edit of a property it owns, with a warning. **Seen:** gdstudio
  #856, 2026-11-08 (proved in the editor: shoulder, offset and height set through the inspector reach the node, and the
  saved scene holds no offset on it).

## Smoothing that feels the same at any frame rate {#smoothing-that-feels-the-same-at-any-frame-rate}

- `lerp(a, b, k)` with a constant `k` per frame, and an Euler spring, both feel different at 30, 60 and 144 frames a
  second, and in Movie Maker (a fixed 0.1 s delta at 10 fps, with six physics ticks in each frame). Use the closed-form
  **critically damped spring** (Ryan Juckett, "Damped Springs"): with `e = exp(-w dt)`, offset `x` and velocity `v`
  from the target, `x' = (x (1 + w dt) + v dt) e` and `v' = (v (1 - w dt) - x w w dt) e`. It is exact for any `dt`.
- The error falls as `(1 + w t) e^(-w t)`; 95 percent is gone at `w t` of about 4.75, so a settle time `T` needs
  `w = 4.75 / T`.
- It keeps its velocity, so reversing a half-done aim zoom has no kink; an exponential ease starts at full speed.
- Following a body that moves steadily, a critically damped spring trails it by `2 v / w`, not `v / w`. Pick the
  follow rate by the lag you can accept at a run, not by the settle time.

## Physics ticks and render frames {#physics-ticks-and-render-frames}

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

- **Approach:** Keep the arm's start inside the character's capsule (`follow_offset` near zero sideways, the shoulder on
  the Camera node's `h_offset`), exclude the character from the arm (`SpringArm3D.add_excluded_object(
  player.get_rid())`) and sweep the camera's yaw in a walled room and in the open with aim, fire and sprint held.
  **Watch out for:** a world-space `follow_offset` of 0.55 m (the aim shoulder) put the arm's origin outside the
  capsule, and at the yaws where the arm points back across the body (-150 to -30) its ray hit the character: the lens
  dropped to 0.28 to 0.41 m from the head, a first-person view. Not the wall (the open floor did it too); at rest the
  origin is inside the capsule, where a ray ignores the body it starts in. The addon excludes `follow_target`, a
  `Node3D` and no collision object, so it excludes nothing. **Seen:** gdstudio #856, 2026-11-08.

## Keeping the aim through a shoulder swap {#shoulder-swap-aim}

<!-- new section: the page held the shoulder view (Phantom Camera) and walls; nothing said what a swap does to the aim
     or how look input and the swap go together -->

An over-the-shoulder view draws the crosshair in the middle of the screen while the lens sits beside the character, so
the crosshair's ray is the view's axis moved sideways by the shoulder offset. Swapping shoulders moves that ray by twice
the offset (1 m in 3D Third Person): with the view's turn unchanged, a point 4 m out slides about 10 degrees off the
crosshair, one at 30 m about 2 degrees, and a shot fired mid-swap goes where the player did not aim.

**What games and engines do (researched 2026-11-11).** No shipped game documents its swap code, so this rests on
guides, developer threads and engine docs, and the claims about games are second-hand:

- *Swap at once.* Guides describe the swaps of ARC Raiders and Ghost Recon Breakpoint as instant
  ([allthings.how on ARC Raiders](https://allthings.how/arc-raiders-shoulder-swap-keyboard-and-controller-controls),
  [on Breakpoint](https://allthings.how/?p=102873)); the ARC Raiders guide says the crosshair and the point of impact do
  not change, another says the gun changes side
  ([Gamer Guides](https://gamer-guides.com/arc-raiders/arc-raiders-settings/)), so that part is unsettled. An instant
  swap leaves no frame mid-way to aim from, which is why it is offered here as a time of 0.
- *Swap tied to aiming.* The Last of Us Part II swaps while aiming and has a setting to keep the last shoulder
  ([GameAccess](https://gameaccess.info/the-last-of-us-part-ii-motor-accessibility-options/3/)); PUBG players asked for
  a swap that does not need aiming
  ([Steam discussion](https://steamcommunity.com/app/578080/discussions/1/135512305404046752)). A swap made mostly while
  aiming is a reason for a shorter time while aiming (`aim_shoulder_time`).
- *Keep the point.* Developers who animate the swap find the aimed point by tracing from the camera before the swap,
  keep that point (no new trace during it) and turn the control rotation toward it as the offset moves, with a minimum
  range so a wall at the muzzle does not swing the view round; *adding* the turn to the control rotation instead of
  setting it is what lets the player keep looking during the swap
  ([Unreal forum thread](https://forums.unrealengine.com/t/1207784)).
  When the crosshair's ray hits nothing, the aimed point is the ray's end at a fixed distance, as Cinemachine's
  third-person aim does with its aim distance
  ([Cinemachine 3rd Person Aim](https://docs.unity3d.com/Packages/com.unity.cinemachine@2.6/manual/Cinemachine3rdPersonAim.html)).
- *Camera feel.* Several automatic camera motions fighting over one angle is a classic mistake, the player's input
  comes first, and modifiers should be relative, not absolute (John Nesky, "50 Camera Mistakes", GDC 2014, mistakes 8
  and 16: [GDC Vault](https://gdcvault.com/play/1020460/50-Camera), [translation](https://habr.com/en/post/272401)). An
  automatic offset added to the player's own input, not replacing it, keeps the camera from fighting the hand
  ([Little Polygon](https://blog.littlepolygon.com/posts/cameras/)). A stick's dead zone is the place that filters a
  resting stick, radial and scaled
  ([Josh Sutphin](https://www.gamedeveloper.com/disciplines/doing-thumbstick-dead-zones-right)), so the camera need not
  guess whether an input is deliberate.

**What 3D Third Person does.** `PlayerCamera.swap_shoulder()` finds the point the way the weapon does (the crosshair's
ray from the character's depth, the character left out, the first hit on `aim_point_mask` or the ray's end at
`aim_point_range`, never nearer than `aim_point_min_distance` past the arm) and keeps it. Each frame it works out the
turn that puts that point on the crosshair from the side offset now and the turn from the offset the swap started at,
both about where the arm starts now, and applies the *difference*: the player's look, the character's moves and a
crouch add to it, nothing builds up, and the turn stays when the swap ends (the shoulder slide is eased, so the turn
slows to nothing and no fade is needed; a fade back would turn the view off the point again). The player's look adds
by default (`swap_look` `ADD`, no threshold to tune); `RELEASE` lets the point go once the look adds up to
`swap_release_angle`. A stick resting inside its 0.2 dead zone sends no look at all. `swap_anchor_strength` scales the
turn, `keep_aim_on_swap` off is the old slide, and a time of 0 swaps at once and turns by the whole correction in one
frame. The client's camera is local and never sent: what it sends is the shot under its crosshair, so the server's body
fires at the kept point (0.04 degrees off in `test_net_swap_aim.gd`).

**When the point is kept.** Only on a swap that starts while the player is aiming (the aim or fire button held, the same
test that picks `aim_shoulder_time`). A swap while walking or sprinting without aiming only slides the view: the yaw and
pitch stay as they are, and so does the way the character runs, because the run follows the view's yaw.
`keep_aim_when_not_aiming` (off) keeps the point on every swap; `keep_aim_on_swap` off keeps it on none. A swap begun
while aiming keeps its point to the end even if the aim is let go mid-swap.

- **Approach:** Tie the aimed-point keeping to aiming: decide when the swap starts (`PlayerCamera._keeps_aim_now()`),
  and offer keeping on every swap as an inspector option that is off by default. Test it with simulated input: a
  sprint (W and Shift held) plus a swap keeps the view's yaw and the run's heading within 0.05 degrees, an aimed swap
  still keeps the point, and the option on keeps it while sprinting (`test_camera_swap_aim.gd`).
  **Watch out for:** a turn the camera makes on its own, with the player not aiming, also turns a moving player who
  is not aiming; on the main branch a sprinting swap past a near pillar turned the run by about 11 degrees (the
  `sprint_swap_tour` capture). **Seen:** gdstudio #1124, 2026-11-11 (the maintainer's review of #1094).

- **Approach:** Keep an aimed point through a change of view offset by applying the difference of two exact solutions
  (the yaw and pitch through the point from the new offset, minus those from the starting offset, about the arm's
  pivot now) on top of the current turn, and test it on the real `Camera3D`'s crosshair on a near board, a far board
  and the empty sky, with a look mid-swap and with the anchor off (`test_camera_swap_aim.gd`, within 0.2 degrees).
  **Watch out for:** setting the turn to the solution fights the player's look, and adding up a per-frame correction
  drifts with any noise. **Seen:** gdstudio #1087, 2026-11-11.
- **Approach:** When the view's turn and its H Offset change together, write the offset in the same step that moves
  the Camera node: the Phantom Camera host copies the turn in its *physics* step (priority 300) when the camera
  follows a physics body, so `PlayerCamera` writes a swap's offset from its `_physics_process` at priority 301; a
  test reads the crosshair at each physics tick, where a shot samples it. **Watch out for:** an offset written at once
  from `_process` met the old turn at the next tick: about 1 degree off mid-swap, a real shot 17 cm off at 8 m, while
  the crosshair read after each frame looked right. **Seen:** gdstudio #1087, 2026-11-11 (fix: the offset waits for
  the host's tick while a swap turns; `test_camera_swap_aim.gd` reads each physics tick).
- **Approach:** Expect the character's head to cross the crosshair for a frame or two of a sideways slide (the lens
  passes behind the head); the aim is unaffected, and a game that minds can raise `vertical_offset` or swap at once.
  **Watch out for:** reading that frame of a capture as the anchor failing. **Seen:** gdstudio #1087, 2026-11-11 (the
  capture's contact sheets).

## Aim and fire framing {#aim-and-fire-framing}

<!-- new section: the page held the shoulder view, walls and the swap; nothing said what aiming and firing do to the
     framing or who may change it -->

3D Third Person's `PlayerCamera` frames three ways besides the follow view: aiming (its Aim group: `aim_fov`,
`aim_distance`, `aim_shifts_shoulder`), firing without aiming (its Fire group: `zoom_when_firing`, `fire_fov`,
`fire_distance`) and sprinting or sliding (wider by `sprint_fov_change`). The zoom follows the buttons (`aim_held`,
`fire_held`), with no hold after a shot. The held weapon may change it: `WeaponDef.fire_zooms` off leaves the framing
alone on fire (the fists), and with `override_zoom` on, the weapon's `aim_fov`, `aim_distance`, `fire_fov`,
`fire_distance` and `zoom_offset` replace the camera's. The camera reads the held definition every frame
(`held_definition()`), on each machine, never sent. The rules and their tests: [Ammo, reloading and
switching](third-person/shooting.md#weapons) (gdstudio #1255) and [Crouch, aim and
shoot](third-person/shooting.md#crouch-aim-shoot) (gdstudio #856).

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

### One shake component for every game {#shake-component}

<!-- new section: the page held Deadnight's shot shake and sprint sway, nothing on a shake any feature can call -->

The templates share one shake, `CameraShake` with `ShakePreset` resources: the scripts are in the synced
`addons/gds_game/camera_shake/` ([Sync](../../studio/sync.md#gds-game)), so every game has them, and the presets are the
game's own `.tres` files (3D Blank's `core/camera_shake/presets/`, so 3D Third Person has them too). It is Deadnight's
trauma shake made general: the shake is `max rotation x level^exponent x wave`, where `level` is the trauma of a
one-shot (it drains by itself, `duration` seconds from 1) or the blend of a held source (it eases by `blend_speed`), and
the wave is seeded noise (impacts) or a sine (a gait). Everything is a function of the steps it was given, so tests and
captures see the same shake.

- **A rig owns one.** `CameraShake` is a node under the camera rig. It only works out the turn; the rig applies it on
  top of its own framing: `rotation_degrees()` (x pitch, y yaw, z roll) and `view_offset()` (a slide of the picture in
  metres, which moves no camera and so no wall sweep). `PlayerCamera` adds the turn to its Phantom Camera's
  third-person rotation and the slide to the shoulder's H and V offset. A rig steps it with `advance(delta)`; one that
  does not leaves `auto_advance` on.
- **One line from anywhere.** `CameraShake.shake(preset, at, scale)` plays a preset once on every shaker in the tree (a
  static function, no autoload: shakers join the group `camera_shake`). `at` is a world position for a play that
  fades with distance from the camera (the preset's `radius`, smooth to zero at the edge), `scale` multiplies the
  trauma, and leaving `at` out is felt in full (the player's own shot, a landing).

  ```gdscript
  const BLAST := preload("res://core/camera_shake/presets/explosion.tres")
  CameraShake.shake(BLAST, explosion.global_position)       # a blast: fades with distance, radius 40 m
  CameraShake.shake(preload("res://core/camera_shake/presets/landing.tres"))  # the player's own landing
  ```

- **An impact calls it the same way.** `Impacts` (its script in `addons/gds_game/impacts/`, its scene the template's
  `gameplay/impacts/impacts.tscn`) reports every hit with its
  `impact_made(surface, collider, point, normal)` signal, so one line from a game's own script shakes the view by it
  (`presets/impact.tres`: trauma 0.35, 0.25 s, felt to 15 m, so a hit beside the player is felt and one across the map
  is not):

  ```gdscript
  const IMPACT := preload("res://core/camera_shake/presets/impact.tres")
  impacts.impact_made.connect(func(_surface, _collider, point, _normal): CameraShake.shake(IMPACT, point))
  ```

  3D Third Person wires it for hits near the player (next bullet); any other use is one line like this.
- **A hit near the player shakes the view.** 3D Third Person's rig has a `NearHitShake` (`gameplay/player/`, under
  `PlayerCamera` in `ui/player_rig/player_rig.tscn`): it listens to the level's `Impacts.impact_made` and plays its
  `preset` (`core/camera_shake/presets/near_hit.tres`: trauma 0.6, 0.35 s, felt to 12 m) on the rig's own shaker at the
  hit's point, so it fades with the distance from the camera and is gone past the radius. A round on the floor 3.6 m
  away peaks at 0.07 degrees (the template's `near_hit_tour.tscn`); one 20 m away adds nothing. Inspector: `enabled`,
  `preset`, `strength` (a share of the preset's trauma, on top of `CameraShake.strength`), `shaker`, `impacts`. It plays
  on its own rig's shaker, not through the static `shake()`, so in a process with several worlds (the online tests) a
  hit shakes only the camera of its world. Online, `ClientCombat` plays each HIT through the same `Impacts`, so every
  peer shakes its own view from the event it has; where the screen finds no surface at the point it calls
  `NearHitShake.play_near(client, point)` itself. The player's own rounds landing close shake it too, by the same
  falloff (a HIT names no shooter).
- **A continuous source is held, not played.** `shaker.hold(&"sprint", preset, level)` every frame with the state's
  level (1 while it holds, 0 when not), or `CameraShake.hold_everywhere(source, preset, level, at)`. A held source
  eases in and out by the preset's `blend_speed`, `release(source)` lets it go, and a source at 0 that has died away is
  forgotten. `PlayerCamera` holds `&"sprint"` this way: its `sprint_shake_amplitude` (0 by default), frequency and blend
  stay in the Sprint group next to the sprint zoom and build a sine preset (pitch once a footfall, yaw and roll once
  for two, 1 : 0.5 : 0.67) read every frame, so a change in the inspector works while the game runs.
- **A shot kick is a one-shot.** `PlayerCamera.shot_kick_amplitude` (degrees, 0 by default) and `shot_kick_duration`
  are in the Fire group. The weapon's `fired` signal calls `kick()`, which adds a preset whose largest single turn is
  the amplitude (a trauma of 0.5 on a straight curve, so a burst stacks to at most twice that).
- **Strength.** `CameraShake.strength` (0 to 1, static) scales every shake in the game: a settings menu sets it from the
  player's "camera shake" option (and 0 for reduced motion), and 0 keeps no trauma at all. In 3D Third Person it is
  Settings > Controls > Camera shake (`controls/camera_shake`, 0 to 100 % in steps of 5, saved with the other options
  and applied at start: [Menus](menus.md#settings-and-rebinding)). Each shaker also has
  `camera_strength` and `enabled` for one camera (a cutscene's). Both apply to what is already shaking.
- **Presets.** `core/camera_shake/presets/` has `shot`, `landing`, `impact`, `explosion` and `sprint` as `.tres`: trauma,
  duration, wave, frequency, `max_rotation`, `max_offset`, exponent, blend speed and radius, tuned in the inspector.
  Peaks at one play: shot 0.19 degrees of pitch, impact 0.1, landing 0.25, explosion 1.3 (at 40 m it fades out).
- **Cheap and local.** Measured on the desktop in Compatibility (GDScript, 100,000 frames): 0.7 microseconds a frame idle,
  3.0 with the sprint held, 5.3 with the sprint, a blast and an impact up; nothing is made while playing but one small
  object per running preset. A shake is the local player's own view: it is never sent over a network (each client
  decides to play it from the event it already has).
- **Not done: an aim that ignores the shake.** The turn is on the Phantom Camera, and the weapon aims through the
  viewport's camera, so a shake moves where the crosshair points: a shot kick at 0.3 degrees moves a shot at 50 m by
  0.26 m. Deadnight kept an unshaken `aim_transform()` for the weapon; the template does not yet, so keep every default
  at 0 and any kick under half a degree.

- **Approach:** Key any camera motion that follows steps to the grounded state, with a test that steps it through the
  first airborne tick; capture camera numbers in a sprint, a sprint-jump and long play; restate a feel request that can
  be read two ways as a number and a visible result, and confirm it before building. **Watch out for:**
  `SprintSway.step` took only the sprint flag and speed, which stay set in the air, so a sprint-jump swayed as on the
  ground; and a field of view meant to sit closer was first widened (70 to 77), the opposite of the ask. **Seen:**
  Deadnight #405, 2026-11-01 (fix: the rig takes `on_floor`; FOV 60, aim 40, sprint 63, sway halved (Deadnight #426)).

- **Approach:** Blend a sprint zoom, a sprint shake and an aim view on the wrapper's resting framing: `advance(delta)`
  moves 0-to-1 blends toward the player's state, eases them with `smoothstep` and sets the Phantom Camera's
  `spring_length`, `follow_offset` and field of view; shake the third-person rotation (pitch once a footfall, yaw and
  roll once for two, 1 : 0.5 : 0.67 of an amplitude that is 0 by default). **Watch out for:** the host copies the active
  camera onto the real `Camera3D` every frame, so a rotation set on that node is overwritten; turning the rig swings the
  lens about the target (2 cm at 0.3 degrees and 4.4 m). **Seen:** gdstudio #836, 2026-11-08 (sprint +6 degrees and
  +0.4 m; aim 2.4 m, 0.55 m over the shoulder, 50 degrees).

- **Approach:** Give a feature that shakes the view one line, `CameraShake.shake(preset, at)` with a `ShakePreset`
  resource, never a shake of its own (a `sin` in the camera script, a tween on the lens), and hold a state-driven shake
  with `hold(source, preset, level)`. **Watch out for:** a shake written per feature (the template's sprint shake had its
  own blend and phase in the camera, Deadnight's shot and sprint sway two more classes) has its own settings, none turns
  down with the others, and the next feature (a landing, an impact, a blast) writes a fourth. **Seen:** gdstudio #879,
  2026-11-10 (fix: `CameraShake`; the sprint shake moved onto it with its inspector settings and default unchanged).

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

- **Approach:** Film a close-up of a live game through a `SubViewport` of its own (sharing `world_3d`, in a
  `SubViewportContainer` on a high `CanvasLayer`), never by making a second camera current in the main viewport.
  **Watch out for:** the 3D Third Person player aims along the main viewport's camera, so a close-up camera made
  current turned the character to face it: the rifle tour's front and side views showed her back as soon as she aimed,
  and a walk steered by that camera missed the pickup. **Seen:** gdstudio #889, 2026-11-10 (fix: `rifle_tour.gd`'s
  viewport).

- **Approach:** Fix a fault found twice where the thing is made, not in each caller, and have camera tests read
  `get_viewport().get_camera_3d()` in the real Solo-with-bots flow. **Watch out for:** every body is `player.tscn` with
  its Camera3D saved as current, so the last body seated took the view; the first fix (Deadnight #430) went into twenty
  capture scripts as `make_current()`, and tests read the person's camera node, never the viewport's. **Seen:**
  Deadnight #430; Deadnight #702, 2026-11-03 (fix: the viewport test above); gdstudio #905, 2026-11-11 (clients in
  one process: each viewport's camera was its own while every Phantom Camera host followed the last client's camera;
  ask the host's `get_active_pcam()` too, [the online client](third-person/online-client.md#puppets)).

## A rig no one looks through {#a-rig-no-one-looks-through}

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

## A fly-over that starts on the player's own lens {#a-fly-over-that-starts-on-the-players-own-lens}

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

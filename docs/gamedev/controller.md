# The player's controller

<!-- new section: gamedev had pages for level design and audio only; nothing held the engine-neutral rules of how a
player's controller, aim and feel are planned against the reference genre -->

How a player's character answers the devices: the genre's conventions, which devices are read, how aiming and firing
share the body and the camera, and the feel that makes an action land. The Godot side is in
[Camera](../engines/godot/camera.md), [Mouse look](../engines/godot/mouse-look.md) and
[Shot feedback](../engines/godot/shot-feedback.md).

## The genre's conventions {#conventions}

<!-- new section: the conventions a controller must follow had no home before this page -->

A player arrives with the reference genre's habits in their hands. List them before the controller is built, and test
each one, rather than finding them one by one in play.

- **Approach:** Before a controller is built, list the reference genre's conventions (hip fire turns the body and zooms,
  aim down sights, free movement facing the travel, sprint any way when not aiming, strafe when aiming) and test a
  matrix from day one: 8 directions, aimed and not, walk and sprint, each checked in a capture; camera reactions to
  movement are tuned numbers in the design. **Watch out for:** the conventions were never listed, so shots went down the
  camera ray while the body kept its facing, sprint was tied to forward input, and the sprint camera pull-back was never
  tuned against a reference. **Seen:** Deadnight, 2026-11-01 (hip fire); Deadnight, 2026-11-01 (sprinting backwards)
  (fix: the list and the movement matrix come before the controller).
- **Approach:** For each interaction, decide press or hold against the reference and write it in the design. **Watch out
  for:** hold-to-interact is the genre's convention for a repeated action, and interact was one press for every use, so
  a repair took one press per board. **Seen:** Deadnight, 2026-11-01 (fix: the design names press or hold for every
  interaction).

## Devices {#devices}

<!-- new section: which devices a controller reads and how it picks the input mode had no engine-neutral home -->

- **Approach:** Bind every gameplay action to all devices (device -1 in Godot) unless the game has local split screen,
  and drive play in a test from a pad that is not device 0. **Watch out for:** pads are numbered as they connect, and a
  reconnect or a virtual pad changes the number; every binding was tied to device 0, so the pad worked only sometimes.
  **Seen:** Deadnight, 2026-11-01 (fix: the bindings take every device and a test plays from another pad).
- **Approach:** Ignore pointer noise of a few pixels when choosing the input mode (and the glyphs it shows). **Watch out
  for:** the input mode is a guess from the last event, and any mouse motion, however small, switched the glyphs to
  keyboard, so a slightly moved mouse made the pad look undetected. **Seen:** Deadnight, 2026-11-01 (fix: a small motion
  no longer changes the mode).
- **Approach:** Name every input device the game ships on (keyboard and mouse, gamepad, touch) and plan touch controls,
  landscape lock and safe areas with the first playable build. **Watch out for:** desktop and the browser were planned
  and phones were not, though Discord Activities run on them. **Seen:** Deadnight, 2026-11-01 (fix: deadnight got
  researched touch controls for landscape play ([Touch controls](../engines/godot/ui-controls.md#touch-controls))).
- **Approach:** Ship every kit template that has a character controller with simple, intuitive touch controls: a
  floating move stick, a drag zone that turns the camera, a few large buttons, built as one reusable component that
  shows only on touch, presses the existing input actions and is tuned in the inspector. **Watch out for:** the first
  3D Third Person plan listed touch controls as one line beside the camera, until the maintainer made them a
  requirement of every controller template. **Seen:** gdstudio #821, 2026-11-08.
- **Approach:** Write one block per action in `[input]`, make gameplay actions listen to their own actions (`pause`,
  `interact`), never to `ui_cancel`, refuse the router's back on an in-game screen, and test the project file for a
  repeated action and the `InputMap` for two gameplay actions on one pad button or stick direction. **Watch out for:**
  two pull requests each added `interact`, Godot keeps the last block and `InputMap` cannot show the first, so on a pad
  X both reloaded and bought a door, and B (crouch) was also `ui_cancel`, which the player, the screen and the router
  each listened to and which paused the night. **Seen:** Deadnight, 2026-11-01 (fix: one block per action, gameplay
  actions own their names, and a test reads `project.godot`).

## Aim and hip fire {#aim}

<!-- new section: how aiming, hip fire and the camera share one body had no engine-neutral home -->

- **Approach:** Give each behaviour the maintainer names its own input (the aim zoom comes from the aim button only,
  never from a shot), let that state drive camera, body and hands together, blend every pose input that follows it
  (bound the per-frame change of the hand target), and test that each release clears in the same time from every press
  order. **Watch out for:** hip fire was first built as a second, partial aim (its own camera spring, a bool for the
  gun's yaw), then one aim weight driven by two inputs coupled every hip-fire tweak to the aim zoom. **Seen:**
  Deadnight #300, 2026-11-01; Deadnight #464, 2026-11-02 (fix: deadnight #473 removed the hip-fire zoom and #488 holds a
  press-order suite); gdstudio #856, 2026-11-08 (a camera driven by the aim pose zoomed on for a second after a shot).
- **Approach:** When two states share one output, test every transition between them, not only each state alone. **Watch
  out for:** a shot while aiming is not hip fire, but the aim weight was held while `fire_age < hip_fire_hold` and every
  shot reset `fire_age`, so the hip-fire zoom came on after aiming, shooting and letting go. **Seen:** Deadnight #428,
  2026-11-01 (fix: deadnight #433).
- **Approach:** Check the line to the target from both the eye and the barrel before an autopilot fires, in a
  third-person game. **Watch out for:** the shot leaves the barrel, beside and below the camera, so a corner can block
  the barrel and not the camera ray: a bot emptied its magazine into a car five metres away while the camera saw the
  zombie. **Seen:** Deadnight, 2026-11-01 (fix: the autopilot tests both lines).

## States and actions {#states}

<!-- new section: what an action does in each state of the body had no home -->

- **Approach:** In the first design of a feature with states (turning, reloading, swapping, crouching) and an action
  (fire), decide for each state whether the action fires, waits or is cancelled and how long a press stays valid; test
  it from the worst starting state on the server and the replaying client, and run a rule on the view with the bots.
  **Watch out for:** the server fired on the trigger alone and every test started with the body facing the view, so a
  hip-fire shot left a body that had not turned; the bot looked where it walked, so the new rule held its shots too.
  **Seen:** Deadnight #477, 2026-11-02 (fix: the simulation the server and the predicting client
  share computes `shot_ready`: the trigger or a buffered press, the body within a tolerance of the view (#488, #511);
  bot suites run when a rule reads a command field, [Bots](bots.md)).
- **Approach:** Evaluate a rule about a state (a dry gun in hand) on the server every tick, not on the action that
  usually meets it, and in the test let go of every input when the state arrives. **Watch out for:** the automatic
  reload began only when the server refused a shot at an empty gun, and touch auto-fire stops pulling the trigger at 0
  rounds, so on a phone nothing asked and the gun stayed dry. **Seen:** Deadnight #1278, 2026-11-05 (fix:
  `NightServer._reload_if_dry` starts it from the state).

## Feel {#feel}

<!-- new section: feel (shake, kick, flash, hit feedback) as a planned pass had no engine-neutral home -->

- **Approach:** Plan a feel pass for every verb (shake, kick, flash, hit feedback), with every amount exported so it is
  tuned in the editor. **Watch out for:** feel was not a planned pass: nothing reacted to firing but the sound, so there
  was no camera shake. **Seen:** Deadnight, 2026-11-01 (fix: a feel pass per verb, amounts exported ([Shot
  feedback](../engines/godot/shot-feedback.md#camera-shake))).
- **Approach:** When a feel request names a quality (a subtle shake), list every verb it can apply to (fire, sprint,
  land, hit, blast) and confirm them, and write the quality as a number (peak degrees) in the design, held by a test.
  **Watch out for:** shake was built for the verb in front of us (firing), so sprinting had none, and subtle had no
  number, so the shotgun reached 0.63 degrees. **Seen:** Deadnight, 2026-11-01 (fix: peaks are numbers in the design and
  a test holds each bound ([Camera: shake and sway](../engines/godot/camera.md#shake-and-sway))).
- **Approach:** Keep a controller's tuned numbers in one resource with groups, ranges and units, derive gravity and jump
  speed from a jump's height and rise time, pin the defaults in a test, and size the sample map from them (blocks a jump
  apart, steps under the step height, a ramp under the slope limit) with a test that fails when one no longer holds.
  **Watch out for:** a speed that feels right at a run still slides on a walk clip; the template blends idle, walk, run
  and sprint on ground speed and treats a half push of a stick as a walk, so the pad and the phone get a gait the keys
  would need a held key for. **Seen:** gdstudio #821, 2026-11-08
  ([The 3D Third Person template](../engines/godot/third-person-template.md#controller)).
- **Approach:** Pick a reference camera at the start and tune its framing, damping and interpolation before content.
  **Watch out for:** camera feel came after the systems, and the shoulder camera sat too far back and moved stiffly.
  **Seen:** Deadnight, 2026-11-01 (fix: deadnight's shoulder camera was brought closer and made fluid against a
  reference camera (Battlefront II)).

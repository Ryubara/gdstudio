# Mouse look at any frame rate

How a first or third person view is kept one to one with the hand when frames drop or arrive unevenly, what the shooters
and the engine docs say, and the one fault that broke it in Deadnight (#905) although every look rule was followed.
Godot 4.7.2. The game's page, with the numbers and the plots, is `docs/research/mouse-look-under-lag.md` there.

## What good shooters do

- **The mouse delta is a distance, not a speed.** Turn the view by `delta_pixels * sensitivity`, once per event, and
  never by `delta_pixels * sensitivity * frame_time`: a hand that moved 1000 pixels turned 1000 pixels at 30 or 144
  frames a second. Scaling by the frame time makes the turn depend on the frame rate (the Unity issue tracker lists it
  as the bug in its sample look script, and the Ogre and Unreal forums say the same).
- **A stick is a speed**, so it is scaled by the frame time: `stick * degrees_per_second * dt`. Nothing else is.
- **Turn the view on the drawn frame.** Apply the look the moment the event arrives (or in `_process`), and place the
  camera in `_process` from the newest yaw and pitch. A view that is updated in the physics tick shows the hand 0 to 2
  ticks late, and unevenly at any frame rate that is not the tick rate.
- **Smoothing is optional, and a function of time**: a window in seconds (or frames) that spreads a sample over the
  frames it is drawn in, keeping the sum so the view ends where the hand put it. Deadnight does that for touch only
  (a finger reports at 60 or 120 Hz; a mouse reports a delta every millisecond, so there is nothing to even out).
- **Sample the view for gameplay when the gameplay needs it** (a shot, the body's facing): read the same yaw and pitch;
  never keep a second copy of them that is turned at a different time.

## Godot specifics {#godot-specifics}

- `InputEventMouseMotion.relative` is the motion in the **viewport's** units: with `canvas_items` or `viewport`
  stretch it is multiplied by `base width / window width` (a 64 pixel headless window turned a 1920 base 30 times as
  far). `screen_relative` is the same motion in screen pixels, which the docs recommend for mouse look so that it
  behaves the same at every window size ([Mouse and input coordinates](https://docs.godotengine.org/en/stable/tutorials/inputs/mouse_and_input_coordinates.html)).
  A test that replays pixels through `Input.parse_input_event` must send them divided by that scale, or the totals
  are a window's guess.
- **Turn by `screen_relative`, never `relative`** (Deadnight #928): with a stretch the turn per mouse pixel changed with
  the window (1.5 times as far at 1280 wide as at 1920, 0.75 at 2560). Two traps after the switch. A hand-made
  `InputEventMouseMotion` in a test or a touch layer has `screen_relative` zero unless it sets it, so the view does not
  turn (set both). And **on the web the runtime reports a pointer move in device pixels** (`movementX` times
  `devicePixelRatio`): the stretch used to cancel the ratio, `screen_relative` does not, so a screen with a ratio of 2
  turns twice as far unless the look divides `DisplayServer.screen_get_scale()` out (web only). Test it by resizing
  the root `Window` (`size`, `content_scale_mode`, `content_scale_size`: the headless display server keeps them) and
  sending a path through `Input.parse_input_event` with both fields in window pixels; the viewport maps `relative`,
  not `screen_relative`. Probe the web build at two viewport sizes and two pixel ratios
  (`tools/web_smoke/look_size.py` in Deadnight).
- `Input.use_accumulated_input` (on by default) merges the motions of a frame into one event, delivered at the start of
  the frame; the total is the same, and a long frame gets one big event. Turn it off only to see events one by one in
  a test or a profile.
- **An event that arrived during frame k turns the view at the start of frame k+1**, which draws it. A probe that posts
  events at the end of `_process` and calls `Input.flush_buffered_events()` sees them in the next frame, the way the
  system's are.
- A rig that is placed every drawn frame is set to `PHYSICS_INTERPOLATION_MODE_OFF`
  ([Physics interpolation](physics-interpolation.md)), so the engine does not blend it a second time.

- **Approach:** Give every Control that only holds screens or a world `MOUSE_FILTER_IGNORE`, and prove mouse look
  through the real input path: a test lists every mouse-catching Control over a running level with the real main scene
  loaded, and the browser smoke moves the mouse and asserts the view turned. **Watch out for:** three full-screen
  Controls (the game's `Main` root, the router's `Stage`, the night screen) kept the default STOP and marked every
  motion handled; tests called the look handler directly, and a headless run skips GUI mouse handling, so nothing saw
  it. **Seen:** Deadnight, 2026-11-01 (fix: the containers ignore the mouse, and the listing test and the browser check
  hold it).

## The fault: set the child, then the parent {#the-fault-set-the-child-then-the-parent}

`ThirdPersonCamera._place` computed the view from the newest yaw, assigned it to the `Camera3D`'s `global_transform`,
and **then** assigned the rig above it (its `top_level` Node3D) the new position and yaw. A child keeps its *local*
transform when its parent moves, so the lens was drawn at `new_rig * old_rig^-1 * wanted`: the view plus one more step
of the rig's last turn, and its place swung round the pivot by the same step. The rig's `yaw` was exact, so every test
that read `yaw` passed (and so did every aim ray, which is built from the same numbers, not from the node).

What it looked like: at a steady turn, a constant lead of one frame's turn. With frames or mouse reports of uneven
size the drawn step is `2 s[k] - s[k-1]`: a frame that gets no mouse turns the view **back** by the last step, and a
long frame overshoots by its whole turn before the next one snaps back. The gamepad stick and the touch look went
through the same place.

**Rule: whatever you place by hand in `_process`, set the parent's transform before the child's, or make the child
`top_level`.** And a look test reads the **node the renderer draws** (`Camera3D.global_transform`), not the numbers the
script keeps.

- **Approach:** In a view test, read the drawn `Camera3D`'s `global_transform` while replaying a recorded look path
  through the real input over 1/144 to 1/15 s and uneven frames, and set the parent before the child for anything placed
  by hand in `_process`. **Watch out for:** every look test read the rig's yaw, which matched the hand; the camera set
  its child's global transform and then moved its `top_level` parent, so the lens drew one step of the last turn ahead
  (33 to 133 degrees off at the worst frame). **Seen:** Deadnight #905, 2026-11-03 (fix: the parent is placed first
  ([lesson](../../lessons/2026-11-03-the-drawn-camera-ran-a-step-ahead-of-the-mouse.md))).

## How to measure it {#how-to-measure-it}

- Replay one recorded path (whole pixels, one per millisecond, seeded) through the real input path
  (`Input.parse_input_event`, the player's own `_unhandled_input`) while the frame rate is held at 144, 60, 30 and 15
  (`Engine.max_fps`) and hitched (`OS.delay_msec` in every nth frame). Headless is enough; nothing here is drawn, but
  there is no `frame_post_draw` either, so write the rows from a `_process` at a late `process_priority`.
- Per frame, write the rig's yaw **and** the camera's own (`camera.global_transform.basis.get_euler(EULER_ORDER_YXZ).y`),
  the frame length, the physics ticks it ran and the path posted so far. Compare the camera with what the hand asked
  for: the biggest distance, the frames that moved against the hand, the frames that moved with no mouse, the RMS of
  (drawn step - hand step).
- A deterministic test steps the rig by hand (`rig.step(length, fraction)`) with the same events, over frame lengths
  of 1/144, 1/60, 1/30, 1/15 s and a seeded uneven run, and asserts the drawn yaw equals the rig's, no frame turns
  against the hand, and every rate ends at the same total. Do the same online (a client of a game server, added to the
  window's own tree: a `SubViewport` does not get the window's input, so the test would pass on a player that heard
  nothing; assert the player turned at all).

- **Approach:** Measure per-frame motion in a child Godot run at `--fixed-fps`, with control cases that must fail.
  **Watch out for:** a smoothness test measured frames timed by the real clock and failed on busy machines, turning
  `main` red. **Seen:** Deadnight #362, 2026-11-01 (fix: main's CI and a local run showed it
  ([lesson](../../lessons/2026-11-01-a-smoothness-test-read-the-real-clock.md))).

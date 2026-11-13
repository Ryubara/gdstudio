# Input in UI tests

<!-- new section: ui-controls.md is at the size limit and its "Menus under test" section grew into a topic of its own: how
a GdUnit4 suite sends mouse, touch, pad and key events to a screen, and what one suite leaves for the next -->

How to put real input through a menu, a HUD or a touch layer in a test, and how to keep a suite from changing the
result of the next one. The controls themselves are in [UI controls](ui-controls.md) (its [Menus under
test](ui-controls.md#menus-under-test) section holds the headless mouse and the router rules); layout checks are in
[UI layout](ui-layout.md); a value that time drives is in [Test speed](test-speed.md#time-driven-values).

## Sending the event {#sending}

<!-- new section: ui-controls.md has the headless mouse; nothing covered pad presses, buffering or taps in a suite -->

- **Approach:** Send pad, key and mouse events to a screen with `get_viewport().push_input(event)` (press and release a
  frame apart), and wait for the router to be idle in `before_test` when it is busy. **Watch out for:** a test that sent
  `InputEventJoypadButton` presses with `Input.parse_input_event` moved a selection three times alone and once in the
  full run: the `Input` singleton keeps which buttons are held across suites, and the router swallows input while a
  transition runs. **Seen:** Deadnight, 2026-11-01 (fix: `push_input` and a wait for the idle router).
- **Approach:** Call `Input.flush_buffered_events()` before and after parsing an event whose `device` or origin
  matters, so it is delivered alone and at once. **Watch out for:** `Input.parse_input_event` buffers events until the
  next frame and, with accumulated input on, adds a mouse motion to the previous buffered one when buttons and modifiers
  match, keeping the first event's `device`: a stray browser motion already waiting absorbed the touch layer's tagged
  motion, and the player ignored the sum as a stray. **Seen:** Deadnight #598, 2026-11-02 (fix: flush around the
  parse).
- **Approach:** After lifting a finger in a test, wait frames (bounded) until `Input.is_action_pressed(action)` is
  false, then tap again. **Watch out for:** the touch layer holds a short tap down for a minimum press and releases it
  on frames; a second tap with no frame between made no new press edge, so a test that tapped Melee twice read one
  press. **Seen:** Deadnight #588, 2026-11-02 (fix: the test waits for the release, as the frames of a real night do).

## Edges {#edges}

<!-- new section: a press that counts once is a per-tick edge, and a test can lose it by reading it twice; no page
covered it -->

- **Approach:** Keep a per-tick edge in the player: remember whether the action was down last tick and report the
  rising edge once. **Watch out for:** `Input.is_action_just_pressed` read on a physics tick can report a press that
  lands between ticks on two consecutive ticks, and pairing it with an `_unhandled_input` flag counted the same press
  again, so one key press gave two shoulder swaps. **Seen:** Deadnight, 2026-11-01 (fix: the player's own edge, the
  same code headless, where GdUnit4 carries actions but no mouse motion).
- **Approach:** Count a press from the controller's flag, and from the held button going down when no flag came with
  it; then a flag that comes after a press already counted from the button is no second press
  (`Character.fire_press`, kept in the step state). Test a one-frame click and a tap under the shot interval with
  `InputSim`, counting shots. **Watch out for:** with `InputSim`
  events and `PlayerInput.sample()`, `is_action_pressed(&"fire")` was true a tick before
  `is_action_just_pressed(&"fire")`, so an automatic weapon fired on the held button and its late flag buffered a
  second shot: one click, two shots. Counting only the button going down dropped a release and press within one tick
  (`test_character_state.gd` caught it).
  **Seen:** gdstudio #1335, 2026-11-12 (tests `test_fire_count.gd`, `test_net_fire_count.gd`).
- **Approach:** Read each edge source once per tick of a test loop, on every tick, and run a new edge action's row
  through two bindings in a row before trusting it. **Watch out for:** the controller keeps the last state of each
  button (`_edge`, `_was_down`), so a test that called `command()` a second time to learn the facing took the press
  from the one sent to the night, and a matrix row that read the edge only on the ticks it asserted never saw the first
  binding's release, so the second binding made no rising edge; a level (fire) hides both. A row for an action with a
  cooldown also needs ticks between its bindings. **Seen:** Deadnight #411, 2026-11-02; Deadnight #642, 2026-11-02
  (fix: the view comes from the camera rig, one `_tick_command` helper reads everything every tick).
- **Approach:** Press an action a node reads in `_unhandled_input` with an event (`Input.parse_input_event` of a
  key or an `InputEventAction`, the suites' `InputSim`), never `Input.action_press`. **Watch out for:**
  `action_press` sets the action's state and sends no event, so a node that reacts to `is_action_pressed(event)`
  (a map toggle, a zoom) never saw the capture tour's presses. **Seen:** gdstudio #884, 2026-11-10.

## What a suite leaves behind {#leaks}

<!-- new section: UI suites share the Input singleton, an autoload router and statics, and the failures show only in
another order; the menus-under-test entry covers the router alone -->

- **Approach:** When a UI input test passes alone and fails in the folder, a shard or a window, treat it as global
  state an earlier suite left and bisect to the pair: take the shard's suite list from its log, run `[leaker, victim]`,
  and print `UIRouter.depth()`, `get_viewport().gui_get_focus_owner()` and `busy` (or the added node's path and class,
  for a wrong count) before forming a theory. **Watch out for:** what is left is a held action, a mouse button, a
  router screen, a static or a setting, and the shard split moves it: a menu one suite left made a look suite read no
  turn on two unrelated pull requests, and a held scoreboard key made another suite's HUD count 43 nodes. **Seen:**
  Deadnight #1037, 2026-11-04; Deadnight, 2026-11-05 (fix: the leaking suites release in `after_test`, and a scan
  test fails a suite that shows a screen or holds an action without cleaning up).
- **Approach:** A fixture that sends input through the `Input` singleton lets go of everything it may have pressed
  when it is freed (mouse buttons, actions, touch emulation, flushed with `Input.flush_buffered_events()`), and a scan
  that looks for presses lists every way the engine lets one be made (a call, an `InputEventAction` with `pressed`, a
  key, a touch's emulated mouse button), each shown red against one suite before it is trusted. **Watch out for:** a
  finger down on a layer that is off pressed the emulated left mouse button and `free_all` released only the actions,
  so a pad test failed after the touch suite; a scan for `Input.action_press(` missed three suites that pressed with
  events and never released. **Seen:** Deadnight #456, 2026-11-02; Deadnight, 2026-11-05 (fix: `free_all` releases
  the mouse, `InputFixture.release_all()`, and the scan counts events).
- **Approach:** A test that sends a finger with `Input.parse_input_event` lifts the finger and the left button itself
  before it ends, and a gameplay suite starts with `InputSim.release_all()` in `before_test` (a held left button is
  `fire`). **Watch out for:** with emulation on, the finger also pressed the left button; the touch layer then turned
  emulation off, so lifting the finger would send no release. The flake was blamed on machine load because full runs
  are made on a loaded machine, but the pair failed every time on an idle one. **Seen:** gdstudio #1357, 2026-11-12
  (3D Blank's `test_touch_controls.gd` left the button down through five suites; the 3D Third Person player fired as
  `test_ai_section.gd` began and its guard turned to the shot behind it).
- **Approach:** A release-all records what the fixture pressed and lets go of exactly that, never a typed list of the
  usual keys; when CI shuffles the suite order, name what is down before guessing (a probe suite run last that prints
  each pressed key, action, mouse mask and pad button), then run `[leaker, victim]`. **Watch out for:** the kit's
  `InputSim.release_all()` released ten named keys, so a suite that held Y left it down though it released in
  `after_test`, and `Input.is_anything_pressed()` failed 141 times in a suite 58 places later, on two unrelated pull
  requests and on `main` in that order; two suites that pressed with `Input.action_press` were suspected first and
  were clean. **Seen:** gdstudio #1274 and #1171, 2026-11-12 (`test_player_input.gd` before `test_character_split.gd`;
  fix: `InputSim` keeps what it pressed); gdstudio #1315, 2026-11-12 (the same pair on a CI rerun).
- **Approach:** A helper that writes a static or a global (the device as touch, the opener a stub replaced, the join
  address a lobby fills) restores it in the same change that adds the write, and a suite that stubs the step which
  would consume a static clears it in `after_test`. **Watch out for:** `UiFitRun.set_window` set the device as touch
  and `restore()` did not, so every suite after a phone-page case ran as a touch device; a lobby suite left the join
  address set, and the next solo night joined a server that was not there and waited five minutes on a signal with no
  timeout. **Seen:** Deadnight #1243, 2026-11-05; Deadnight, 2026-11-05 (fix: begin saves, restore puts back, and a test
  fails if it stays set; `RouterFixture.forget_join()`).

## Touch {#touch}

<!-- new section: ui-controls.md has the touch layer's design rules; the state a touch layer keeps while it is off had
no home -->

- **Approach:** Any layer, screen or mode that stops reading input and starts again says what happens to a pointer
  that is down across the gap, and has a test with the press before the gap and the drag after it. **Watch out for:** a
  layer that returns early from `_input` while off learns of a finger only by its press, and Godot cannot list which
  fingers are down, so a finger that went down or stayed down across the helicopter drop turned nothing for the rest of
  its life (10 drags of 20 units: 0.0 pixels). **Seen:** Deadnight #1320, 2026-11-06 (fix: the fingers are kept while
  off from the events, and taken in when it is on again: the stick's zone makes a stick, anything else looks).

## Browser probes {#probes}

<!-- new section: scripted browser input has two traps of its own, key timing and units, and no page for the pad and
touch tests held them -->

- **Approach:** Hold a key for about 150 ms in a browser test, and after Back press a focus key (Down, Up, Up) before
  Enter. **Watch out for:** Godot reads input once per frame, so a press and release inside one frame can be lost, and
  after a screen is popped nothing has focus and the router spends the first arrow or accept key on giving it.
  **Seen:** Deadnight, 2026-11-01 (fix: held keys and a focus key in the web smoke).
- **Approach:** Have a capture script assert the state it claims (a probe's `touch_held` names what the layer thinks is
  down), look at the frame of every "held" capture before it is evidence, and read a script inherited from another
  agent instead of trusting it. **Watch out for:** a probe listed buttons as shares of the page and sent them to
  `Input.dispatchTouchEvent` as pixels (a touch at 0.19 px), so "Scoreboard held" looked exactly like the frame before
  and was filed as the held state. **Seen:** Deadnight #1275, 2026-11-05 (fix: multiply by the page's width and height).

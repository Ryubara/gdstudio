class_name InputSim
extends RefCounted
## Simulated input for the suites: real key, pad and mouse events sent through the engine's own
## input path (`Input.parse_input_event`), so the project's `InputMap` decides what each one
## does. Part of the synced `gds_game` addon: used by tests only, never by shipped code.


static func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


static func pad_button(index: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 3  # Never device 0: pads are numbered as they connect.
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


static func pad_axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 3
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()


static func mouse_button(index: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.button_mask = (1 << (index - 1)) if pressed else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()


## Lets go of everything a test pressed.
static func release_all() -> void:
	for code: Key in [
		KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE, KEY_SHIFT, KEY_X, KEY_E, KEY_C, KEY_CTRL
	]:
		key(code, false)
	for axis: JoyAxis in [
		JOY_AXIS_LEFT_X,
		JOY_AXIS_LEFT_Y,
		JOY_AXIS_RIGHT_X,
		JOY_AXIS_RIGHT_Y,
		JOY_AXIS_TRIGGER_LEFT,
		JOY_AXIS_TRIGGER_RIGHT
	]:
		pad_axis(axis, 0.0)
	pad_button(JOY_BUTTON_B, false)
	mouse_button(MOUSE_BUTTON_LEFT, false)
	mouse_button(MOUSE_BUTTON_RIGHT, false)
	# A base suite that sends a click leaves the left button and its action (`fire`) down, and a
	# mouse release does not clear the action: let go of every action of the project directly.
	for action: StringName in InputMap.get_actions():
		Input.action_release(action)
	Input.flush_buffered_events()


## Waits `count` physics frames.
static func ticks(tree: SceneTree, count: int) -> void:
	for _frame in count:
		await tree.physics_frame

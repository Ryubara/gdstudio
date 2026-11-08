class_name InputSim
extends RefCounted
## Simulated input for the suites: real key, pad and touch events sent through the engine's own
## input path (`Input.parse_input_event`), so the project's `InputMap` decides what each one
## does.


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


## Lets go of everything a test pressed.
static func release_all() -> void:
	for code: Key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE, KEY_SHIFT, KEY_X, KEY_E]:
		key(code, false)
	for axis: JoyAxis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
		pad_axis(axis, 0.0)
	Input.flush_buffered_events()


## Waits `count` physics frames.
static func ticks(tree: SceneTree, count: int) -> void:
	for _frame in count:
		await tree.physics_frame

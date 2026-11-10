# What the controls screen needs of the InputMap: a binding's device, its name, its form in a
# settings file (never an Object, and a bad one is refused), rebinding with a swap, and which
# presses bind.
extends GdUnitTestSuite

const ACTION_A := &"test_bind_a"
const ACTION_B := &"test_bind_b"
const AMONG: Array[StringName] = [ACTION_A, ACTION_B]


func before_test() -> void:
	for action in AMONG:
		InputMap.add_action(action)
	InputMap.action_add_event(ACTION_A, _key(KEY_Q))
	InputMap.action_add_event(ACTION_A, _key(KEY_LEFT))
	InputMap.action_add_event(ACTION_A, _pad(JOY_BUTTON_X))
	InputMap.action_add_event(ACTION_B, _key(KEY_R))
	InputMap.action_add_event(ACTION_B, _pad(JOY_BUTTON_Y))


func after_test() -> void:
	for action in AMONG:
		InputMap.erase_action(action)


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event


func _pad(index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	return event


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


func _click(index: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index
	return event


func test_a_binding_belongs_to_the_keyboard_or_to_a_pad() -> void:
	assert_int(InputBindings.device_of(_key(KEY_A))).is_equal(InputBindings.Device.KEYBOARD)
	assert_int(InputBindings.device_of(_click(MOUSE_BUTTON_LEFT))).is_equal(
		InputBindings.Device.KEYBOARD
	)
	assert_int(InputBindings.device_of(_pad(JOY_BUTTON_A))).is_equal(InputBindings.Device.GAMEPAD)
	assert_int(InputBindings.device_of(_axis(JOY_AXIS_TRIGGER_LEFT, 1.0))).is_equal(
		InputBindings.Device.GAMEPAD
	)
	assert_int(InputBindings.device_of(InputEventMouseMotion.new())).is_equal(-1)


func test_the_events_of_an_action_split_by_device_keep_their_order() -> void:
	var keys := InputBindings.events_of(ACTION_A, InputBindings.Device.KEYBOARD)
	assert_int(keys.size()).is_equal(2)
	assert_int((keys[0] as InputEventKey).physical_keycode).is_equal(KEY_Q)
	assert_int((keys[1] as InputEventKey).physical_keycode).is_equal(KEY_LEFT)
	assert_int(InputBindings.events_of(ACTION_A, InputBindings.Device.GAMEPAD).size()).is_equal(1)
	assert_int(InputBindings.events_of(&"no_such", InputBindings.Device.KEYBOARD).size()).is_zero()


func test_names_a_player_can_read() -> void:
	assert_str(InputBindings.label_of(_pad(JOY_BUTTON_A))).is_equal("A")
	assert_str(InputBindings.label_of(_pad(JOY_BUTTON_RIGHT_SHOULDER))).is_equal("Right bumper")
	assert_str(InputBindings.label_of(_click(MOUSE_BUTTON_RIGHT))).is_equal("Right mouse button")
	assert_str(InputBindings.label_of(_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0))).is_equal("Right trigger")
	assert_str(InputBindings.label_of(_axis(JOY_AXIS_LEFT_Y, -1.0))).is_equal("Left stick up")
	assert_str(InputBindings.label_of(_axis(JOY_AXIS_RIGHT_X, 1.0))).is_equal("Right stick right")
	assert_str(InputBindings.label_of(_key(KEY_SPACE))).is_not_empty()


func test_every_kind_of_binding_survives_the_form_a_file_holds() -> void:
	for event: InputEvent in [
		_key(KEY_F5),
		_click(MOUSE_BUTTON_MIDDLE),
		_pad(JOY_BUTTON_START),
		_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0),
		_axis(JOY_AXIS_LEFT_X, -1.0),
	]:
		var data := InputBindings.to_data(event)
		var back := InputBindings.event_from_data(data)
		assert_object(back).is_not_null()
		(
			assert_bool(InputBindings.same_control(event, back))
			. override_failure_message(str(data))
			. is_true()
		)
		assert_bool(data.values().any(func(v: Variant) -> bool: return v is Object)).is_false()


func test_data_that_is_not_a_binding_is_refused() -> void:
	for bad: Variant in [
		null,
		"jump",
		42,
		[],
		{},
		{"type": "bogus"},
		{"type": "key"},
		{"type": "key", "code": -3},
		{"type": "key", "code": 1 << 30},
		{"type": "key", "code": "A"},
		{"type": "key", "code": NAN},
		{"type": "mouse", "button": 99},
		{"type": "mouse", "button": 0},
		{"type": "pad_button", "button": -1},
		{"type": "pad_button", "button": 4000},
		{"type": "pad_axis", "axis": 50},
		{"type": "pad_axis"},
	]:
		(
			assert_object(InputBindings.event_from_data(bad))
			. override_failure_message(str(bad))
			. is_null()
		)


func test_a_stick_direction_is_one_control_and_the_other_direction_another() -> void:
	(
		assert_bool(
			InputBindings.same_control(_axis(JOY_AXIS_LEFT_X, 0.8), _axis(JOY_AXIS_LEFT_X, 1.0))
		)
		. is_true()
	)
	(
		assert_bool(
			InputBindings.same_control(_axis(JOY_AXIS_LEFT_X, 0.8), _axis(JOY_AXIS_LEFT_X, -1.0))
		)
		. is_false()
	)
	assert_bool(InputBindings.same_control(_key(KEY_Q), _pad(JOY_BUTTON_A))).is_false()


func test_rebinding_replaces_the_first_binding_of_the_device_and_keeps_the_others() -> void:
	var swapped := InputBindings.rebind(ACTION_A, _key(KEY_F), AMONG)
	assert_str(str(swapped)).is_empty()
	var keys := InputBindings.events_of(ACTION_A, InputBindings.Device.KEYBOARD)
	assert_int(keys.size()).is_equal(2)
	assert_int((keys[0] as InputEventKey).physical_keycode).is_equal(KEY_F)
	assert_int((keys[1] as InputEventKey).physical_keycode).is_equal(KEY_LEFT)
	# The pad's binding is untouched.
	assert_int(InputBindings.events_of(ACTION_A, InputBindings.Device.GAMEPAD).size()).is_equal(1)


func test_a_control_another_action_uses_is_swapped_over() -> void:
	var swapped := InputBindings.rebind(ACTION_A, _key(KEY_R), AMONG)
	assert_str(str(swapped)).is_equal(str(ACTION_B))
	var mine := InputBindings.events_of(ACTION_A, InputBindings.Device.KEYBOARD)
	var theirs := InputBindings.events_of(ACTION_B, InputBindings.Device.KEYBOARD)
	assert_int((mine[0] as InputEventKey).physical_keycode).is_equal(KEY_R)
	assert_int((theirs[0] as InputEventKey).physical_keycode).is_equal(KEY_Q)


func test_binding_a_second_binding_of_the_same_action_does_not_double_it() -> void:
	InputBindings.rebind(ACTION_A, _key(KEY_LEFT), AMONG)
	var keys := InputBindings.events_of(ACTION_A, InputBindings.Device.KEYBOARD)
	assert_int(keys.size()).is_equal(1)
	assert_int((keys[0] as InputEventKey).physical_keycode).is_equal(KEY_LEFT)


func test_an_action_the_map_lacks_is_not_rebound() -> void:
	var swapped := InputBindings.rebind(&"no_such_action", _key(KEY_F), AMONG)
	assert_str(str(swapped)).is_empty()
	assert_bool(InputMap.has_action(&"no_such_action")).is_false()


func test_which_presses_can_be_bound() -> void:
	var press := _key(KEY_G)
	press.pressed = true
	assert_bool(InputBindings.is_bindable_press(press)).is_true()
	press.echo = true
	assert_bool(InputBindings.is_bindable_press(press)).is_false()
	var escape := _key(KEY_ESCAPE)
	escape.pressed = true
	assert_bool(InputBindings.is_bindable_press(escape)).is_false()
	var release := _key(KEY_G)
	release.pressed = false
	assert_bool(InputBindings.is_bindable_press(release)).is_false()
	assert_bool(InputBindings.is_bindable_press(_axis(JOY_AXIS_LEFT_X, 0.3))).is_false()
	assert_bool(InputBindings.is_bindable_press(_axis(JOY_AXIS_LEFT_X, 0.9))).is_true()
	assert_bool(InputBindings.is_bindable_press(InputEventMouseMotion.new())).is_false()


func test_an_event_for_the_map_answers_every_device_and_keeps_nothing_of_the_press() -> void:
	var press := _pad(JOY_BUTTON_B)
	press.device = 3
	press.pressed = true
	var copy := InputBindings.for_map(press) as InputEventJoypadButton
	assert_int(copy.device).is_equal(-1)
	assert_bool(copy.pressed).is_false()
	var push := _axis(JOY_AXIS_RIGHT_Y, -0.7)
	push.device = 2
	var stick := InputBindings.for_map(push) as InputEventJoypadMotion
	assert_float(stick.axis_value).is_equal(-1.0)
	assert_int(stick.device).is_equal(-1)

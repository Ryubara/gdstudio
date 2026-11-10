# Rebinding on the settings screen: pressing a binding takes the next real key, mouse button or
# pad button through the input path, Escape cancels the wait without leaving the screen, a control
# in use is swapped, and a reset gives the default keys back.
extends GdUnitTestSuite

const SETTINGS := "res://ui/menus/settings_menu.tscn"

var _screen: SettingsMenu


func before_test() -> void:
	InputMap.load_from_project_settings()
	Settings.reset_defaults()
	UIMotion.reduced = true
	UIRouter.reset(SETTINGS, UITransition.Kind.CUT)
	assert_bool(await MenuFixture.settle(get_tree())).is_true()
	_screen = UIRouter.top() as SettingsMenu


func after_test() -> void:
	InputSim.release_all()
	UIMotion.reduced = false
	await MenuFixture.clear(get_tree())
	Settings.reset_defaults()
	InputMap.load_from_project_settings()


func _tap(key: Key) -> void:
	InputSim.key(key, true)
	InputSim.key(key, false)


func _controls() -> ControlsPage:
	_screen.select_tab(2, false)
	return _screen.get_node("%ControlsPage") as ControlsPage


func _rebind_row(action: StringName) -> RebindRow:
	for row in _controls().rebind_rows():
		if row.action == action:
			return row
	return null


func test_the_controls_page_has_a_row_for_every_action_it_lists() -> void:
	var page := _controls()
	assert_int(page.rebind_rows().size()).is_equal(page.actions.size())
	var jump := _rebind_row(&"jump")
	assert_str(jump.buttons()[0].text).is_equal(
		InputBindings.label_of(InputBindings.events_of(&"jump", 0)[0])
	)
	assert_str(jump.buttons()[1].text).is_equal("A")


func test_pressing_a_binding_then_a_key_rebinds_it_and_saves_it_in_the_service() -> void:
	var row := _rebind_row(&"jump")
	row.buttons()[0].pressed.emit()
	assert_bool(row.is_listening()).is_true()
	assert_str(row.buttons()[0].text).is_equal(RebindRow.WAITING)
	_tap(KEY_F)
	assert_bool(row.is_listening()).is_false()
	var keys := InputBindings.events_of(&"jump", InputBindings.Device.KEYBOARD)
	assert_int((keys[0] as InputEventKey).physical_keycode).is_equal(KEY_F)
	assert_str(row.buttons()[0].text).is_equal(InputBindings.label_of(keys[0]))
	assert_bool(Settings.is_rebound(&"jump", InputBindings.Device.KEYBOARD)).is_true()


func test_the_next_press_of_the_other_device_does_not_bind_to_this_button() -> void:
	var row := _rebind_row(&"jump")
	row.buttons()[0].pressed.emit()
	InputSim.pad_button(JOY_BUTTON_Y, true)
	InputSim.pad_button(JOY_BUTTON_Y, false)
	assert_bool(row.is_listening()).is_true()
	_tap(KEY_G)
	assert_bool(row.is_listening()).is_false()
	var pads := InputBindings.events_of(&"jump", InputBindings.Device.GAMEPAD)
	assert_int((pads[0] as InputEventJoypadButton).button_index).is_equal(JOY_BUTTON_A)


func test_the_pad_button_binds_from_a_pad_that_is_not_device_zero() -> void:
	var row := _rebind_row(&"crouch")
	row.buttons()[1].pressed.emit()
	InputSim.pad_button(JOY_BUTTON_X, true)
	InputSim.pad_button(JOY_BUTTON_X, false)
	var pads := InputBindings.events_of(&"crouch", InputBindings.Device.GAMEPAD)
	assert_int((pads[0] as InputEventJoypadButton).button_index).is_equal(JOY_BUTTON_X)
	assert_int(pads[0].device).is_equal(-1)


func test_a_mouse_button_binds_too() -> void:
	var row := _rebind_row(&"interact")
	row.buttons()[0].pressed.emit()
	InputSim.mouse_button(MOUSE_BUTTON_MIDDLE, true)
	InputSim.mouse_button(MOUSE_BUTTON_MIDDLE, false)
	var keys := InputBindings.events_of(&"interact", InputBindings.Device.KEYBOARD)
	assert_object(keys[0]).is_instanceof(InputEventMouseButton)
	assert_str(row.buttons()[0].text).is_equal("Middle mouse button")


func test_escape_cancels_the_wait_and_does_not_leave_the_screen() -> void:
	UIRouter.reset("res://ui/menus/main_menu.tscn", UITransition.Kind.CUT)
	UIRouter.push(SETTINGS, UITransition.Kind.CUT)
	await MenuFixture.settle(get_tree())
	_screen = UIRouter.top() as SettingsMenu
	var row := _rebind_row(&"jump")
	var was := InputBindings.events_of(&"jump", InputBindings.Device.KEYBOARD)[0]
	row.buttons()[0].pressed.emit()
	assert_bool(_screen.allow_back).is_false()
	_tap(KEY_ESCAPE)
	await MenuFixture.settle(get_tree())
	assert_bool(row.is_listening()).is_false()
	assert_int(UIRouter.depth()).is_equal(2)
	assert_bool(_screen.allow_back).is_true()
	(
		assert_bool(
			InputBindings.same_control(
				was, InputBindings.events_of(&"jump", InputBindings.Device.KEYBOARD)[0]
			)
		)
		. is_true()
	)


func test_a_control_already_used_is_swapped_and_both_rows_show_it() -> void:
	var jump := _rebind_row(&"jump")
	var sprint := _rebind_row(&"sprint")
	jump.buttons()[0].pressed.emit()
	_tap(KEY_SHIFT)
	assert_str(jump.buttons()[0].text).is_equal(
		InputBindings.label_of(InputBindings.events_of(&"jump", 0)[0])
	)
	assert_str(sprint.buttons()[0].text).is_equal(
		InputBindings.label_of(InputBindings.events_of(&"sprint", 0)[0])
	)
	assert_str(sprint.buttons()[0].text).is_not_equal(jump.buttons()[0].text)


func test_reset_gives_the_default_keys_back_and_the_rows_say_so() -> void:
	var row := _rebind_row(&"jump")
	row.buttons()[0].pressed.emit()
	_tap(KEY_F)
	(_screen.get_node("%ResetButton") as Button).pressed.emit()
	var keys := InputBindings.events_of(&"jump", InputBindings.Device.KEYBOARD)
	assert_int((keys[0] as InputEventKey).physical_keycode).is_equal(KEY_SPACE)
	assert_str(row.buttons()[0].text).is_equal(InputBindings.label_of(keys[0]))

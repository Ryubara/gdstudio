# Rebinding through the Settings service: the new control is in the InputMap at once, a swapped
# action keeps what the other gave up, the change is saved and applied again at the next start, a
# reset gives the project's own bindings back, and a damaged entry in the file is skipped.
extends GdUnitTestSuite

const SCENE := "res://core/settings/settings.tscn"
const TEMP_PATH := "user://settings_bindings_test.cfg"
const AMONG: Array[StringName] = [&"jump", &"sprint", &"fire"]

var _service: SettingsService


func before_test() -> void:
	InputMap.load_from_project_settings()
	_service = _make()


func after_test() -> void:
	InputMap.load_from_project_settings()
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(TEMP_PATH)


func _make(path := "") -> SettingsService:
	var service := load(SCENE).instantiate() as SettingsService
	service.path = path
	add_child(service)
	return auto_free(service)


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event


func _first_key(action: StringName) -> int:
	var events := InputBindings.events_of(action, InputBindings.Device.KEYBOARD)
	return (events[0] as InputEventKey).physical_keycode if not events.is_empty() else -1


func test_a_rebound_action_answers_its_new_key_and_not_the_old_one() -> void:
	assert_int(_first_key(&"jump")).is_equal(KEY_SPACE)
	_service.rebind(&"jump", _key(KEY_F), AMONG)
	assert_int(_first_key(&"jump")).is_equal(KEY_F)
	var press := _key(KEY_F)
	press.pressed = true
	assert_bool(InputMap.event_is_action(press, &"jump")).is_true()
	var old := _key(KEY_SPACE)
	old.pressed = true
	assert_bool(InputMap.event_is_action(old, &"jump")).is_false()
	assert_bool(_service.is_rebound(&"jump", InputBindings.Device.KEYBOARD)).is_true()
	assert_bool(_service.is_rebound(&"jump", InputBindings.Device.GAMEPAD)).is_false()


func test_the_pad_binding_changes_without_touching_the_keyboard_one() -> void:
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_Y
	pad.device = 4
	pad.pressed = true
	_service.rebind(&"jump", pad, AMONG)
	var events := InputBindings.events_of(&"jump", InputBindings.Device.GAMEPAD)
	assert_int((events[0] as InputEventJoypadButton).button_index).is_equal(JOY_BUTTON_Y)
	# A binding the map holds answers every device, not only the pad that was pressed.
	assert_int(events[0].device).is_equal(-1)
	assert_int(_first_key(&"jump")).is_equal(KEY_SPACE)


func test_a_control_in_use_is_swapped_and_both_actions_are_saved() -> void:
	var swapped := _service.rebind(&"jump", _key(KEY_SHIFT), AMONG)
	assert_str(str(swapped)).is_equal("sprint")
	assert_int(_first_key(&"jump")).is_equal(KEY_SHIFT)
	assert_int(_first_key(&"sprint")).is_equal(KEY_SPACE)
	assert_bool(_service.is_rebound(&"sprint", InputBindings.Device.KEYBOARD)).is_true()


func test_a_rebinding_is_announced() -> void:
	var count := [0]
	_service.bindings_changed.connect(func() -> void: count[0] += 1)
	_service.rebind(&"jump", _key(KEY_F), AMONG)
	assert_int(count[0]).is_equal(1)


func test_rebinding_is_saved_and_applied_at_the_next_start() -> void:
	var first := _make(TEMP_PATH)
	first.rebind(&"jump", _key(KEY_F), AMONG)
	first.rebind(&"fire", _key(KEY_G), AMONG)
	assert_int(first.save()).is_equal(OK)
	InputMap.load_from_project_settings()
	assert_int(_first_key(&"jump")).is_equal(KEY_SPACE)
	_make(TEMP_PATH)
	assert_int(_first_key(&"jump")).is_equal(KEY_F)
	assert_int(_first_key(&"fire")).is_equal(KEY_G)
	# What the player did not touch stays as the project declared it.
	assert_int(_first_key(&"sprint")).is_equal(KEY_SHIFT)


func test_reset_gives_the_projects_own_bindings_back() -> void:
	_service.rebind(&"jump", _key(KEY_F), AMONG)
	_service.rebind(&"sprint", _key(KEY_SPACE), AMONG)
	_service.reset_bindings()
	assert_int(_first_key(&"jump")).is_equal(KEY_SPACE)
	assert_int(_first_key(&"sprint")).is_equal(KEY_SHIFT)
	assert_bool(_service.is_rebound(&"jump", InputBindings.Device.KEYBOARD)).is_false()
	var count := InputMap.action_get_events(&"jump").size()
	assert_int(count).is_equal(2)


func test_reset_defaults_resets_the_bindings_too() -> void:
	_service.rebind(&"jump", _key(KEY_F), AMONG)
	_service.reset_defaults()
	assert_int(_first_key(&"jump")).is_equal(KEY_SPACE)


func test_a_damaged_binding_in_the_file_is_skipped_and_the_good_ones_apply() -> void:
	var file := ConfigFile.new()
	file.set_value("bindings", "jump.keys", [{"type": "bogus"}])
	file.set_value("bindings", "sprint.keys", "not a list")
	file.set_value("bindings", "fire.keys", [{"type": "key", "code": KEY_H, "physical": true}])
	file.set_value("bindings", "no_such_action.keys", [{"type": "key", "code": KEY_J}])
	file.set_value("bindings", "interact.elsewhere", [{"type": "key", "code": KEY_K}])
	file.save(TEMP_PATH)
	_make(TEMP_PATH)
	assert_int(_first_key(&"jump")).is_equal(KEY_SPACE)
	assert_int(_first_key(&"sprint")).is_equal(KEY_SHIFT)
	assert_int(_first_key(&"fire")).is_equal(KEY_H)
	assert_int(_first_key(&"interact")).is_equal(KEY_E)
	assert_bool(InputMap.has_action(&"no_such_action")).is_false()


func test_an_unbound_control_in_the_file_is_kept_unbound() -> void:
	var file := ConfigFile.new()
	file.set_value("bindings", "walk.keys", [])
	file.save(TEMP_PATH)
	_make(TEMP_PATH)
	assert_int(InputBindings.events_of(&"walk", InputBindings.Device.KEYBOARD).size()).is_zero()


func test_the_template_actions_are_in_the_map_for_the_controls_page() -> void:
	for action: StringName in (auto_free(ControlsPage.new()) as ControlsPage).actions:
		assert_bool(InputMap.has_action(action)).override_failure_message(str(action)).is_true()

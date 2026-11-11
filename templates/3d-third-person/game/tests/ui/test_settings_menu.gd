# The settings screen: each row shows the saved value and sends a change to Settings, a reset puts
# the screen and the service back, the tabs switch with their focus, and rebinding takes the next
# real key, mouse button or pad button through the input path and lets Escape cancel it.
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
	CameraShake.strength = 1.0
	AudioSettings.reset_player_gain()
	get_tree().root.scaling_3d_scale = 1.0
	InputMap.load_from_project_settings()


func _row(row_name: String) -> SettingRow:
	return _screen.find_child(row_name, true, false) as SettingRow


func _tap(key: Key) -> void:
	InputSim.key(key, true)
	InputSim.key(key, false)


func test_the_screen_has_three_tabs_and_starts_on_video_with_the_first_tab_focused() -> void:
	assert_int(_screen.current_tab()).is_zero()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(_screen.get_node("%VideoTab"))
	assert_bool(_screen.get_node("%VideoPage").visible).is_true()
	assert_bool(_screen.get_node("%AudioPage").visible).is_false()


func test_a_slider_row_shows_the_saved_value_and_its_number() -> void:
	Settings.set_value(SettingsService.VOLUME_SFX, 35)
	var row := _row("Effects")
	assert_float((row.control as UISlider).value).is_equal(35.0)
	row.refresh()
	assert_float((row.control as UISlider).value).is_equal(35.0)


func test_moving_a_slider_sets_the_value_and_applies_it() -> void:
	_screen.select_tab(1, false)
	var slider := _row("Effects").control as UISlider
	slider.value = 40.0
	assert_int(Settings.get_value(SettingsService.VOLUME_SFX)).is_equal(40)
	assert_float(AudioSettings.player_gain(&"SFX")).is_equal_approx(0.4, 0.0001)


func test_every_audio_row_drives_its_own_bus() -> void:
	_screen.select_tab(1, false)
	var rows := {
		"Master": [SettingsService.VOLUME_MASTER, &"Master"],
		"Effects": [SettingsService.VOLUME_SFX, &"SFX"],
		"Ambient": [SettingsService.VOLUME_AMBIENT, &"Ambient"],
		"Interface": [SettingsService.VOLUME_UI, &"UI"],
	}
	for row_name: String in rows:
		(_row(row_name).control as UISlider).value = 25.0
		(
			assert_float(AudioSettings.player_gain(rows[row_name][1]))
			. override_failure_message(row_name)
			. is_equal_approx(0.25, 0.0001)
		)
		assert_int(Settings.get_value(rows[row_name][0])).is_equal(25)


func test_a_toggle_sets_its_value() -> void:
	_screen.select_tab(2, false)
	var toggle := _row("InvertY").control as UIToggle
	toggle.button_pressed = true
	assert_bool(Settings.get_value(SettingsService.INVERT_Y)).is_true()
	toggle.button_pressed = false
	assert_bool(Settings.get_value(SettingsService.INVERT_Y)).is_false()


func test_the_camera_shake_slider_sets_the_global_strength() -> void:
	_screen.select_tab(2, false)
	var row := _row("CameraShake")
	assert_str(row.key).is_equal(String(SettingsService.CAMERA_SHAKE))
	var slider := row.control as UISlider
	assert_float(slider.value).is_equal(100.0)
	slider.value = 30.0
	assert_int(Settings.get_value(SettingsService.CAMERA_SHAKE)).is_equal(30)
	assert_float(CameraShake.strength).is_equal_approx(0.3, 0.0001)
	slider.value = 0.0
	assert_float(CameraShake.strength).is_equal(0.0)


func test_the_camera_shake_slider_turns_down_with_a_key_and_sits_under_the_look_rows() -> void:
	_screen.select_tab(2, false)
	var slider := _row("CameraShake").control as UISlider
	slider.grab_focus()
	await get_tree().process_frame
	_tap(KEY_LEFT)
	await get_tree().process_frame
	assert_int(Settings.get_value(SettingsService.CAMERA_SHAKE)).is_equal(95)
	assert_float(CameraShake.strength).is_equal_approx(0.95, 0.0001)
	var order := _screen.get_node("%ControlsPage").get_children().map(
		func(row: Node) -> String: return String(row.name)
	)
	assert_int(order.find("CameraShake")).is_equal(order.find("InvertY") + 1)


func test_the_quality_selector_lists_the_presets_and_sets_the_step() -> void:
	var selector := _row("Quality").control as UIOptionSelector
	assert_array(Array(selector.options)).is_equal(["Low", "Medium", "High"])
	selector.select(0, false)
	selector.selected_changed.emit(0)
	assert_int(Settings.get_value(SettingsService.QUALITY)).is_equal(0)
	selector.selected_changed.emit(1)
	assert_int(Settings.get_value(SettingsService.QUALITY)).is_equal(1)


func test_the_window_mode_and_vsync_rows_are_there_on_a_computer() -> void:
	assert_bool(_row("WindowMode").visible).is_equal(not OS.has_feature("web"))
	assert_bool(_row("Vsync").visible).is_equal(not OS.has_feature("web"))


func test_a_change_made_elsewhere_moves_the_row() -> void:
	Settings.set_value(SettingsService.RESOLUTION_SCALE, 65)
	assert_float((_row("ResolutionScale").control as UISlider).value).is_equal(65.0)


func test_the_selector_shows_the_option_nearest_a_hand_edited_value() -> void:
	var row := _row("Quality")
	Settings.set_value(SettingsService.QUALITY, 2)
	assert_int((row.control as UIOptionSelector).selected).is_equal(2)
	assert_int(row._index_of(0.4)).is_equal(0)
	assert_int(row._index_of(1.6)).is_equal(2)


func test_reset_puts_the_service_and_the_rows_back() -> void:
	Settings.set_value(SettingsService.RESOLUTION_SCALE, 55)
	Settings.set_value(SettingsService.INVERT_Y, true)
	(_screen.get_node("%ResetButton") as Button).pressed.emit()
	assert_float((_row("ResolutionScale").control as UISlider).value).is_equal(100.0)
	assert_bool((_row("InvertY").control as UIToggle).button_pressed).is_false()
	assert_int(Settings.get_value(SettingsService.RESOLUTION_SCALE)).is_equal(100)


func test_a_tab_switch_shows_its_page_and_keeps_the_focus_on_the_strip() -> void:
	_screen.select_tab(2, false)
	assert_int(_screen.current_tab()).is_equal(2)
	assert_bool(_screen.get_node("%ControlsPage").visible).is_true()
	assert_bool(_screen.get_node("%VideoPage").visible).is_false()
	(_screen.get_node("%AudioTab") as Button).grab_focus()
	_screen.select_tab(1, false)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(_screen.get_node("%AudioTab"))


func test_back_leaves_the_screen_when_it_is_not_the_only_one() -> void:
	UIRouter.reset("res://ui/menus/main_menu.tscn", UITransition.Kind.CUT)
	UIRouter.push(SETTINGS, UITransition.Kind.CUT)
	await MenuFixture.settle(get_tree())
	assert_int(UIRouter.depth()).is_equal(2)
	_tap(KEY_ESCAPE)
	await MenuFixture.settle(get_tree())
	assert_int(UIRouter.depth()).is_equal(1)
	assert_object(UIRouter.top()).is_instanceof(MainMenu)


func test_the_back_button_pops_the_screen() -> void:
	UIRouter.reset("res://ui/menus/main_menu.tscn", UITransition.Kind.CUT)
	UIRouter.push(SETTINGS, UITransition.Kind.CUT)
	await MenuFixture.settle(get_tree())
	(UIRouter.top().get_node("%BackButton") as Button).pressed.emit()
	await MenuFixture.settle(get_tree())
	assert_object(UIRouter.top()).is_instanceof(MainMenu)

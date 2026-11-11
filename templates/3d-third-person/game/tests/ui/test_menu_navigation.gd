# Every menu can be used without a mouse: from the control that has the focus when a screen opens,
# the four directions reach every control on the screen and lead back, and the real keys and pad
# buttons (the d-pad, accept, back) walk the same road. No focus dead ends.
extends GdUnitTestSuite

const SCREENS := {
	"main menu": "res://ui/menus/main_menu.tscn",
	"pause menu": "res://ui/menus/pause_menu.tscn",
	"settings": "res://ui/menus/settings_menu.tscn",
}

var _window_size := Vector2i.ZERO


func before_test() -> void:
	# The test window is 64 x 64: lay the screens out at the design size, as a player sees them.
	_window_size = get_window().size
	get_window().size = Vector2i(1920, 1080)
	UIMotion.reduced = true
	Settings.reset_defaults()


func after_test() -> void:
	InputSim.release_all()
	UIMotion.reduced = false
	await MenuFixture.clear(get_tree())
	get_window().size = _window_size


func _open(path: String) -> Control:
	UIRouter.reset(path, UITransition.Kind.CUT)
	assert_bool(await MenuFixture.settle(get_tree())).is_true()
	await get_tree().process_frame
	return UIRouter.top()


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


## Fails with the controls the walk from the first focus did not reach, and the ones from which the
## first focus cannot be reached again.
func _assert_no_dead_ends(screen: Control, label: String) -> void:
	var start := _focus()
	assert_object(start).override_failure_message("%s: nothing has focus" % label).is_not_null()
	var all := MenuFixture.focusables(screen)
	var reached := MenuFixture.reachable(start)
	var missed := all.filter(func(c: Control) -> bool: return c not in reached)
	(
		assert_array(missed.map(func(c: Control) -> String: return str(c.get_path())))
		. override_failure_message("%s: not reachable from %s" % [label, start.name])
		. is_empty()
	)
	var stuck := all.filter(func(c: Control) -> bool: return start not in MenuFixture.reachable(c))
	(
		assert_array(stuck.map(func(c: Control) -> String: return str(c.get_path())))
		. override_failure_message("%s: no way back to %s from these" % [label, start.name])
		. is_empty()
	)


func test_the_main_menu_has_no_dead_ends() -> void:
	var screen := await _open(SCREENS["main menu"])
	_assert_no_dead_ends(screen, "main menu")
	assert_int(MenuFixture.focusables(screen).size()).is_greater_equal(2)


func test_the_pause_menu_has_no_dead_ends() -> void:
	var screen := await _open(SCREENS["pause menu"])
	_assert_no_dead_ends(screen, "pause menu")
	assert_int(MenuFixture.focusables(screen).size()).is_equal(3)


func test_every_tab_of_the_settings_has_no_dead_ends() -> void:
	var screen := await _open(SCREENS["settings"]) as SettingsMenu
	for tab in 3:
		screen.select_tab(tab, false)
		await get_tree().process_frame
		await get_tree().process_frame
		(screen.get_node("%Tabs").get_child(tab) as Control).grab_focus()
		_assert_no_dead_ends(screen, "settings tab %d" % tab)
	# The controls tab holds the most: the four fixed rows (sensitivity, invert, camera shake, pause
	# in the inventory), a row of two buttons for each action, the three tabs and the two footer
	# buttons.
	var page: ControlsPage = screen.get_node("%ControlsPage")
	assert_int(MenuFixture.focusables(screen).size()).is_equal(
		4 + 2 * page.rebind_rows().size() + 3 + 2
	)


func test_the_keys_walk_down_the_main_menu_and_round_again() -> void:
	var screen := await _open(SCREENS["main menu"])
	var play: Control = screen.get_node("%PlayButton")
	var settings: Control = screen.get_node("%SettingsButton")
	assert_object(_focus()).is_same(play)
	InputSim.key(KEY_DOWN, true)
	InputSim.key(KEY_DOWN, false)
	assert_object(_focus()).is_same(settings)
	InputSim.key(KEY_UP, true)
	InputSim.key(KEY_UP, false)
	assert_object(_focus()).is_same(play)
	# Up from the first button reaches the last: no key ends on a button with nothing beyond it.
	InputSim.key(KEY_UP, true)
	InputSim.key(KEY_UP, false)
	assert_object(_focus()).is_not_same(play)
	InputSim.key(KEY_DOWN, true)
	InputSim.key(KEY_DOWN, false)
	assert_object(_focus()).is_same(play)


func test_the_pads_dpad_and_a_button_work_the_menu() -> void:
	var screen := await _open(SCREENS["pause menu"])
	var resume: Control = screen.get_node("%ResumeButton")
	var settings: Control = screen.get_node("%SettingsButton")
	assert_object(_focus()).is_same(resume)
	InputSim.pad_button(JOY_BUTTON_DPAD_DOWN, true)
	InputSim.pad_button(JOY_BUTTON_DPAD_DOWN, false)
	assert_object(_focus()).is_same(settings)
	InputSim.pad_button(JOY_BUTTON_A, true)
	InputSim.pad_button(JOY_BUTTON_A, false)
	await MenuFixture.settle(get_tree())
	assert_object(UIRouter.top()).is_instanceof(SettingsMenu)


func test_the_keys_walk_from_the_tabs_through_the_rows_to_the_footer_and_back() -> void:
	var screen := await _open(SCREENS["settings"]) as SettingsMenu
	var tab: Control = screen.get_node("%VideoTab")
	assert_object(_focus()).is_same(tab)
	var rows := screen.focus_rows()
	for row: Array in rows:
		InputSim.key(KEY_DOWN, true)
		InputSim.key(KEY_DOWN, false)
		assert_object(_focus()).is_same(row[0])
	InputSim.key(KEY_DOWN, true)
	InputSim.key(KEY_DOWN, false)
	assert_object(_focus()).is_same(screen.get_node("%ResetButton"))
	InputSim.key(KEY_RIGHT, true)
	InputSim.key(KEY_RIGHT, false)
	assert_object(_focus()).is_same(screen.get_node("%BackButton"))
	for _row in rows.size() + 1:
		InputSim.key(KEY_UP, true)
		InputSim.key(KEY_UP, false)
	assert_object(_focus()).is_not_null()
	assert_bool(screen.is_ancestor_of(_focus())).is_true()


func test_left_and_right_change_a_slider_and_stay_on_it() -> void:
	var screen := await _open(SCREENS["settings"]) as SettingsMenu
	screen.select_tab(1, false)
	await get_tree().process_frame
	var master: UISlider = (screen.find_child("Master", true, false) as SettingRow).control
	master.grab_focus()
	Settings.set_value(SettingsService.VOLUME_MASTER, 50)
	InputSim.key(KEY_RIGHT, true)
	InputSim.key(KEY_RIGHT, false)
	assert_object(_focus()).is_same(master)
	assert_int(Settings.get_value(SettingsService.VOLUME_MASTER)).is_greater(50)
	InputSim.key(KEY_LEFT, true)
	InputSim.key(KEY_LEFT, false)
	InputSim.key(KEY_LEFT, true)
	InputSim.key(KEY_LEFT, false)
	assert_object(_focus()).is_same(master)
	assert_int(Settings.get_value(SettingsService.VOLUME_MASTER)).is_less(50)


func test_accept_flips_a_switch_and_the_focus_stays_on_it() -> void:
	var screen := await _open(SCREENS["settings"]) as SettingsMenu
	screen.select_tab(2, false)
	await get_tree().process_frame
	var toggle: UIToggle = (screen.find_child("InvertY", true, false) as SettingRow).control
	toggle.grab_focus()
	InputSim.key(KEY_ENTER, true)
	InputSim.key(KEY_ENTER, false)
	assert_bool(Settings.get_value(SettingsService.INVERT_Y)).is_true()
	assert_object(_focus()).is_same(toggle)
	InputSim.key(KEY_LEFT, true)
	InputSim.key(KEY_LEFT, false)
	assert_object(_focus()).is_same(toggle)


func test_a_key_on_a_screen_with_nothing_focused_gives_it_focus_first() -> void:
	var screen := await _open(SCREENS["main menu"])
	_focus().release_focus()
	assert_object(_focus()).is_null()
	InputSim.key(KEY_DOWN, true)
	InputSim.key(KEY_DOWN, false)
	assert_object(_focus()).is_not_null()
	assert_bool(screen.is_ancestor_of(_focus())).is_true()

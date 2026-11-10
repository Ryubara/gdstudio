# The screen host: a menu opened over the game pauses it, lets the mouse go and turns touch into
# mouse for the buttons, and the last screen closing gives all three back. Esc, pad Start and B,
# a browser's lost pointer lock and any action bound to a screen open and close it, through the
# real input path. The mouse is a stand-in platform: a headless run reads the mode back as visible.
extends GdUnitTestSuite

const PAUSE := preload("res://ui/menus/pause_menu.tscn")
const SETTINGS := preload("res://ui/menus/settings_menu.tscn")
const OPEN_ACTION := &"test_open_screen"

var _host: ScreenHost
var _mode := Input.MOUSE_MODE_VISIBLE
var _touch_mouse := true


class Ticker:
	extends Node
	var count := 0

	func _process(_delta: float) -> void:
		count += 1


func before_test() -> void:
	_mode = Input.MOUSE_MODE_VISIBLE
	_touch_mouse = Input.emulate_mouse_from_touch
	InputMap.add_action(OPEN_ACTION)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F9
	InputMap.action_add_event(OPEN_ACTION, event)
	_host = _make_host()


func after_test() -> void:
	InputSim.release_all()
	InputSim.key(KEY_F9, false)
	get_tree().paused = false
	await MenuFixture.clear(get_tree())
	if is_instance_valid(_host):
		_host.free()
	Input.emulate_mouse_from_touch = _touch_mouse
	InputMap.erase_action(OPEN_ACTION)
	await get_tree().process_frame


func _make_host() -> ScreenHost:
	var host := ScreenHost.new()
	host.pause_screen = PAUSE
	host.pause_on_focus_loss = false
	host.mouse_mode_reader = func() -> Input.MouseMode: return _mode
	host.mouse_mode_writer = func(mode: Input.MouseMode) -> void: _mode = mode
	add_child(host)
	return host


func _settle() -> void:
	assert_bool(await MenuFixture.settle(get_tree())).is_true()


func test_every_export_has_its_default_pinned() -> void:
	var fresh := auto_free(ScreenHost.new()) as ScreenHost
	var pins := {
		&"pause_screen": null,
		&"action_screens": {},
		&"transition": UITransition.Kind.FADE,
		&"pause_tree": true,
		&"release_mouse": true,
		&"pause_on_focus_loss": true,
		&"pause_on_lost_mouse": true,
		&"menu_scene": "res://ui/menus/menu_scene.tscn",
	}
	assert_array(ExportPins.differences(fresh, pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, pins)).is_empty()


func test_opening_a_screen_pauses_the_game_and_lets_the_mouse_go() -> void:
	_mode = Input.MOUSE_MODE_CAPTURED
	Input.emulate_mouse_from_touch = false
	var opened := [0]
	_host.opened.connect(func() -> void: opened[0] += 1)
	_host.open_pause()
	await _settle()
	assert_bool(_host.is_open()).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_int(_mode).is_equal(Input.MOUSE_MODE_VISIBLE)
	assert_bool(Input.emulate_mouse_from_touch).is_true()
	assert_int(UIRouter.depth()).is_equal(1)
	assert_object(UIRouter.top()).is_instanceof(PauseMenu)
	assert_int(opened[0]).is_equal(1)


func test_closing_gives_back_the_game_the_mouse_and_the_touch_setting() -> void:
	_mode = Input.MOUSE_MODE_CAPTURED
	Input.emulate_mouse_from_touch = false
	var closed := [0]
	_host.closed.connect(func() -> void: closed[0] += 1)
	_host.open_pause()
	await _settle()
	_host.close()
	await _settle()
	assert_bool(_host.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_int(_mode).is_equal(Input.MOUSE_MODE_CAPTURED)
	assert_bool(Input.emulate_mouse_from_touch).is_false()
	assert_int(UIRouter.depth()).is_zero()
	assert_int(closed[0]).is_equal(1)


func test_a_mouse_the_game_did_not_hold_is_not_taken_on_close() -> void:
	_host.open_pause()
	await _settle()
	_host.close()
	await _settle()
	assert_int(_mode).is_equal(Input.MOUSE_MODE_VISIBLE)


func test_the_game_stops_while_a_screen_is_up_and_runs_again_after() -> void:
	var ticker := Ticker.new()
	add_child(ticker)
	await get_tree().process_frame
	_host.open_pause()
	await _settle()
	var frozen := ticker.count
	for _frame in 5:
		await get_tree().process_frame
	assert_int(ticker.count).is_equal(frozen)
	_host.close()
	await _settle()
	for _frame in 5:
		await get_tree().process_frame
	assert_int(ticker.count).is_greater(frozen)
	ticker.free()


func test_a_host_that_does_not_pause_leaves_the_game_running() -> void:
	_host.pause_tree = false
	_host.open_pause()
	await _settle()
	assert_bool(get_tree().paused).is_false()
	assert_int(UIRouter.depth()).is_equal(1)


func test_escape_opens_the_pause_menu_and_escape_again_resumes() -> void:
	InputSim.key(KEY_ESCAPE, true)
	InputSim.key(KEY_ESCAPE, false)
	await _settle()
	assert_bool(get_tree().paused).is_true()
	assert_object(UIRouter.top()).is_instanceof(PauseMenu)
	InputSim.key(KEY_ESCAPE, true)
	InputSim.key(KEY_ESCAPE, false)
	await _settle()
	assert_bool(get_tree().paused).is_false()
	assert_int(UIRouter.depth()).is_zero()


func test_the_pads_start_opens_and_closes_even_over_settings() -> void:
	InputSim.pad_button(JOY_BUTTON_START, true)
	InputSim.pad_button(JOY_BUTTON_START, false)
	await _settle()
	assert_object(UIRouter.top()).is_instanceof(PauseMenu)
	UIRouter.push(SETTINGS, UITransition.Kind.CUT)
	await _settle()
	assert_int(UIRouter.depth()).is_equal(2)
	InputSim.pad_button(JOY_BUTTON_START, true)
	InputSim.pad_button(JOY_BUTTON_START, false)
	await _settle()
	assert_int(UIRouter.depth()).is_zero()
	assert_bool(get_tree().paused).is_false()


func test_escape_and_the_pads_b_go_back_one_screen_at_a_time() -> void:
	_host.open_pause()
	await _settle()
	UIRouter.push(SETTINGS, UITransition.Kind.CUT)
	await _settle()
	InputSim.pad_button(JOY_BUTTON_B, true)
	InputSim.pad_button(JOY_BUTTON_B, false)
	await _settle()
	assert_object(UIRouter.top()).is_instanceof(PauseMenu)
	assert_bool(get_tree().paused).is_true()
	InputSim.pad_button(JOY_BUTTON_B, true)
	InputSim.pad_button(JOY_BUTTON_B, false)
	await _settle()
	assert_bool(get_tree().paused).is_false()


func test_an_action_bound_to_a_screen_opens_it_and_the_same_key_closes_it() -> void:
	_host.action_screens = {OPEN_ACTION: SETTINGS}
	InputSim.key(KEY_F9, true)
	InputSim.key(KEY_F9, false)
	await _settle()
	assert_object(UIRouter.top()).is_instanceof(SettingsMenu)
	assert_bool(get_tree().paused).is_true()
	InputSim.key(KEY_F9, true)
	InputSim.key(KEY_F9, false)
	await _settle()
	assert_int(UIRouter.depth()).is_zero()
	assert_bool(get_tree().paused).is_false()


func test_code_opens_any_screen_and_a_second_one_stacks() -> void:
	_host.open(SETTINGS)
	await _settle()
	_host.open(PAUSE)
	await _settle()
	assert_int(UIRouter.depth()).is_equal(2)
	assert_bool(get_tree().paused).is_true()
	_host.close()
	await _settle()
	assert_int(UIRouter.depth()).is_zero()
	assert_bool(get_tree().paused).is_false()


func test_the_host_found_by_a_screen_is_the_one_in_the_tree() -> void:
	assert_object(ScreenHost.current).is_same(_host)


func test_freeing_the_host_with_a_screen_up_unpauses_and_clears_the_router() -> void:
	_host.open_pause()
	await _settle()
	_host.free()
	await get_tree().process_frame
	assert_bool(get_tree().paused).is_false()
	assert_object(ScreenHost.current).is_null()
	await _settle()
	assert_int(UIRouter.depth()).is_zero()


func test_resume_on_the_screen_closes_it() -> void:
	_host.open_pause()
	await _settle()
	var resume: Button = UIRouter.top().get_node("%ResumeButton")
	resume.pressed.emit()
	await _settle()
	assert_bool(get_tree().paused).is_false()
	assert_int(UIRouter.depth()).is_zero()

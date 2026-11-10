# `ScreenHost` of `gds_game` on its own: a screen opened over a game pauses it and lets the mouse
# go, the last one closing gives both back, the `pause` action opens and closes its screen, and
# "Main menu" leaves for `menu_scene` (empty: the project's main scene). The screens are plain
# controls and the mouse a stand-in; a game's suites open its own menus through the real keys
# (3D Third Person's `test_screen_host.gd`).
extends GdUnitTestSuite

const SETTLE_SECONDS := 4.0
const PAUSE_KEY := KEY_F8

var _host: ScreenHost
var _mode := Input.MOUSE_MODE_CAPTURED
var _changed: Array[String] = []
var _touch_mouse := true
var _added_pause := false


func before_test() -> void:
	_mode = Input.MOUSE_MODE_CAPTURED
	_changed.clear()
	_touch_mouse = Input.emulate_mouse_from_touch
	_added_pause = not InputMap.has_action(ScreenHost.PAUSE_ACTION)
	if _added_pause:
		InputMap.add_action(ScreenHost.PAUSE_ACTION)
		var key := InputEventKey.new()
		key.physical_keycode = PAUSE_KEY
		InputMap.action_add_event(ScreenHost.PAUSE_ACTION, key)
	_host = ScreenHost.new()
	_host.pause_on_focus_loss = false
	_host.transition = UITransition.Kind.CUT
	_host.mouse_mode_reader = func() -> Input.MouseMode: return _mode
	_host.mouse_mode_writer = func(mode: Input.MouseMode) -> void: _mode = mode
	_host.scene_changer = func(path: String) -> void: _changed.append(path)
	add_child(_host)


func after_test() -> void:
	InputSim.release_all()
	InputSim.key(PAUSE_KEY, false)
	get_tree().paused = false
	await RouterFixture.clear(get_tree())
	if is_instance_valid(_host):
		_host.free()
	Input.emulate_mouse_from_touch = _touch_mouse
	if _added_pause:
		InputMap.erase_action(ScreenHost.PAUSE_ACTION)
	await get_tree().process_frame


func _screen() -> PackedScene:
	var screen := Control.new()
	screen.name = "Screen"
	var packed := PackedScene.new()
	packed.pack(screen)
	screen.free()
	return packed


func _settle() -> void:
	var waited := 0.0
	while UIRouter.busy and waited < SETTLE_SECONDS:
		await get_tree().process_frame
		waited += get_tree().root.get_process_delta_time()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(UIRouter.busy).is_false()


func _press_pause() -> void:
	InputSim.key(PAUSE_KEY, true)
	InputSim.key(PAUSE_KEY, false)
	await _settle()


func test_a_screen_pauses_the_game_and_closing_it_gives_the_game_and_mouse_back() -> void:
	_host.open(_screen())
	await _settle()
	assert_bool(_host.is_open()).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_int(_mode).is_equal(Input.MOUSE_MODE_VISIBLE)
	assert_bool(Input.emulate_mouse_from_touch).is_true()
	_host.close(UITransition.Kind.CUT)
	await _settle()
	assert_bool(_host.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_int(_mode).is_equal(Input.MOUSE_MODE_CAPTURED)
	assert_bool(Input.emulate_mouse_from_touch).is_equal(_touch_mouse)


func test_a_host_that_does_not_pause_leaves_the_tree_running() -> void:
	_host.pause_tree = false
	_host.open(_screen())
	await _settle()
	assert_bool(_host.is_open()).is_true()
	assert_bool(get_tree().paused).is_false()


func test_the_pause_action_opens_its_screen_and_closes_it_again() -> void:
	_host.pause_screen = _screen()
	await _press_pause()
	assert_bool(_host.is_open()).is_true()
	await _press_pause()
	assert_bool(_host.is_open()).is_false()


func test_main_menu_leaves_for_the_menu_scene_set_on_the_host() -> void:
	_host.menu_scene = "res://somewhere/menu.tscn"
	_host.go_to_menu()
	assert_array(_changed).is_equal(["res://somewhere/menu.tscn"])
	assert_int(_mode).is_equal(Input.MOUSE_MODE_VISIBLE)


func test_an_empty_menu_scene_is_the_projects_main_scene() -> void:
	var main := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	_host.menu_scene = ""
	assert_str(_host.menu_scene).is_equal(main)
	ProjectSettings.set_setting("application/run/main_scene", "res://start.tscn")
	assert_str(_host.menu_scene).is_equal("res://start.tscn")
	_host.go_to_menu()
	ProjectSettings.set_setting("application/run/main_scene", main)
	assert_array(_changed).is_equal(["res://start.tscn"])


func test_freeing_the_host_with_a_screen_up_unpauses_and_clears_the_router() -> void:
	_host.open(_screen())
	await _settle()
	_host.free()
	await _settle()
	assert_bool(get_tree().paused).is_false()
	assert_int(UIRouter.depth()).is_equal(0)
	assert_object(ScreenHost.current).is_null()

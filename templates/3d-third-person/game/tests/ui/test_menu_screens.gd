# The main menu, the pause menu, the loading screen and the scene the project starts: what each
# button does, what a browser leaves out, and the way back from a game that cannot be read.
extends GdUnitTestSuite

const MAIN_MENU := preload("res://ui/menus/main_menu.tscn")
const PAUSE := preload("res://ui/menus/pause_menu.tscn")
const LOADING := "res://ui/menus/loading_screen.tscn"

var _touch_mouse := true


func before_test() -> void:
	_touch_mouse = Input.emulate_mouse_from_touch
	UIMotion.reduced = true


func after_test() -> void:
	UIMotion.reduced = false
	get_tree().paused = false
	await MenuFixture.clear(get_tree())
	Input.emulate_mouse_from_touch = _touch_mouse
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _show(scene: PackedScene) -> Control:
	UIRouter.reset(scene, UITransition.Kind.CUT)
	assert_bool(await MenuFixture.settle(get_tree())).is_true()
	return UIRouter.top()


func test_the_main_menu_shows_the_games_name_and_its_buttons() -> void:
	var menu := await _show(MAIN_MENU) as MainMenu
	assert_str((menu.get_node("%Title") as Label).text).is_equal(
		str(ProjectSettings.get_setting("application/config/name"))
	)
	assert_str((menu.get_node("%PlayButton") as Button).text).is_equal("Play")
	assert_str((menu.get_node("%OnlineButton") as Button).text).is_equal("Play online")
	assert_str((menu.get_node("%SettingsButton") as Button).text).is_equal("Settings")
	assert_str((menu.get_node("%QuitButton") as Button).text).is_equal("Quit")


func test_quit_is_left_out_in_a_browser_and_there_otherwise() -> void:
	var menu := await _show(MAIN_MENU) as MainMenu
	assert_bool((menu.get_node("%QuitButton") as Button).visible).is_equal(
		not OS.has_feature("web")
	)


func test_the_main_menu_starts_on_play() -> void:
	var menu := await _show(MAIN_MENU) as MainMenu
	assert_object(get_viewport().gui_get_focus_owner()).is_same(menu.get_node("%PlayButton"))
	assert_bool(menu.allow_back).is_false()


func test_settings_pushes_the_settings_screen_and_back_returns_to_the_menu() -> void:
	var menu := await _show(MAIN_MENU) as MainMenu
	(menu.get_node("%SettingsButton") as Button).grab_focus()
	(menu.get_node("%SettingsButton") as Button).pressed.emit()
	await MenuFixture.settle(get_tree())
	assert_object(UIRouter.top()).is_instanceof(SettingsMenu)
	assert_int(UIRouter.depth()).is_equal(2)
	UIRouter.pop()
	await MenuFixture.settle(get_tree())
	assert_object(UIRouter.top()).is_same(menu)
	# The focus comes back to the button that opened the screen.
	assert_object(get_viewport().gui_get_focus_owner()).is_same(menu.get_node("%SettingsButton"))


func test_escape_on_the_main_menu_does_nothing() -> void:
	await _show(MAIN_MENU)
	InputSim.key(KEY_ESCAPE, true)
	InputSim.key(KEY_ESCAPE, false)
	await MenuFixture.settle(get_tree())
	assert_int(UIRouter.depth()).is_equal(1)


func test_play_shows_the_loading_screen_with_the_game_scene() -> void:
	var menu := MAIN_MENU.instantiate() as MainMenu
	# A scene that is not there, so the loading screen stops where it can be seen and nothing
	# replaces the scene this test runs in.
	menu.game_scene = "res://no_such_game.tscn"
	UIRouter.reset(menu, UITransition.Kind.CUT)
	await MenuFixture.settle(get_tree())
	menu.play()
	await MenuFixture.settle(get_tree())
	var loading := UIRouter.top() as LoadingScreen
	assert_object(loading).is_not_null()
	assert_str(loading.params["scene"]).is_equal("res://no_such_game.tscn")
	assert_int(UIRouter.depth()).is_equal(1)


func test_play_online_loads_the_online_game_for_the_address_in_the_field() -> void:
	var menu := MAIN_MENU.instantiate() as MainMenu
	menu.online_scene = "res://no_such_online_game.tscn"
	UIRouter.reset(menu, UITransition.Kind.CUT)
	await MenuFixture.settle(get_tree())
	var field := menu.get_node("%AddressField") as LineEdit
	# The suites run a debug build: the developer's field shows, with the game's server in it.
	assert_bool(field.visible).is_true()
	assert_str(field.text).is_equal(menu.server_address)
	field.text = " ws://10.0.0.7:8910 "
	(menu.get_node("%OnlineButton") as Button).pressed.emit()
	await MenuFixture.settle(get_tree())
	assert_str(NetClient.next_url).is_equal("ws://10.0.0.7:8910")
	NetClient.next_url = ""
	var loading := UIRouter.top() as LoadingScreen
	assert_object(loading).is_not_null()
	assert_str(loading.params["scene"]).is_equal("res://no_such_online_game.tscn")


func test_a_release_build_shows_no_address_and_joins_the_games_server() -> void:
	var menu := MAIN_MENU.instantiate() as MainMenu
	menu.online_scene = "res://no_such_online_game.tscn"
	menu.address_field = MainMenu.AddressField.NEVER
	menu.server_address = "wss://play.example.org"
	UIRouter.reset(menu, UITransition.Kind.CUT)
	await MenuFixture.settle(get_tree())
	assert_bool((menu.get_node("%AddressField") as Control).visible).is_false()
	menu.play_online()
	assert_str(NetClient.next_url).is_equal("wss://play.example.org")
	NetClient.next_url = ""


func test_a_game_that_cannot_be_read_says_so_and_offers_the_way_back() -> void:
	UIRouter.reset(LOADING, UITransition.Kind.CUT, {"scene": "res://no_such_game.tscn"})
	await MenuFixture.settle(get_tree())
	var loading := UIRouter.top() as LoadingScreen
	var back := loading.get_node("%BackButton") as Button
	assert_bool(back.visible).is_true()
	assert_str((loading.get_node("%Message") as Label).text).is_equal("Could not load the game.")
	assert_object(get_viewport().gui_get_focus_owner()).is_same(back)
	back.pressed.emit()
	await MenuFixture.settle(get_tree())
	assert_object(UIRouter.top()).is_instanceof(MainMenu)


func test_a_loading_screen_with_no_scene_is_a_failure_too() -> void:
	UIRouter.reset(LOADING, UITransition.Kind.CUT)
	await MenuFixture.settle(get_tree())
	var loading := UIRouter.top() as LoadingScreen
	assert_bool((loading.get_node("%BackButton") as Button).visible).is_true()


func test_the_pause_menu_closes_on_back_and_has_the_three_ways_out() -> void:
	var menu := await _show(PAUSE) as PauseMenu
	assert_bool(menu.back_closes).is_true()
	assert_bool(menu.stars).is_false()
	for button_name in ["%ResumeButton", "%SettingsButton", "%MainMenuButton"]:
		(
			assert_object(menu.get_node(button_name))
			. override_failure_message(button_name)
			. is_not_null()
		)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(menu.get_node("%ResumeButton"))


func test_the_pause_menu_lets_the_game_show_through() -> void:
	var menu := await _show(PAUSE) as PauseMenu
	assert_float(menu.self_modulate.a).is_less(1.0)
	assert_float(menu.self_modulate.a).is_greater(0.5)


func test_settings_on_the_pause_menu_goes_back_to_the_pause_menu() -> void:
	var menu := await _show(PAUSE) as PauseMenu
	(menu.get_node("%SettingsButton") as Button).pressed.emit()
	await MenuFixture.settle(get_tree())
	assert_object(UIRouter.top()).is_instanceof(SettingsMenu)
	InputSim.key(KEY_ESCAPE, true)
	InputSim.key(KEY_ESCAPE, false)
	await MenuFixture.settle(get_tree())
	assert_object(UIRouter.top()).is_same(menu)


func test_main_menu_from_the_pause_menu_leaves_the_game_for_the_menu_scene() -> void:
	var host := ScreenHost.new()
	host.pause_screen = PAUSE
	host.pause_on_focus_loss = false
	var changed: Array[String] = []
	host.scene_changer = func(path: String) -> void: changed.append(path)
	add_child(host)
	host.open_pause()
	await MenuFixture.settle(get_tree())
	var menu := UIRouter.top() as PauseMenu
	(menu.get_node("%MainMenuButton") as Button).pressed.emit()
	assert_array(changed).is_equal(["res://ui/menus/menu_scene.tscn"])
	assert_bool(get_tree().paused).is_false()
	assert_bool(host.is_open()).is_false()
	assert_int(Input.mouse_mode).is_equal(Input.MOUSE_MODE_VISIBLE)
	host.free()


func test_the_project_starts_the_menu_scene_which_shows_the_main_menu() -> void:
	var scene := MenuScene.new()
	scene.main_menu = MAIN_MENU
	Input.emulate_mouse_from_touch = false
	add_child(scene)
	assert_bool(scene.wants_game()).is_false()
	assert_bool(await MenuFixture.settle(get_tree())).is_true()
	assert_object(UIRouter.top()).is_instanceof(MainMenu)
	assert_bool(Input.emulate_mouse_from_touch).is_true()
	scene.free()


func test_a_menu_scene_told_to_skip_the_menu_goes_to_the_game() -> void:
	var scene := MenuScene.new()
	scene.main_menu = MAIN_MENU
	scene.skip_menu = true
	var went: Array[String] = []
	scene.scene_changer = func(path: String) -> void: went.append(path)
	add_child(scene)
	assert_array(went).is_equal(["res://main.tscn"])
	assert_int(UIRouter.depth()).is_zero()
	scene.free()


func test_the_menu_scene_is_the_one_in_the_project_file() -> void:
	var scene := (load("res://ui/menus/menu_scene.tscn") as PackedScene).instantiate() as MenuScene
	assert_object(scene.main_menu).is_not_null()
	assert_str(scene.game_scene).is_equal("res://main.tscn")
	assert_bool(scene.skip_menu).is_false()
	scene.free()

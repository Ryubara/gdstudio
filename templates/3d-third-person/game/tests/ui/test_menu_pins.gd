# The inspector contract of the menu parts: every export's default is pinned, so a new export fails
# until someone has looked at it, and the parts that carry values to tune are checked once.
extends GdUnitTestSuite


func _check(object: Object, pins: Dictionary) -> void:
	assert_array(ExportPins.differences(object, pins)).is_empty()
	assert_array(ExportPins.wrong_values(object, pins)).is_empty()


func test_the_quality_preset() -> void:
	_check(
		auto_free(QualityPreset.new()),
		{
			&"title": "High",
			&"msaa": Viewport.MSAA_2X,
			&"shadow_atlas_size": 4096,
			&"shadow_filter": RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
		}
	)


func test_the_three_presets_of_the_scene_step_down_in_cost() -> void:
	var service := (load("res://core/settings/settings_service.tscn") as PackedScene).instantiate()
	var presets: Array[QualityPreset] = (service as SettingsService).presets
	(
		assert_array(presets.map(func(p: QualityPreset) -> int: return p.shadow_atlas_size))
		. is_equal([2048, 2048, 4096])
	)
	(
		assert_array(presets.map(func(p: QualityPreset) -> int: return p.msaa))
		. is_equal([Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X])
	)
	service.free()


func test_the_menu_fit() -> void:
	_check(
		auto_free(MenuFit.new()),
		{&"phone_short_side": 500, &"touch_short_side": 1000, &"phone_factor": 2.0, &"force": 0}
	)


func test_a_setting_row() -> void:
	_check(
		auto_free(SettingRow.new()),
		{
			&"title": "",
			&"hint": "",
			&"key": &"",
			&"format": "%d%%",
			&"option_values": PackedFloat32Array(),
			&"options_from_presets": false,
			&"hide_on_web": false,
		}
	)


func test_the_look_settings_bridge() -> void:
	_check(auto_free(LookSettings.new()), {&"camera": null})


func test_the_controls_page_lists_the_actions_a_player_may_rebind() -> void:
	var page := auto_free(ControlsPage.new()) as ControlsPage
	assert_array(ExportPins.differences(page, {&"actions": page.actions})).is_empty()
	assert_array(page.actions).contains(
		[&"move_forward", &"jump", &"sprint", &"crouch", &"aim", &"fire", &"pause"]
	)


func test_the_pause_button() -> void:
	var button := auto_free(PauseButton.new()) as PauseButton
	var pins := {
		&"host": null,
		&"touch": null,
		&"screen": null,
		&"always_shown": false,
		&"variant": UIButton.Variant.PRIMARY,
		&"preview_state": UIButton.Preview.NONE,
	}
	# The button is a UIButton, whose own two exports are the addon's.
	assert_array(ExportPins.wrong_values(button, pins)).is_empty()
	for pinned: StringName in [&"host", &"touch", &"screen", &"always_shown"]:
		assert_array(ExportPins.names(button)).contains([pinned])


func test_the_main_menu_and_the_menu_scene() -> void:
	var main_menu := auto_free(MainMenu.new()) as MainMenu
	assert_str(main_menu.game_scene).is_equal("res://main.tscn")
	assert_str(main_menu.title).is_empty()
	assert_bool(main_menu.allow_back).is_true()
	var menu_scene := auto_free(MenuScene.new()) as MenuScene
	_check(
		menu_scene,
		{
			&"main_menu": null,
			&"game_scene": "res://main.tscn",
			&"server_scene": "res://gameplay/net/net_server.tscn",
			&"skip_menu": false,
		}
	)


func test_the_loading_screen_stays_up_a_moment() -> void:
	var loading := auto_free(LoadingScreen.new()) as LoadingScreen
	assert_float(loading.least_time).is_equal_approx(0.4, 0.0001)

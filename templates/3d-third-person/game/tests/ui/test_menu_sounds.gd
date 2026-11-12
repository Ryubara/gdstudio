# The menus' sounds are wired (`MenuSoundService`, the `MenuSounds` autoload): it takes the UI
# cues, every player is on the UI bus with its level (measured in a game made from the template,
# kit docs engines/godot/audio.md#menu-sounds) and decoded takes, every file of the folder plays,
# and every control of every menu has a role the table knows.
extends GdUnitTestSuite

const SCENE := "res://ui/menus/menu_sound_service.tscn"
const SCREENS := {
	"main menu": "res://ui/menus/main_menu.tscn",
	"pause menu": "res://ui/menus/pause_menu.tscn",
	"settings": "res://ui/menus/settings_menu.tscn",
}
## Each player's volume (dB) and base pitch: the ladder of `gamedev/audio/ui-sounds.md`.
const LEVELS := {
	&"Hint": [-15.0, 1.0],
	&"Press": [-7.0, 1.0],
	&"Confirm": [-10.0, 1.0],
	&"Back": [-9.0, 0.8],
	&"Refuse": [-9.0, 0.67],
	&"Tab": [-13.0, 1.0],
	&"Select": [-13.0, 1.12],
	&"ToggleOn": [-13.0, 1.12],
	&"ToggleOff": [-13.0, 0.89],
	&"Tick": [-17.0, 1.0],
	&"Open": [-7.0, 1.0],
	&"Close": [-9.0, 0.85],
}

var _sounds: MenuSoundService
var _window_size := Vector2i.ZERO


func before_test() -> void:
	_window_size = get_window().size
	get_window().size = Vector2i(1920, 1080)
	UIMotion.reduced = true
	UIInputMode.touch = false
	_sounds = (load(SCENE) as PackedScene).instantiate() as MenuSoundService
	add_child(_sounds)


func after_test() -> void:
	InputSim.release_all()
	UIMotion.reduced = false
	UIInputMode.touch = false
	await MenuFixture.clear(get_tree())
	AudioSettings.stop_players(_sounds)
	_sounds.free()
	AudioSettings.drain_mixer()
	# The project's own service takes the cues again.
	var autoload := get_node_or_null(^"/root/MenuSounds") as MenuSoundService
	if autoload != null:
		UIAudio.handler = autoload.handle
	get_window().size = _window_size


func _open(path: String) -> Control:
	UIRouter.reset(path, UITransition.Kind.CUT)
	assert_bool(await MenuFixture.settle(get_tree())).is_true()
	await get_tree().process_frame
	_sounds.advance(1.0)
	_sounds.heard.clear()
	return UIRouter.top()


## The sounds heard since the list was cleared, `&""` for a cue that stayed silent.


func _heard() -> Array:
	return _sounds.heard.map(func(entry: Array) -> StringName: return entry[1])


func _played() -> Array:
	return _heard().filter(func(sound: StringName) -> bool: return sound != &"")


func test_the_project_loads_the_service_and_it_takes_the_ui_cues() -> void:
	var autoload := get_node_or_null(^"/root/MenuSounds")
	assert_object(autoload).is_instanceof(MenuSoundService)
	assert_str(String(ProjectSettings.get_setting("autoload/MenuSounds"))).is_equal("*" + SCENE)
	# The suite's own instance took the hook when it entered the tree.
	assert_bool(UIAudio.handler == Callable(_sounds, &"handle")).is_true()
	assert_int(_sounds.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)


func test_every_player_is_on_the_ui_bus_with_its_level_and_decoded_takes() -> void:
	var players := _sounds.players()
	assert_int(players.size()).is_equal(LEVELS.size())
	for player in players:
		assert_str(String(player.bus)).is_equal("UI")
		assert_bool(LEVELS.has(player.name)).is_true()
		assert_float(player.volume_db).is_equal(LEVELS[player.name][0])
		assert_float(player.pitch_scale).is_equal_approx(LEVELS[player.name][1], 0.001)
		var takes := player.stream as AudioStreamRandomizer
		(
			assert_object(takes)
			. override_failure_message("%s: no randomizer" % player.name)
			. is_not_null()
		)
		for n in takes.streams_count:
			# Decoded while loading, so a press never pays the Vorbis set-up.
			assert_object(takes.get_stream(n)).is_instanceof(AudioStreamWAV)


func test_every_file_of_the_ui_folder_is_played_by_the_service() -> void:
	var text := FileAccess.get_file_as_string(SCENE)
	var dir := DirAccess.open("res://assets/audio/ui")
	var files := 0
	for file in dir.get_files():
		if file.ends_with(".ogg"):
			files += 1
			assert_bool(text.contains("assets/audio/ui/" + file)).is_true()
			var stream := load("res://assets/audio/ui/" + file) as AudioStream
			assert_float(stream.get_length()).is_less(0.5)
	assert_int(files).is_equal(14)
	assert_bool(FileAccess.file_exists("res://assets/audio/ui/LICENSE.md")).is_true()


func test_the_exports_keep_their_defaults() -> void:
	var pins := {
		&"enabled": true,
		&"hint_gap": 0.07,
		&"quiet_after_action": 0.3,
		&"tick_gap": 0.06,
		&"tick_pitch": Vector2(0.9, 1.25),
	}
	assert_array(ExportPins.differences(_sounds, pins)).is_empty()
	assert_array(ExportPins.wrong_values(_sounds, pins)).is_empty()


func test_every_control_of_every_menu_has_a_role_the_table_knows() -> void:
	for label: String in SCREENS:
		var screen := await _open(SCREENS[label])
		for node in screen.find_children("*", "Control", true, false):
			var control := node as Control
			if control.focus_mode == Control.FOCUS_NONE and not control is BaseButton:
				continue
			var role := MenuSoundService.role_of(control)
			(
				assert_bool(MenuSoundService.TABLE.has(role))
				. override_failure_message("%s: %s has role '%s'" % [label, control.name, role])
				. is_true()
			)
		await MenuFixture.clear(get_tree())
	# Screens the router does not host: the online status layer and the inventory screen.
	for path in ["res://ui/online/online_status.tscn", "res://ui/inventory/inventory_screen.tscn"]:
		var layer := auto_free((load(path) as PackedScene).instantiate()) as Node
		for node in layer.find_children("*", "BaseButton", true, false):
			var role := MenuSoundService.role_of(node)
			(
				assert_bool(MenuSoundService.TABLE.has(role))
				. override_failure_message("%s: %s has role '%s'" % [path, node.name, role])
				. is_true()
			)


func test_the_inventory_cell_is_a_choice_from_a_set() -> void:
	var cell := (
		auto_free((load("res://ui/inventory/inventory_cell.tscn") as PackedScene).instantiate())
		as InventoryCell
	)
	assert_str(String(MenuSoundService.role_of(cell))).is_equal("cell")
	assert_str(String(MenuSoundService.sound_for(&"select", cell))).is_equal("Select")

## Films the HUD's weapon slots and hotbar over the game, through the keys a player presses: the
## player is hurt, key 2 takes the fists (slot 2 lights), key 3 uses a bandage from the hotbar (the
## place flashes, health rises by 25, the count drops), key 1 takes the pistol back, and a bandage
## is put on hotbar place 4 from the inventory screen with its key. Every step holds `STEP`
## seconds. With `phone` after the engine's `--` the touch controls come up and the page's pixel
## ratio is 2 (a 1688 x 780 window is an 844 x 390 phone page), and a finger on each place does
## what the key does.
##
## Two ways to run it:
## - with Movie Maker through the kit, for a desktop-sized window:
##   `gds godot -- --path game --write-movie out/hotbar.png --fixed-fps 10 --resolution 1920x1080
##   --quit-after 200 res://tools/capture/hotbar_tour.tscn` (it quits by itself at its end)
## - for a phone-sized window (Movie Maker crops a canvas wider than 1920 units), with
##   `--shots=<dir>` after the engine's `--`: each step's real window pixels are saved as a PNG:
##   `gds godot -- --path game --resolution 1688x780 res://tools/capture/hotbar_tour.tscn --
##   phone --shots=out`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const STEP := 0.9
const GAME := "res://main.tscn"

var _shots := ""
var _count := 0
var _phone := false
var _hud: Hud
var _touch: TouchControls


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):
			_shots = argument.trim_prefix("--shots=")
	_phone = OS.get_cmdline_user_args().has("phone")
	var game: Node = (load(GAME) as PackedScene).instantiate()
	add_child(game)
	_hud = game.get_node("Hud")
	_touch = game.get_node("PlayerRig/TouchControls")
	if _phone:
		_hud.pixel_ratio = 2.0
		_touch.show_mode = TouchControls.ShowMode.ALWAYS
		_touch._set_shown(true)
	await _hold(1.5)
	var player := get_tree().get_first_node_in_group(&"player") as Player
	Health.of(player).value = 40.0
	await _hold()
	await _place(&"weapon_2", KEY_2)
	await _hold(1.2)
	await _place(&"hotbar_1", KEY_3)
	await _hold(0.15)
	await _hold()
	await _place(&"weapon_1", KEY_1)
	await _hold(1.2)
	if not _phone:
		_key(KEY_I)
		await _hold()
		await _hold(0.2)
		var screen := UIRouter.top() as InventoryScreen
		screen.item_cells()[0].grab_focus()
		await _hold(0.2)
		_key(KEY_4)
		await _hold()
		_key(KEY_I)
		await _hold()
	# Stops the sounds and gives the mixer a few frames to let go of them before quitting (a voice
	# still playing at exit is reported as a leak).
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()


# Presses a place as the player would: its key on a desktop, a finger on it on a phone.
func _place(action: StringName, key: Key) -> void:
	if not _phone:
		_key(key)
		return
	for zone in _hud.touch_zones():
		if zone["action"] == action:
			_touch_at((zone["rect"] as Rect2).get_center(), true)
			await get_tree().create_timer(0.1, true).timeout
			_touch_at((zone["rect"] as Rect2).get_center(), false)


func _key(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func _touch_at(at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 4
	event.position = at
	event.pressed = pressed
	_touch._input(event)


## Waits `seconds` and, when asked for shots, saves what the window shows.
func _hold(seconds := STEP) -> void:
	await get_tree().create_timer(seconds, true).timeout
	if _shots.is_empty():
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_shots)
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/step%02d.png" % [_shots, _count])
	_count += 1

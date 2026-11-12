## Plays the menus' sounds for a recording, in two parts, and prints each event as
## `TOUR <seconds> <what>` (seconds from the first frame, at the capture's fixed rate):
## - levels: every player of the `MenuSounds` service alone, three times each, 0.7 s apart;
## - walk: the menus driven by real key presses (focus moves, Settings, a tab, an option, slider
##   steps, a toggle, Esc), then Play into the game, a pistol shot for reference, Esc for the pause
##   menu over the game, a few focus moves and Esc to resume.
##
## `gds godot -- --path game --write-movie <abs>/menu_sounds.avi --fixed-fps 60 --resolution
## 1280x720 res://tools/capture/menu_sounds_tour.tscn` (kit docs engines/godot/audio.md). It lives
## in tools/, which the export leaves out.
extends Node

const MAIN_MENU := "res://ui/menus/main_menu.tscn"
const FPS := 60.0
const GAP := 0.7

var _start := 0


func _ready() -> void:
	if not has_meta(&"driver"):
		# Play changes the scene, which frees this one: the tour runs from a node beside it.
		var driver := Node.new()
		driver.set_script(get_script())
		driver.set_meta(&"driver", true)
		driver.process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().root.add_child.call_deferred(driver)
		return
	_start = Engine.get_process_frames()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _levels()
	await _walk()
	await _end()


func _log(what: String) -> void:
	print("TOUR %.3f %s" % [(Engine.get_process_frames() - _start) / FPS, what])


func _levels() -> void:
	var sounds := get_node(^"/root/MenuSounds") as MenuSoundService
	await _wait(1.0)
	for player in sounds.players():
		for n in 3:
			_log("level %s" % player.name)
			player.play()
			await _wait(GAP)
		await _wait(GAP)


func _walk() -> void:
	UIRouter.reset(MAIN_MENU, UITransition.Kind.CUT)
	await _wait(1.5)
	_log("walk main menu")
	# From Play: down to Play online, back up, and up round the column to Quit and Settings.
	for key: Key in [KEY_DOWN, KEY_UP, KEY_UP, KEY_UP]:
		await _key(key, "key %s" % OS.get_keycode_string(key))
	await _key(KEY_ENTER, "key Enter (Settings)", 1.5)
	await _key(KEY_RIGHT, "key Right (Audio tab focus)")
	await _key(KEY_ENTER, "key Enter (Audio tab)")
	await _key(KEY_LEFT, "key Left (Video tab focus)")
	await _key(KEY_ENTER, "key Enter (Video tab)")
	await _key(KEY_DOWN, "key Down (window mode)")
	await _key(KEY_DOWN, "key Down (quality)")
	await _key(KEY_RIGHT, "key Right (quality option)")
	await _key(KEY_LEFT, "key Left (quality option)")
	await _key(KEY_DOWN, "key Down (resolution slider)")
	for n in 4:
		await _key(KEY_LEFT, "key Left (slider step)", 0.25)
	for n in 4:
		await _key(KEY_RIGHT, "key Right (slider step)", 0.25)
	await _key(KEY_DOWN, "key Down (vsync)")
	await _key(KEY_ENTER, "key Enter (vsync toggle)")
	await _key(KEY_ENTER, "key Enter (vsync toggle)")
	await _key(KEY_ESCAPE, "key Esc (back to the main menu)", 1.5)
	await _key(KEY_DOWN, "key Down (Quit)")
	await _key(KEY_DOWN, "key Down (Play)")
	await _key(KEY_ENTER, "key Enter (Play)", 6.0)
	_log("in the game")
	Input.action_press(&"fire")
	_log("shot")
	await _wait(0.1)
	Input.action_release(&"fire")
	await _wait(1.5)
	await _key(KEY_ESCAPE, "key Esc (pause)", 1.2)
	await _key(KEY_DOWN, "key Down")
	await _key(KEY_DOWN, "key Down")
	await _key(KEY_UP, "key Up")
	await _key(KEY_ESCAPE, "key Esc (resume)", 1.5)


func _end() -> void:
	_log("end")
	get_tree().paused = false
	AudioSettings.stop_players(get_tree().root)
	for frame in 8:
		await get_tree().process_frame
	get_tree().quit()


func _key(code: Key, what: String, after := GAP) -> void:
	_log(what)
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
	await _wait(after)


func _wait(seconds: float) -> void:
	for frame in roundi(seconds * FPS):
		await get_tree().process_frame

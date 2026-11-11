## Walks the inventory for a capture, over the game: the player picks up coins, the screen opens
## from the `inventory` action, the focus goes to the bag, a stack of bandages is picked up and put
## in another slot, the preview turns, the fists are chosen, and after closing the player holds
## them; then a bandage stack is dropped and lies in front of the player. Every step holds `STEP`
## seconds.
##
## Two ways to run it:
## - with Movie Maker through the kit, for a desktop-sized window:
##   `gds godot -- --path game --write-movie out/inventory.png --fixed-fps 10 --resolution
##   1920x1080 --quit-after 120 res://tools/capture/inventory_tour.tscn`
## - for a phone-sized window (Movie Maker crops a canvas wider than 1920 units), with
##   `--shots=<dir>` after the engine's `--`: each step's real window pixels are saved as a PNG:
##   `gds godot -- --path game --resolution 844x390 res://tools/capture/inventory_tour.tscn --
##   --shots=out`
## It lives in tools/, which the export leaves out.
extends Node

const STEP := 0.9
const GAME := "res://main.tscn"

var _shots := ""
var _count := 0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):
			_shots = argument.trim_prefix("--shots=")
	var game: Node = (load(GAME) as PackedScene).instantiate()
	add_child(game)
	await _hold(1.5)
	var player := get_tree().get_first_node_in_group(&"player") as Player
	player.collect(&"coin", 7)
	_press(&"inventory")
	await _hold()
	var screen := UIRouter.top() as InventoryScreen
	var cells := screen.item_cells()
	cells[0].grab_focus()
	await _hold()
	screen.press_item(0)
	cells[5].grab_focus()
	await _hold()
	screen.press_item(5)
	await _hold()
	screen.preview().turn(80.0)
	await _hold()
	screen.preview().turn(-160.0)
	await _hold()
	var fists := screen.weapon_cells()[-1]
	fists.grab_focus()
	screen.choose_weapon(fists.slot)
	await _hold()
	_press(&"inventory")
	await _hold(1.5)
	_press(&"inventory")
	await _hold()
	screen = UIRouter.top() as InventoryScreen
	screen.item_cells()[5].grab_focus()
	await _hold()
	screen.drop_selected()
	await _hold()
	_press(&"inventory")
	await _hold(1.5)
	# Leave the game the way a scene change does, so its sounds are let go of before the engine quits.
	get_tree().paused = false
	game.free()
	await get_tree().process_frame
	get_tree().quit()


# Presses and lets go of an action's first key through the input path, as a player would.
func _press(action: StringName) -> void:
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key == null:
			continue
		for pressed in [true, false]:
			var sent := key.duplicate() as InputEventKey
			sent.pressed = pressed
			Input.parse_input_event(sent)
		return


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

## Moves a pointer over the inventory's slots for a capture, over the game: the player picks up
## coins, the screen opens from the `inventory` action, then the pointer rests off the slots, on
## the pistol, the fists, the bandages, the coins, an empty slot and off again, holding each for
## `STEP` seconds and gliding between them in `GLIDE_FRAMES` frames. The pointer is real mouse
## motion through the viewport (the slots show their details on hover, as for a player) and a
## drawn arrow, since Movie Maker does not record the system cursor. It shows whether the screen
## keeps still while the details text changes.
##
## - desktop, with Movie Maker: `gds godot -- --path game --write-movie out/hover.png --fixed-fps
##   10 --resolution 1920x1080 --quit-after 110 res://tools/capture/inventory_hover_tour.tscn`
## - a phone page, one PNG a step from the real window: `gds godot -- --path game --resolution
##   1688x780 res://tools/capture/inventory_hover_tour.tscn -- --shots=out --phone`
##   (`--phone` draws the menu at the phone factor, as on an 844 x 390 page at a pixel ratio of 2).
extends Node

const STEP := 0.9
const GLIDE_FRAMES := 4
const GAME := "res://main.tscn"

var _shots := ""
var _count := 0
var _at := Vector2.ZERO
var _arrow: Polygon2D


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):
			_shots = argument.trim_prefix("--shots=")
	var game: Node = (load(GAME) as PackedScene).instantiate()
	add_child(game)
	_add_arrow()
	await _hold(1.5)
	var player := get_tree().get_first_node_in_group(&"player") as Player
	player.collect(&"coin", 7)
	_press(&"inventory")
	await _hold()
	var screen := UIRouter.top() as InventoryScreen
	if "--phone" in OS.get_cmdline_user_args():
		(screen.get_node(^"Fit") as MenuFit).force = 2
	var off := screen.get_node(^"%Title") as Control
	await _glide_to(off)
	var weapons := screen.weapon_cells()
	var items := screen.item_cells()
	var coin_slot := player.inventory.find(player.inventory.find_in_catalog(&"coin"))
	var bandage_slot := player.inventory.find(player.inventory.find_in_catalog(&"bandage"))
	var empty_slot := player.inventory.slot_count - 1
	for slot in range(player.inventory.slot_count):
		if player.inventory.is_empty(slot):
			empty_slot = slot
			break
	for target: Control in [
		weapons[0], weapons[-1], items[bandage_slot], items[coin_slot], items[empty_slot]
	]:
		await _glide_to(target)
	await _glide_to(off)
	get_tree().paused = false
	game.free()
	await get_tree().process_frame
	get_tree().quit()


func _add_arrow() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	var arrow := PackedVector2Array(
		[
			Vector2(0, 0),
			Vector2(0, 22),
			Vector2(6, 17),
			Vector2(10, 26),
			Vector2(14, 24),
			Vector2(10, 16),
			Vector2(17, 16)
		]
	)
	_arrow = Polygon2D.new()
	_arrow.polygon = arrow
	_arrow.color = Color.WHITE
	var outline := Line2D.new()
	outline.points = arrow + PackedVector2Array([arrow[0]])
	outline.width = 2.0
	outline.default_color = Color.BLACK
	_arrow.add_child(outline)
	layer.add_child(_arrow)


# Glides the pointer to the middle of `target` in a few motion events, then holds there.
func _glide_to(target: Control) -> void:
	var to := target.get_global_transform_with_canvas() * (target.size / 2.0)
	var from := _at
	for index in GLIDE_FRAMES:
		_move(from.lerp(to, float(index + 1) / GLIDE_FRAMES))
		await get_tree().process_frame
	await _hold()


func _move(at: Vector2) -> void:
	_at = at
	_arrow.position = at
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion, true)


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

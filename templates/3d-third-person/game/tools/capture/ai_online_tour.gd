## The AI online, for a clip of two screens side by side (gdstudio #970): the left half is the game
## server's own world (its real guards and allies, deciding, walking and shooting, seen by a camera
## that follows Bo's), the right half Bo's screen, where every one of them is a puppet drawn from
## the TICK's AI block and no AI runs. Guards and allies fight each other and the players; Bo kills
## a guard, which falls into a ragdoll Bo's screen makes itself from one event. The server and
## both clients run in this process over a real socket (`tests/fixtures/online_rig.gd`), each with
## a map of its own.
##
## `gds capture frames --project game --scene res://tools/capture/ai_online_tour.tscn --seconds
## 14 --fps 10`. It lives in tools/, which the export leaves out.
extends Node

const GUARD := "res://gameplay/ai/ai_guard.tscn"
const ALLY := "res://gameplay/ai/ai_ally.tscn"
const VIEW := Vector2i(960, 540)
## The AI section's floor (world/world.tscn puts it at x -25, z -9): guards at its west end,
## allies in the middle, Ada and Bo at its east end looking west.
const GUARDS: Array[Vector3] = [
	Vector3(-38.0, 0.3, -14.0),
	Vector3(-38.0, 0.3, -9.0),
	Vector3(-38.0, 0.3, -4.0),
	Vector3(-35.0, 0.3, -11.5),
	Vector3(-35.0, 0.3, -6.5),
]
const ALLIES: Array[Vector3] = [
	Vector3(-20.0, 0.3, -12.0),
	Vector3(-20.0, 0.3, -6.0),
]
const ADA_AT := Vector3(-12.0, 0.3, -11.0)
const BO_AT := Vector3(-12.0, 0.3, -7.0)
const FACING_WEST := PI / 2.0
const CHEST := 1.15
## Seconds before Bo shoots the nearest guard, and his shots' spacing.
const SHOOT_AFTER := 6.0
const SHOT_TICKS := 15

var _rig: OnlineRig
var _bo: NetClient
var _ada: NetClient
var _server_camera: Camera3D
var _guards: Array[AiCharacter] = []
var _aim: Callable = Callable()
var _presses: Array[int] = []
var _label: Label


func _ready() -> void:
	_rig = OnlineRig.new(false)
	_rig.view_size = VIEW
	add_child(_rig)
	_rig.start()
	var map := _rig.server.get_node("World")
	for spot in GUARDS:
		_guards.append(_spawn(map, GUARD, spot, -FACING_WEST))
	for spot in ALLIES:
		_spawn(map, ALLY, spot, -FACING_WEST)
	_ada = await _rig.join("Ada", 600)
	_bo = await _rig.join("Bo", 600)
	_put(_ada, ADA_AT, FACING_WEST)
	_put(_bo, BO_AT, FACING_WEST)
	_turn_camera(_bo, 90.0)
	_turn_camera(_ada, 90.0)
	_rig.controllers[1].plan = _plan
	_server_camera = Camera3D.new()
	_server_camera.current = true
	_rig.server_view.add_child(_server_camera)
	_show(_rig.server_view, 0, "The server's world (the AI runs here)")
	_show(_rig.views[1], 1, "Bo's screen (every AI drawn from the server's rows)")
	_label = Label.new()
	_label.position = Vector2(VIEW.x + 12, VIEW.y - 34)
	_label.add_theme_font_size_override(&"font_size", 18)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 4)
	add_child(_label)
	await _rig.wait(roundi(SHOOT_AFTER * NetLimits.TICK_RATE))
	var target := _nearest_guard()
	if target != null:
		var id := int(target.get_meta(NetHits.AI_META, -1))
		_aim = func() -> Vector3:
			var puppet := _bo.ai_replica.puppet_of(id)
			var at := puppet.global_position if puppet != null else target.global_position
			return at + Vector3.UP * CHEST
		var now: int = _rig.controllers[1].ticks
		for shot in 8:
			_presses.append(now + 20 + shot * SHOT_TICKS)


func _process(_delta: float) -> void:
	if _bo == null or not _bo.is_seated() or _server_camera == null:
		return
	# The server's view from where Bo's camera is.
	var camera := _bo.get_viewport().get_camera_3d()
	if camera != null:
		_server_camera.global_transform = camera.global_transform
		_server_camera.fov = camera.fov
	var dead := 0
	for guard in _guards:
		dead += 1 if is_instance_valid(guard) and guard.is_dead() else 0
	_label.text = (
		"Puppets on this screen: %d   AI on the server: %d   guards down: %d"
		% [_bo.ai_replica.count(), _rig.server.ai.rows().size(), dead]
	)


func _spawn(map: Node, scene_path: String, spot: Vector3, heading: float) -> AiCharacter:
	var body := (load(scene_path) as PackedScene).instantiate() as AiCharacter
	body.position = spot
	body.rotation.y = heading
	map.add_child(body)
	return body


func _nearest_guard() -> AiCharacter:
	var best: AiCharacter = null
	for guard in _guards:
		if not is_instance_valid(guard) or guard.is_dead():
			continue
		if (
			best == null
			or guard.global_position.distance_to(BO_AT) < best.global_position.distance_to(BO_AT)
		):
			best = guard
	return best


# Bo's command: aims at the guard with the shot block from his eye, pressing on the planned ticks.
func _plan(tick: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	var body := _bo.player
	command.yaw = body.view_yaw
	if not _aim.is_valid():
		return command
	var eye := body.global_position + Vector3.UP * body.tuning.camera_height
	var angles := CommandCodec.direction_angles((_aim.call() as Vector3) - eye)
	command.yaw = angles.x
	command.pitch = angles.y
	command.aim = true
	command.has_shot = true
	command.origin = eye
	command.shot_yaw = angles.x
	command.shot_pitch = angles.y
	command.fire_pressed = _presses.has(tick)
	return command


func _put(client: NetClient, spot: Vector3, heading: float) -> void:
	_rig.server_body(client).teleport(spot, heading)
	client.player.teleport(spot, heading)


func _turn_camera(client: NetClient, yaw: float) -> void:
	var rig := client.player.get_parent() as PlayerRig
	rig.camera_rig.yaw = yaw
	rig.camera_rig.pitch = 10.0


func _show(view: SubViewport, column: int, title: String) -> void:
	var picture := TextureRect.new()
	picture.texture = view.get_texture()
	picture.position = Vector2(column * VIEW.x, 0)
	picture.size = Vector2(VIEW)
	add_child(picture)
	var label := Label.new()
	label.text = title
	label.position = Vector2(column * VIEW.x + 12, 8)
	label.add_theme_font_size_override(&"font_size", 18)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 4)
	add_child(label)

## An AI's starts and stops seen from a client (gdstudio #1452), two views side by side: the left
## half is the game server's own world (the AI's stepped body, seen by a camera where Bo's is), the
## right half Bo's screen, where the AI is a puppet drawn from the server's rows. The AI walks,
## runs and sprints west along a clear lane, stops, turns back and runs east and stops again;
## the line under each half names the gait transition its body plays. Everything runs in this
## process (`tests/fixtures/online_rig.gd`, lockstep over a `LoopbackListener`).
##
## `gds capture frames --project game --scene res://tools/capture/ai_gait_tour.tscn --seconds 8
## --fps 30`. It lives in tools/, which the export leaves out.
extends Node

## The lane the AI runs, westwards along z = 16.6 from here, clear of the level's parts (the lane
## `test_net_ai_puppet_gait.gd` runs it along).
const START := Vector3(6.0, 0.0, 16.6)
const WEST := -PI / 2.0
## Where Bo stands, south of the lane (west of the column at x 0, z 12), his camera following
## the AI; his own body is hidden on both sides so it never stands in front of the AI.
const BO_AT := Vector3(-3.5, 0.0, 12.5)
const VIEW := Vector2i(960, 540)
## A walk's share of a full push (1.7 m/s).
const WALK_SHARE := 0.4

var _rig: OnlineRig
var _bo: NetClient
var _runner: AiCharacter
var _server_camera: Camera3D
var _labels: Array[Label] = []


func _ready() -> void:
	_rig = OnlineRig.new()
	_rig.view_size = VIEW
	add_child(_rig)
	_rig.start()
	_bo = await _rig.join("Bo")
	_rig.server_body(_bo).teleport(BO_AT, PI)
	_bo.player.teleport(BO_AT, PI)
	_bo.player.visible = false
	_rig.server_body(_bo).visible = false
	_runner = AiNetStage.walker(START)
	_runner.facing = WEST
	AiNetStage.server_map(_rig.server).add_child(_runner)
	_server_camera = Camera3D.new()
	_server_camera.current = true
	_rig.server_view.add_child(_server_camera)
	_show(_rig.server_view, 0, "The server's world (the AI's own body)")
	_show(_rig.views[0], 1, "Bo's screen (the AI drawn from the server's rows)")
	await _rig.wait(40)
	await _move("walk", Vector3.LEFT, 70)
	await _move("run", Vector3.LEFT, 50)
	await _move("sprint", Vector3.LEFT, 60)
	await _move("", Vector3.ZERO, 50)
	await _move("run", Vector3.RIGHT, 60)
	await _move("", Vector3.ZERO, 60)


func _process(_delta: float) -> void:
	if _bo == null or not _bo.is_seated() or _server_camera == null or _runner == null:
		return
	var id := int(_runner.get_meta(NetHits.AI_META, -1))
	var puppet := _bo.ai_replica.puppet_of(id)
	if puppet != null:
		var toward := puppet.global_position - _bo.player.global_position
		var rig := _bo.player.get_parent() as PlayerRig
		rig.camera_rig.yaw = rad_to_deg(atan2(-toward.x, -toward.z))
		rig.camera_rig.pitch = 6.0
	var camera := _bo.get_viewport().get_camera_3d()
	if camera != null:
		_server_camera.global_transform = camera.global_transform
		_server_camera.fov = camera.fov
	_labels[0].text = _playing(_runner)
	_labels[1].text = _playing(puppet) if puppet != null else ""


# The AI walks along `move` in `gait` for `ticks` physics ticks.
func _move(gait: String, move: Vector3, ticks: int) -> void:
	(_runner.controller as AiController).sprint = gait == "sprint"
	AiNetStage.walk(_runner, move, WALK_SHARE if gait == "walk" else 1.0)
	await _rig.wait(ticks)


# What `body`'s gait transitions play, and its speed.
static func _playing(body: Character) -> String:
	var animation := body.get_node(^"Animation") as CharacterAnimation
	var transitions := animation.gait.transitions
	var clip := String(transitions.clip).trim_prefix("gds/") if transitions.is_playing() else "-"
	return "transition: %s   %.1f m/s" % [clip, body.ground_speed()]


func _show(view: SubViewport, column: int, title: String) -> void:
	var picture := TextureRect.new()
	picture.texture = view.get_texture()
	picture.position = Vector2(column * VIEW.x, 0)
	picture.size = Vector2(VIEW)
	add_child(picture)
	for line in 2:
		var label := Label.new()
		label.text = title if line == 0 else ""
		label.position = Vector2(column * VIEW.x + 12, 8 if line == 0 else VIEW.y - 40)
		label.add_theme_font_size_override(&"font_size", 22)
		label.add_theme_color_override(&"font_outline_color", Color.BLACK)
		label.add_theme_constant_override(&"outline_size", 5)
		add_child(label)
		if line == 1:
			_labels.append(label)

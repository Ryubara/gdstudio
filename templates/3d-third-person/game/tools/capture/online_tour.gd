## Two clients of one game server, side by side, for a clip of online play: the left half is Ada's
## own screen (her body, predicted), the right half Bo's screen, where Ada is a puppet drawn from
## the server's TICKs (`RemotePlayers`). Ada walks, crouches, aims up at Bo, jumps, sprints and
## stops; Bo stands and watches her. The server and both clients run in this process
## (`tests/fixtures/online_rig.gd`, lockstep over a `LoopbackListener`), each with a map of its own.
##
## `gds capture frames --project game --scene res://tools/capture/online_tour.tscn --seconds 14
## --fps 10`. It lives in tools/, which the export leaves out.
extends Node

## Where the two stand on the open ground south of the dais: Bo looks along +Z at Ada.
const ADA_AT := Vector3(3.0, 0.0, 14.0)
const BO_AT := Vector3(3.0, 0.0, 9.0)
const VIEW := Vector2i(960, 540)

## The tour, one step a row: seconds, then the command's settings (`move` in the world's axes).
const TOUR: Array[Dictionary] = [
	{"seconds": 1.0},
	{"seconds": 1.4, "move": Vector3.RIGHT, "walk": true},
	{"seconds": 1.4, "move": Vector3.LEFT, "walk": true},
	{"seconds": 1.6, "crouch": true},
	{"seconds": 0.6},
	{"seconds": 1.8, "aim": true, "pitch": 0.3},
	{"seconds": 1.4, "move": Vector3.RIGHT, "jump": true},
	{"seconds": 1.2, "move": Vector3.LEFT, "sprint": true},
	{"seconds": 2.0},
]

var _rig: OnlineRig
var _ada: NetClient
var _bo: NetClient
var _labels: Array[Label] = []


func _ready() -> void:
	_rig = OnlineRig.new()
	_rig.view_size = VIEW
	add_child(_rig)
	_rig.start()
	_ada = await _rig.join("Ada")
	_bo = await _rig.join("Bo")
	_put(_ada, ADA_AT, PI)
	_put(_bo, BO_AT, 0.0)
	_turn_camera(_ada, 0.0)
	_turn_camera(_bo, 180.0)
	_show(_rig.views[0], 0, "Ada's screen (her own body, predicted)")
	_show(_rig.views[1], 1, "Bo's screen (Ada drawn from the server)")
	await _rig.wait(30)
	for step in TOUR:
		_rig.controllers[0].next = _command(step)
		await _rig.wait(roundi(float(step["seconds"]) * NetLimits.TICK_RATE))


func _command(step: Dictionary) -> PlayerCommand:
	var command := PlayerCommand.new()
	var move: Vector3 = step.get("move", Vector3.ZERO)
	command.set_from_world(move, Vector3.FORWARD)
	command.walk = step.get("walk", false)
	command.sprint = step.get("sprint", false)
	command.crouch = step.get("crouch", false)
	command.aim = step.get("aim", false)
	command.pitch = step.get("pitch", 0.0)
	command.jump = step.get("jump", false)
	command.jump_pressed = command.jump
	return command


func _put(client: NetClient, spot: Vector3, heading: float) -> void:
	_rig.server_body(client).teleport(spot, heading)
	client.player.teleport(spot, heading)


func _turn_camera(client: NetClient, yaw: float) -> void:
	var rig := client.player.get_parent() as PlayerRig
	rig.camera_rig.yaw = yaw
	rig.camera_rig.pitch = 8.0


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
	_labels.append(label)

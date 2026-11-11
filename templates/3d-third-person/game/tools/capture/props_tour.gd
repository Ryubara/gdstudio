## Two clients of one game server over a real socket, side by side, for a clip of the map's
## networked props and targets: the left half is Ada's own screen, the right half Bo's, where Ada is
## a puppet and every crate and target is where the server's records put it. Ada pushes a 5 kg
## crate (`PushCube2`, moved west and lightened on every peer, as `test_net_props.gd` does), then
## the 60 kg cube beside it, then shoots a target, which falls and stands again on both screens
## when the server's does. The server and both clients run in this process
## (`tests/fixtures/online_rig.gd`), each with a map of its own.
##
## `gds capture frames --project game --scene res://tools/capture/props_tour.tscn --seconds 18
## --fps 10`. It lives in tools/, which the export leaves out.
extends Node

const VIEW := Vector2i(960, 540)
const CRATE := "PushCube2"
const CRATE_AT := Vector3(-9.0, 0.5, 19.0)
const CUBE := "PushCube1"
## Ada starts this far south of a prop, facing north; Bo watches from the east.
const BEHIND := 1.3
const BO_AT := Vector3(-2.5, 0.0, 13.0)
const BO_LOOKS := 125.0
const SHOOT_ADA := Vector3(-3.0, 0.3, -10.0)
const SHOOT_BO := Vector3(-6.5, 0.3, -9.0)

var _rig: OnlineRig
var _ada: NetClient
var _bo: NetClient
var _command := PlayerCommand.new()


func _ready() -> void:
	_rig = OnlineRig.new(false)
	_rig.view_size = VIEW
	_rig.prepare_server = _make_crate
	_rig.prepare_arena = _make_crate
	add_child(_rig)
	_rig.start()
	_ada = await _rig.join("Ada")
	_bo = await _rig.join("Bo")
	_rig.controllers[0].plan = func(_tick: int) -> PlayerCommand: return _command
	_show(_rig.views[0], 0, "Ada's screen (player 1): she pushes")
	_show(_rig.views[1], 1, "Bo's screen (player 2): the props and targets from the server")
	await _push(CRATE)
	await _push(CUBE)
	await _shoot()


# The same 5 kg crate in every peer's map.
static func _make_crate(scene: Node) -> void:
	var crate := scene.find_child(CRATE, true, false) as PhysicsProp
	crate.position = CRATE_AT
	crate.weight = 5.0
	crate.push_speed = 0.0


# Ada walks north into the prop for 2.5 s, Bo watching from the east.
func _push(prop_name: String) -> void:
	var prop := _rig.server_view.find_child(prop_name, true, false) as PhysicsProp
	var start := prop.global_position
	_put(_ada, Vector3(start.x, 0.0, start.z + BEHIND), 0.0, 25.0)
	_put(_bo, BO_AT, BO_LOOKS, 22.0)
	_walk(Vector2.ZERO)
	await _rig.wait(20)
	_walk(Vector2(0.0, 1.0))
	await _rig.wait(150)
	_walk(Vector2.ZERO)
	await _rig.wait(40)


# Ada aims at `TargetB` and fires once; the board falls and stands up 3 s later on both screens.
func _shoot() -> void:
	_put(_ada, SHOOT_ADA, 0.0, 10.0)
	_put(_bo, SHOOT_BO, -28.0, 8.0)
	var target := _rig.server_view.find_child("TargetB", true, false) as Target
	var board := target.global_position + Vector3.UP * 0.9
	var body := _ada.player
	await _rig.wait(20)
	for index in 260:
		var eye := body.global_position + Vector3.UP * body.tuning.camera_height
		var angles := CommandCodec.direction_angles(board - eye)
		var command := PlayerCommand.new()
		command.yaw = angles.x
		command.pitch = angles.y
		command.aim = true
		command.has_shot = true
		command.origin = eye
		command.shot_yaw = angles.x
		command.shot_pitch = angles.y
		command.fire_pressed = index == 30
		_command = command
		await get_tree().physics_frame


func _walk(move: Vector2) -> void:
	var command := PlayerCommand.new()
	command.yaw = 0.0
	command.move = move
	_command = command


# Puts a client's body and its server body at one spot, the camera looking `camera_yaw` degrees
# (0 along -Z, 90 along -X) and `pitch` down.
func _put(client: NetClient, spot: Vector3, camera_yaw: float, pitch: float) -> void:
	var facing := deg_to_rad(camera_yaw) + PI
	_rig.server_body(client).teleport(spot, facing)
	client.player.teleport(spot, facing)
	var rig := client.player.get_parent() as PlayerRig
	rig.camera_rig.yaw = camera_yaw
	rig.camera_rig.pitch = pitch


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

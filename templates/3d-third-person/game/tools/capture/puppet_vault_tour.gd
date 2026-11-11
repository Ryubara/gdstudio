## A player vaulting the course, seen from two screens of one game server side by side: the left
## half is Ada's own screen (her body, stepped and predicted), the right half Bo's, where Ada is a
## puppet drawn from the server's TICKs that plans the same crossings itself (`PuppetVault`) and
## plays the clips the stepping body plays. Ada runs east over the course's 0.5, 0.9 and 1.2 m walls
## and mantles the 1.6 m one; Bo stands south of the course and watches. Everything runs in this
## process (`tests/fixtures/online_rig.gd`, lockstep over a `LoopbackListener`).
##
## `gds capture frames --project game --scene res://tools/capture/puppet_vault_tour.tscn
## --seconds 8 --fps 10`. It lives in tools/, which the export leaves out.
extends Node

const ADA_AT := Vector3(-19.4, 0.0, -12.0)
const BO_AT := Vector3(-14.4, 0.0, -7.4)
const VIEW := Vector2i(960, 540)
## The west faces of the walls Ada crosses (x), in order.
const FACES: Array[float] = [-18.2, -15.7, -13.25, -11.0]
## Metres before a face (past the body's radius) the jump is pressed.
const PRESS_BEFORE := 0.6

var _rig: OnlineRig
var _ada: NetClient
var _bo: NetClient


func _ready() -> void:
	_rig = OnlineRig.new()
	_rig.view_size = VIEW
	add_child(_rig)
	_rig.start()
	_ada = await _rig.join("Ada")
	_bo = await _rig.join("Bo")
	_put(_ada, ADA_AT, PI / 2.0)
	_put(_bo, BO_AT, PI)
	_turn_camera(_ada, -90.0, 12.0)
	_turn_camera(_bo, 0.0, 20.0)
	_show(_rig.views[0], 0, "Ada's screen (her own body)")
	_show(_rig.views[1], 1, "Bo's screen (Ada drawn from the server)")
	await _rig.wait(40)
	var radius := _ada.player.tuning.radius
	var next := 0
	for _tick in 6 * NetLimits.TICK_RATE:
		var command := PlayerCommand.new()
		command.set_from_world(Vector3.RIGHT if next < FACES.size() else Vector3.ZERO)
		if (
			next < FACES.size()
			and _ada.player.global_position.x >= FACES[next] - radius - PRESS_BEFORE
		):
			command.jump = true
			command.jump_pressed = true
			next += 1
		_rig.controllers[0].next = command
		await get_tree().physics_frame


func _put(client: NetClient, spot: Vector3, heading: float) -> void:
	_rig.server_body(client).teleport(spot, heading)
	client.player.teleport(spot, heading)


func _turn_camera(client: NetClient, yaw: float, pitch: float) -> void:
	var rig := client.player.get_parent() as PlayerRig
	rig.camera_rig.yaw = yaw
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

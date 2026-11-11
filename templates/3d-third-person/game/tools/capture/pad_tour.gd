## Two clients of one game server over a real socket, side by side, for a clip of the pressure pad
## online: the left half is Ada's own screen, the right half Bo's, where Ada is a puppet. Ada walks
## onto the pad and the room's door opens, she stands, then walks back off; on Bo's screen the plate
## turns green and back by the server's word alone (his copy of the pad senses nothing). The
## server and both clients run in this process (`tests/fixtures/online_rig.gd`), each with a map
## of its own.
##
## `gds capture frames --project game --scene res://tools/capture/pad_tour.tscn --seconds 9
## --fps 10`. It lives in tools/, which the export leaves out.
extends Node

const VIEW := Vector2i(960, 540)
## Where Ada starts (south of the pad, looking along -Z) and where Bo stands, his camera turned
## toward the pad and the door (degrees, 0 along -Z, 90 along -X).
const ADA_START := Vector3(13.0, 0.0, -0.5)
const BO_SPOT := Vector3(8.5, 0.0, -0.5)
const BO_YAW := -40.0

var _rig: OnlineRig
var _ada: NetClient
var _bo: NetClient


func _ready() -> void:
	_rig = OnlineRig.new(false)
	_rig.view_size = VIEW
	add_child(_rig)
	_rig.start()
	_ada = await _rig.join("Ada")
	_bo = await _rig.join("Bo")
	_show(_rig.views[0], 0, "Ada's screen (player 1)")
	_show(_rig.views[1], 1, "Bo's screen (player 2): the pad from the server")
	_put(_ada, ADA_START, 0.0)
	_put(_bo, BO_SPOT, BO_YAW)
	await _rig.wait(30)
	var pad := _rig.server_view.find_child("PressurePad", true, false) as TriggerZone
	_command(Vector2(0.0, 1.0))
	await _rig.until(pad.is_active, 180)
	await _rig.wait(12)
	_command(Vector2.ZERO)
	await _rig.wait(150)
	_command(Vector2(0.0, -1.0))
	await _rig.until(func() -> bool: return not pad.is_active(), 180)
	await _rig.wait(20)
	_command(Vector2.ZERO)


# Ada's next command: a push in her view's axes (she looks along -Z).
func _command(move: Vector2) -> void:
	var command := PlayerCommand.new()
	command.yaw = 0.0
	command.move = move
	_rig.controllers[0].next = command


# Puts a client's body and its server body at one spot, the camera looking `camera_yaw` degrees.
func _put(client: NetClient, spot: Vector3, camera_yaw: float) -> void:
	var facing := deg_to_rad(camera_yaw) + PI
	_rig.server_body(client).teleport(spot, facing)
	client.player.teleport(spot, facing)
	var rig := client.player.get_parent() as PlayerRig
	rig.camera_rig.yaw = camera_yaw
	rig.camera_rig.pitch = 15.0


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

## Two clients of one game server over a real socket, side by side, for a clip of the map's
## networked parts: the left half is Ada's own screen, the right half Bo's, where Ada is a puppet
## and the door, the shuttle and the coin are where the server's records put them. Ada opens the
## room's door and walks in, rides the shuttle from the far landing to the near one, and takes the
## coin on the far landing; Bo watches each from the ground. The server and both clients run in
## this process (`tests/fixtures/online_rig.gd`), each with a map of its own.
##
## `gds capture frames --project game --scene res://tools/capture/map_parts_tour.tscn --seconds 24
## --fps 10`. It lives in tools/, which the export leaves out.
extends Node

const VIEW := Vector2i(960, 540)
## Each scene: where Ada starts and faces, where Bo stands and the way his camera looks (degrees,
## 0 along -Z, 90 along -X).
const DOOR_ADA := Vector3(13.0, 0.0, -8.3)
const DOOR_BO := Vector3(11.5, 0.0, -1.0)
const RIDE_ADA := Vector3(18.0, 2.0, 13.6)
const RIDE_BO := Vector3(21.5, 2.0, 2.5)
const COIN_ADA := Vector3(18.0, 2.0, 18.8)
const COIN_BO := Vector3(21.0, 2.0, 12.6)

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
	_show(_rig.views[1], 1, "Bo's screen (player 2): door, shuttle and coin from the server")
	await _door()
	await _ride()
	await _coin()


# Ada opens the room's door with her interact button and walks in.
func _door() -> void:
	_put(_ada, DOOR_ADA, 0.0)
	_put(_bo, DOOR_BO, -10.0)
	await _rig.wait(20)
	_command(Vector2.ZERO, true)
	await _rig.wait(70)
	_command(Vector2(0.0, 1.0))
	await _rig.wait(70)
	_command(Vector2.ZERO)
	await _rig.wait(20)


# Ada waits on the far landing for the shuttle, walks onto it and rides it to the near landing.
func _ride() -> void:
	_put(_ada, RIDE_ADA, 0.0)
	_put(_bo, RIDE_BO, 150.0)
	var shuttle := _rig.views[0].find_child("Shuttle", true, false) as MovingPlatform
	await _rig.until(
		func() -> bool:
			var ride := shuttle.ride_at(_ada.seq)
			return ride.wait > 1.2 and ride.distance >= shuttle.travel.length() - 0.001,
		600
	)
	_command(Vector2(0.0, 1.0))
	await _rig.until(
		func() -> bool: return _ada.player.global_position.z < shuttle.global_position.z + 0.6
	)
	_command(Vector2.ZERO)
	await _rig.until(func() -> bool: return shuttle.ride_at(_ada.seq).distance <= 0.001, 300)
	_command(Vector2(0.0, 1.0))
	await _rig.wait(40)
	_command(Vector2.ZERO)
	await _rig.wait(10)


# Ada walks into the coin on the far landing.
func _coin() -> void:
	_put(_ada, COIN_ADA, 0.0)
	_put(_bo, COIN_BO, 139.0)
	await _rig.wait(20)
	_command(Vector2(0.0, 1.0))
	await _rig.wait(60)
	_command(Vector2.ZERO)
	await _rig.wait(30)


# Ada's next commands: a push in her view's axes (she looks along -Z), the interact press, a walk.
func _command(move: Vector2, interact := false, walk := false) -> void:
	var command := PlayerCommand.new()
	command.yaw = 0.0
	command.move = move
	command.walk = walk
	command.interact_pressed = interact
	_rig.controllers[0].next = command


# Puts a client's body and its server body at one spot, the camera looking `camera_yaw` degrees.
func _put(client: NetClient, spot: Vector3, camera_yaw: float) -> void:
	var facing := deg_to_rad(camera_yaw) + PI
	_rig.server_body(client).teleport(spot, facing)
	client.player.teleport(spot, facing)
	var rig := client.player.get_parent() as PlayerRig
	rig.camera_rig.yaw = camera_yaw
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

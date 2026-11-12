## A player shooting while sliding, seen from two screens of one game server side by side
## (kit #1277): the left half is Ada's own screen (her body, stepped and predicted, the camera
## behind her turning with her aim), the right half Bo's, where Ada is a puppet drawn from the
## server's TICKs. Ada sprints west, drops into a slide and aims 50 degrees to her left, then 50
## to her right, firing once at each; the aim's heading off the body comes in her entry, so Bo's
## puppet turns its upper body and points the pistol the same way while the body slides on along
## its line. Bo stands ahead of the slide, a little to its side, his camera following her.
## Everything runs in this process (`tests/fixtures/online_rig.gd`, lockstep over a
## `LoopbackListener`).
##
## `gds capture frames --project game --scene res://tools/capture/puppet_aim_tour.tscn
## --seconds 5 --fps 10`. It lives in tools/, which the export leaves out.
extends Node

## The lane Ada slides down, westwards along z = 16.6, clear of the level's parts.
const ADA_AT := Vector3(5.0, 0.0, 16.6)
const WEST := -PI / 2.0
const BO_AT := Vector3(-9.5, 0.0, 15.2)
const VIEW := Vector2i(960, 540)
## Degrees Ada aims off the slide, to her left and then to her right.
const AIM := 50.0
## Ticks of each part: the run, the drop into the slide, each aim.
const RUN_TICKS := 30
const DROP_TICKS := 4
const AIM_TICKS := 32
## Degrees a tick Ada's camera turns toward her aim.
const CAMERA_TURN := 5.0

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
	# A long, slow slide (a copy of the tuning, on the server and on Ada's screen alike), so each
	# aim is held well inside it.
	var long_slide := _ada.player.slide_tuning.duplicate() as SlideTuning
	long_slide.max_time = 3.0
	long_slide.friction = 0.4
	long_slide.drag = 0.0
	_ada.player.slide_tuning = long_slide
	_rig.server_body(_ada).slide_tuning = long_slide
	_put(_ada, ADA_AT, WEST)
	_put(_bo, BO_AT, PI / 2.0)
	_turn_camera(_ada, 90.0, 10.0)
	_turn_camera(_bo, -90.0, 8.0)
	_show(_rig.views[0], 0, "Ada's screen (her own body)")
	_show(_rig.views[1], 1, "Bo's screen (Ada drawn from the server)")
	await _rig.wait(30)
	await _drive(0.0, false, false, RUN_TICKS)
	await _drive(0.0, true, false, DROP_TICKS)
	await _drive(AIM, true, true, AIM_TICKS)
	await _drive(-AIM, true, true, AIM_TICKS)
	await _drive(-AIM, true, true, 16)


# Ada runs west looking `look` degrees to her left, sliding with `crouch`, aiming with `aim`; a
# shot halfway through an aim.
func _drive(look: float, crouch: bool, aim: bool, ticks: int) -> void:
	var rig := _ada.player.get_parent() as PlayerRig
	for tick in ticks:
		var command := CommandDriver.walking(
			Vector3.LEFT, CommandCodec.direction_from_angles(WEST + PI + deg_to_rad(look), 0.0)
		)
		command.sprint = true
		command.crouch = crouch
		command.aim = aim
		command.fire = aim and tick == ticks / 2
		command.fire_pressed = command.fire
		_rig.controllers[0].next = command
		rig.camera_rig.yaw = move_toward(rig.camera_rig.yaw, 90.0 + look, CAMERA_TURN)
		_follow_with_bo()
		await get_tree().physics_frame


# Bo's camera turns to keep Ada's puppet in view.
func _follow_with_bo() -> void:
	var puppet := _bo.remote_players.puppet_at(_ada.slot)
	if puppet == null:
		return
	var toward := puppet.global_position - _bo.player.global_position
	var rig := _bo.player.get_parent() as PlayerRig
	rig.camera_rig.yaw = rad_to_deg(atan2(-toward.x, -toward.z))


func _put(client: NetClient, spot: Vector3, heading: float) -> void:
	_rig.server_body(client).teleport(spot, heading)
	client.player.teleport(spot, heading)
	var stand := PlayerCommand.new()
	stand.yaw = heading - PI
	_rig.controllers[_rig.clients.find(client)].next = stand


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

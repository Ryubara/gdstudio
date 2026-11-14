## A bandage used online, seen from two screens of one game server side by side (gdstudio #1386):
## the left half is Ada's own screen (her body, which starts the use at her press), the right half
## Bo's, where Ada is a puppet that plays the clip and the sound from the server's USE event alone.
## Ada is hurt to 40; she presses the first hotbar place, both bodies lower the aim and bring the
## left hand to the face, and at 75% of the use the server heals her 25 and takes one bandage: her
## health and count follow on her screen, the puppet's health on Bo's. Each screen's line shows
## Ada's health and bandages as that screen has them. Everything runs in this process
## (`tests/fixtures/online_rig.gd`, lockstep over a `LoopbackListener`).
##
## `gds capture frames --project game --scene res://tools/capture/online_heal_tour.tscn
## --seconds 7 --fps 10`. It lives in tools/, which the export leaves out.
extends Node

const ADA_AT := Vector3(5.0, 0.0, 16.6)
## Bo stands 2 m in front of Ada and a little to her right, looking at her.
const BO_AT := Vector3(4.1, 0.0, 14.8)
## Each screen is half of the 1920 x 1080 window, upright.
const VIEW := Vector2i(960, 1080)
const HURT := 40
## Ticks before the press (past the first second of the join, while the views settle).
const LEAD_TICKS := 130

var _rig: OnlineRig
var _ada: NetClient
var _bo: NetClient
var _lines: Array[Label] = []


func _ready() -> void:
	_rig = OnlineRig.new()
	_rig.view_size = VIEW
	add_child(_rig)
	_rig.start()
	_ada = await _rig.join("Ada")
	_bo = await _rig.join("Bo")
	# The camera's heading from Ada to Bo (0 faces -Z); a body's heading is the camera's less a
	# half turn.
	var toward_bo := BO_AT - ADA_AT
	var ada_look := atan2(-toward_bo.x, -toward_bo.z)
	_put(_ada, ADA_AT, ada_look - PI)
	_put(_bo, BO_AT, ada_look)
	_turn_camera(_ada, rad_to_deg(ada_look), 12.0)
	_show(_rig.views[0], 0, "Ada's screen (her own body)")
	_show(_rig.views[1], 1, "Bo's screen (Ada drawn from the server)")
	await _rig.wait(20)
	Health.of(_rig.server_body(_ada)).set_wire_value(HURT)
	Health.of(_ada.player).set_wire_value(HURT)
	var puppet := _bo.remote_players.puppet_at(_ada.slot)
	if puppet != null:
		Health.of(puppet).set_wire_value(HURT)
	for tick in LEAD_TICKS + 200:
		if tick == LEAD_TICKS:
			_rig.controllers[0].next.use_place = 0
		_follow_with_bo()
		_write_lines()
		await get_tree().physics_frame


# Bo's camera keeps Ada's puppet in view, from her front.
func _follow_with_bo() -> void:
	var puppet := _bo.remote_players.puppet_at(_ada.slot)
	if puppet == null:
		return
	var toward := puppet.global_position - _bo.player.global_position
	var rig := _bo.player.get_parent() as PlayerRig
	rig.camera_rig.yaw = rad_to_deg(atan2(-toward.x, -toward.z))
	rig.camera_rig.pitch = 8.0


func _write_lines() -> void:
	var puppet := _bo.remote_players.puppet_at(_ada.slot)
	var own := Hotbar.of(_ada.player)
	_lines[0].text = (
		"Ada: health %d, bandages %d%s"
		% [
			roundi(Health.of(_ada.player).value),
			own.count_at(0),
			"  (using)" if ItemUse.of(_ada.player).is_using() else ""
		]
	)
	if puppet != null:
		_lines[1].text = (
			"Ada's puppet: health %d%s"
			% [
				roundi(Health.of(puppet).value),
				"  (using)" if ItemUse.of(puppet).is_using() else ""
			]
		)


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
	for row in 2:
		var label := Label.new()
		label.text = title if row == 0 else ""
		label.position = Vector2(column * VIEW.x + 12, 8 + row * 28)
		label.add_theme_font_size_override(&"font_size", 18)
		label.add_theme_color_override(&"font_outline_color", Color.BLACK)
		label.add_theme_constant_override(&"outline_size", 4)
		add_child(label)
		if row == 1:
			_lines.append(label)

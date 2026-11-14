## The gait transitions (the starts, stops, the sprint reversal, a pivot and the turns on the spot
## of kit #1156, #1157 and #1158) seen from two screens of one game server side by side
## (gdstudio #1367): the left half is Ada's own screen (her body, stepped and predicted), the right
## half Bo's, where Ada is a puppet drawn from the server's TICKs. Both cameras look at her from
## the north, across the lane she runs along (z = 16.6, x from 5 to -10, clear of the level's
## parts), so a stop's slide and a start's first step read from the side.
##
## Every physics frame it prints one line starting `PUPPETGAIT`: the frame (shown on the screen
## too), the part, then for Ada's own body and for Bo's puppet of her the ground speed, the x and z
## of the body, the tree's body state, the transition clip that plays (`-` for none), the largest
## turn of one bone since the frame before in degrees and its bone (`PoseJump`), the momentum
## blend's offset in degrees and the poses drawn so far. A snap shows as a jump far past the clips'
## own motion; a stop that plays in place as a speed at 0 while the stop clip goes on.
##
## `gds capture frames --project game --scene res://tools/capture/puppet_gait_tour.tscn
## --seconds 20 --fps 60` (one movie frame a physics frame, so the frame on the screen is the
## PNG's number). Everything runs in this process (`tests/fixtures/online_rig.gd`, lockstep over a
## `LoopbackListener`). It lives in tools/, which the export leaves out.
extends Node

const LANE_Z := 16.6
const EAST_END := 4.5
const WEST_END := -9.0
## Where Bo watches from: beside the lane's east half, and beside its west half for the sprint.
const BO_AT := Vector3(3.5, 0.0, 14.0)
const BO_WEST_AT := Vector3(-4.5, 0.0, 14.0)
## Degrees Bo's camera looks past Ada, so his own body stands beside her on his screen.
const BO_LOOK_PAST := 14.0
const VIEW := Vector2i(960, 540)
const WEST := Vector3.LEFT
const EAST := Vector3.RIGHT
const NORTH := Vector3.FORWARD
## The parts: a title, physics frames, the way to move (zero: stand), the gait (`walk`, `jog`,
## `sprint`), the way to look while standing and aiming (zero: along the facing, no aim).
const PARTS: Array[Array] = [
	["Stand", 40, Vector3.ZERO, "", Vector3.ZERO],
	["Walk start", 80, WEST, "walk", Vector3.ZERO],
	["Walk stop", 60, Vector3.ZERO, "", Vector3.ZERO],
	["Jog start", 60, WEST, "jog", Vector3.ZERO],
	["Jog stop", 70, Vector3.ZERO, "", Vector3.ZERO],
	["@west_end", 40, Vector3.ZERO, "", Vector3.ZERO],
	["Sprint start", 60, EAST, "sprint", Vector3.ZERO],
	["Sprint reversal", 80, WEST, "sprint", Vector3.ZERO],
	["Sprint stop", 80, Vector3.ZERO, "", Vector3.ZERO],
	["@east_end", 40, Vector3.ZERO, "", Vector3.ZERO],
	["Jog", 30, WEST, "jog", Vector3.ZERO],
	["Jog pivot 90 to the north", 60, NORTH, "jog", Vector3.ZERO],
	["Jog stop", 60, Vector3.ZERO, "", Vector3.ZERO],
	["@east_end", 40, Vector3.ZERO, "", Vector3.ZERO],
	["Turn on the spot 90, aiming", 70, Vector3.ZERO, "", NORTH],
	["Turn on the spot 180, aiming", 90, Vector3.ZERO, "", Vector3.BACK],
	["Stand", 30, Vector3.ZERO, "", Vector3.ZERO],
]

var _rig: OnlineRig
var _ada: NetClient
var _bo: NetClient
var _frame := 0
var _part := ""
var _label: Label
var _own_jump: PoseJump
var _puppet_jump: PoseJump


func _ready() -> void:
	_rig = OnlineRig.new()
	_rig.view_size = VIEW
	add_child(_rig)
	_rig.start()
	_ada = await _rig.join("Ada")
	_bo = await _rig.join("Bo")
	_put(_ada, Vector3(EAST_END, 0.0, LANE_Z), -PI / 2.0)
	_put(_bo, BO_AT, 0.0)
	_turn_camera(_ada, 180.0, 12.0)
	_turn_camera(_bo, 180.0, 12.0)
	_show(_rig.views[0], 0, "Ada's screen (her own body)")
	_show(_rig.views[1], 1, "Bo's screen (Ada drawn from the server)")
	_build_label()
	await _rig.wait(30)
	var puppet := _bo.remote_players.puppet_at(_ada.slot)
	_own_jump = PoseJump.new(_ada.player.model.skeleton())
	_puppet_jump = PoseJump.new(puppet.model.skeleton())
	for part: Array in PARTS:
		await _play(part)
	_finish()


func _play(part: Array) -> void:
	var title: String = part[0]
	if title.begins_with("@"):
		# Moved back to an end of the lane, standing, before the next moves; Bo goes beside it.
		var east := title == "@east_end"
		var heading := -PI / 2.0 if east else PI / 2.0
		_put(_ada, Vector3(EAST_END if east else WEST_END, 0.0, LANE_Z), heading)
		_put(_bo, BO_AT if east else BO_WEST_AT, 0.0)
		_own_jump.forget()
		_puppet_jump.forget()
		title = "(moved to the lane's %s end)" % ("east" if east else "west")
	_part = title
	for _tick in int(part[1]):
		_rig.controllers[0].next = _command(part[2], part[3], part[4])
		_follow_with_cameras()
		await get_tree().physics_frame
		_frame += 1
		_report()


# What Ada presses this frame.
func _command(move: Vector3, gait: String, look: Vector3) -> PlayerCommand:
	var body := _ada.player
	var facing := Vector3.BACK.rotated(Vector3.UP, body.facing)
	var command := CommandDriver.walking(
		move, move if move != Vector3.ZERO else (look if look != Vector3.ZERO else facing)
	)
	command.walk = gait == "walk"
	command.sprint = gait == "sprint"
	command.aim = look != Vector3.ZERO
	return command


# Both cameras keep Ada in the middle of their screen from where they are.
func _follow_with_cameras() -> void:
	var puppet := _bo.remote_players.puppet_at(_ada.slot)
	if puppet == null:
		return
	var toward := puppet.global_position - _bo.player.global_position
	(_bo.player.get_parent() as PlayerRig).camera_rig.yaw = (
		rad_to_deg(atan2(-toward.x, -toward.z)) + BO_LOOK_PAST
	)
	(_ada.player.get_parent() as PlayerRig).camera_rig.yaw = 180.0


func _report() -> void:
	var puppet := _bo.remote_players.puppet_at(_ada.slot)
	var own := _side(_ada.player, _own_jump)
	var drawn := _side(puppet, _puppet_jump)
	print("PUPPETGAIT %d %s | own %s | puppet %s" % [_frame, _part.replace(" ", "_"), own, drawn])
	_label.text = "frame %d   %s\nAda's own:  %s\nBo's puppet: %s" % [_frame, _part, own, drawn]


func _side(body: Player, jump: PoseJump) -> String:
	var animation := body.get_node(^"Animation") as CharacterAnimation
	var clip := String(animation.gait.transitions.clip)
	var momentum := animation.gait.momentum
	var offset := rad_to_deg(momentum.largest_offset()) if momentum != null else 0.0
	return (
		"%.2f m/s x %.2f z %.2f %s %s jump %.1f %s mom %.1f poses %d"
		% [
			body.ground_speed(),
			body.global_position.x,
			body.global_position.z,
			animation.body_state(),
			clip.get_file() if clip != "" else "-",
			jump.degrees,
			jump.bone if jump.bone != "" else "-",
			offset,
			jump.poses,
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
	var label := Label.new()
	label.text = title
	label.position = Vector2(column * VIEW.x + 12, 8)
	label.add_theme_font_size_override(&"font_size", 18)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 4)
	add_child(label)


func _build_label() -> void:
	_label = Label.new()
	_label.position = Vector2(12, VIEW.y - 92)
	_label.add_theme_font_size_override(&"font_size", 16)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 4)
	add_child(_label)


func _finish() -> void:
	AudioSettings.stop_players(get_tree().root)
	for _frame_count in 8:
		await get_tree().process_frame
	get_tree().quit()

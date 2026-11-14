## The jump's states of gdstudio #1371 seen from two screens of one game server side by side, as
## `puppet_gait_tour.gd` films the gait transitions: the left half is Ada's own screen (her body,
## stepped and predicted), the right half Bo's, where Ada is a puppet drawn from the server's TICKs
## and picks the same clips from what it is drawn with. Both cameras look at her across the lane
## she runs along (z = 16.6, clear of the level's parts).
##
## The parts: a standing jump (the standing take-off, the air, the soft landing), a jog with a
## running jump off the left foot and one off the right (each pressed while that foot is down,
## the landings into the run), and a drop from 3 m (the hard landing, played through its settle).
##
## Every physics frame it prints one line starting `JUMPTOUR`: the frame (shown on the screen too),
## the part, then for Ada's own body and for Bo's puppet of her the tree's body state, the take-off
## and the landing last picked, the vertical speed and the largest turn of one bone since the frame
## before (`PoseJump`).
##
## `gds capture frames --project game --scene res://tools/capture/jump_tour.tscn --seconds 16
## --fps 60` (one movie frame a physics frame). Everything runs in this process
## (`tests/fixtures/online_rig.gd`). It lives in tools/, which the export leaves out.
extends Node

const LANE_Z := 16.6
const EAST_END := 4.5
const BO_AT := Vector3(1.5, 0.0, 13.5)
const BO_LOOK_PAST := 14.0
const VIEW := Vector2i(960, 540)
const WEST := Vector3.LEFT
## The parts: a title, physics frames, the way to move (zero: stand), what to do: `jump` (pressed
## on the first frame), `left` or `right` (pressed once the jog's left or right foot is down),
## `drop` (put 3 m up on the first frame), `` nothing.
const PARTS: Array[Array] = [
	["Stand", 40, Vector3.ZERO, ""],
	["Standing jump", 80, Vector3.ZERO, "jump"],
	["Jog", 50, WEST, ""],
	["Running jump off the left foot", 70, WEST, "left"],
	["Jog", 20, WEST, ""],
	["Running jump off the right foot", 70, WEST, "right"],
	["Stop", 60, Vector3.ZERO, ""],
	["@east_end", 30, Vector3.ZERO, ""],
	["Drop from 3 m", 150, Vector3.ZERO, "drop"],
]
const DROP := 3.0

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
	_turn_camera(_ada, 180.0, 22.0)
	_turn_camera(_bo, 180.0, 8.0)
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
		_put(_ada, Vector3(EAST_END, 0.0, LANE_Z), -PI / 2.0)
		_own_jump.forget()
		_puppet_jump.forget()
		title = "(moved to the lane's east end)"
	_part = title
	var what: String = part[3]
	var pressed := false
	for tick in int(part[1]):
		var press := false
		match what:
			"jump":
				press = tick == 0
			"left", "right":
				press = not pressed and _foot_down() == what.left(1)
			"drop":
				if tick == 0:
					var up := _ada.player.global_position + Vector3.UP * DROP
					_rig.server_body(_ada).teleport(up, _ada.player.facing)
					_ada.player.teleport(up, _ada.player.facing)
		pressed = pressed or press
		_rig.controllers[0].next = _command(part[2], press, pressed and tick < 30)
		_follow_with_cameras()
		await get_tree().physics_frame
		_frame += 1
		_report()


# The foot of Ada's own jog that is down now (`l`, `r`), or `` in its flights.
func _foot_down() -> String:
	var animation := _ada.player.get_node(^"Animation") as CharacterAnimation
	var phase := animation.gait.blend.phase(animation.tree, CharacterAnimation.GROUND)
	return GaitClips.planted_foot(CharacterClips.RUN, phase)


# What Ada presses this frame.
func _command(move: Vector3, press: bool, hold: bool) -> PlayerCommand:
	var body := _ada.player
	var facing := Vector3.BACK.rotated(Vector3.UP, body.facing)
	var command := CommandDriver.walking(move, move if move != Vector3.ZERO else facing)
	command.jump_pressed = press
	command.jump = press or hold
	return command


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
	print("JUMPTOUR %d %s | own %s | puppet %s" % [_frame, _part.replace(" ", "_"), own, drawn])
	_label.text = "frame %d   %s\nAda's own:  %s\nBo's puppet: %s" % [_frame, _part, own, drawn]


func _side(body: Player, jump: PoseJump) -> String:
	var animation := body.get_node(^"Animation") as CharacterAnimation
	var picks := animation.gait.jump
	return (
		"%s off %s land %s (%.1f m/s) vy %.2f jump %.1f %s"
		% [
			animation.body_state(),
			String(picks.takeoff).get_file() if picks.takeoff != &"" else "-",
			String(picks.landing).get_file() if picks.landing != &"" else "-",
			picks.fall_speed,
			body.velocity.y,
			jump.degrees,
			jump.bone if jump.bone != "" else "-",
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

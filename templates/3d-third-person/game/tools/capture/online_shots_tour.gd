## Shots, hits and deaths online, for a clip from both game cameras: the left half is Ada's own
## screen, the right half Bo's, where Ada is a puppet drawn from the server. Ada shoots a target
## (on Bo's screen her puppet's pistol flashes, a cosmetic round flies, the impact plays and the
## board falls by the server's word), then Bo shoots Ada three times: her health falls on both
## screens, she dies into a ragdoll each screen makes itself (no bone is sent) and gets up where
## the server says. The server and both clients run in this process (`tests/fixtures/online_rig.gd`,
## lockstep over a `LoopbackListener`), each with a map of its own.
##
## `gds capture frames --project game --scene res://tools/capture/online_shots_tour.tscn --seconds
## 12 --fps 10`. It lives in tools/, which the export leaves out.
extends Node

## Ada stands behind `TargetB`, Bo behind her on her right, both looking toward the targets.
const ADA_AT := Vector3(-3.0, 0.3, -10.0)
const BO_AT := Vector3(-0.3, 0.3, -4.5)
const VIEW := Vector2i(960, 540)
## The board of `TargetB` and where a body is aimed at, above its feet.
const BOARD := Vector3(-3.0, 0.9, -15.2)
const CHEST := 1.15
## Seconds the dead lie before the server gets them up.
const REVIVE_SECONDS := 2.5

var _rig: OnlineRig
var _ada: NetClient
var _bo: NetClient
## Each controller's aim (a Callable answering a point, or none) and the ticks it presses fire on.
var _aims: Array[Callable] = [Callable(), Callable()]
var _presses: Array[Array] = [[], []]
var _health_labels: Array[Label] = []


func _ready() -> void:
	_rig = OnlineRig.new()
	_rig.view_size = VIEW
	add_child(_rig)
	_rig.start()
	_rig.server.combat.revive_seconds = REVIVE_SECONDS
	_ada = await _rig.join("Ada")
	_bo = await _rig.join("Bo")
	_put(_ada, ADA_AT, PI)
	_put(_bo, BO_AT, PI)
	_turn_camera(_ada, 0.0)
	_turn_camera(_bo, -8.0)
	for index in 2:
		_rig.controllers[index].plan = _plan.bind(index)
	_show(_rig.views[0], 0, "Ada's screen (her own body, predicted)")
	_show(_rig.views[1], 1, "Bo's screen (Ada drawn from the server)")
	await _rig.wait(30)
	# Ada shoots the target.
	_aims[0] = func() -> Vector3: return BOARD
	await _rig.wait(30)
	_presses[0] = [_rig.controllers[0].ticks + 2]
	await _rig.wait(110)
	_aims[0] = Callable()
	await _rig.wait(20)
	# Bo shoots Ada three times.
	var ada_on_bo := _bo.remote_players.puppet_at(_ada.slot)
	_aims[1] = func() -> Vector3: return ada_on_bo.global_position + Vector3.UP * CHEST
	await _rig.wait(30)
	var now: int = _rig.controllers[1].ticks
	_presses[1] = [now + 2, now + 32, now + 62]
	await _rig.wait(90)
	_aims[1] = Callable()
	await _rig.wait(roundi((REVIVE_SECONDS + 1.5) * NetLimits.TICK_RATE))


# A controller's command: aim at its point with the shot block from its eye, pressing on the
# planned ticks; standing still with no aim.
func _plan(tick: int, index: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	var body := _rig.clients[index].player
	command.yaw = body.view_yaw
	if not _aims[index].is_valid():
		return command
	var eye := body.global_position + Vector3.UP * body.tuning.camera_height
	var angles := CommandCodec.direction_angles((_aims[index].call() as Vector3) - eye)
	command.yaw = angles.x
	command.pitch = angles.y
	command.aim = true
	command.has_shot = true
	command.origin = eye
	command.shot_yaw = angles.x
	command.shot_pitch = angles.y
	command.fire_pressed = _presses[index].has(tick)
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
	var health := Label.new()
	health.position = Vector2(column * VIEW.x + 12, VIEW.y - 34)
	health.add_theme_font_size_override(&"font_size", 18)
	health.add_theme_color_override(&"font_outline_color", Color.BLACK)
	health.add_theme_constant_override(&"outline_size", 4)
	health.set_meta(&"column", column)
	add_child(health)
	_health_labels.append(health)


func _process(_delta: float) -> void:
	if _ada == null or _bo == null or not _ada.is_seated() or not _bo.is_seated():
		return
	for label in _health_labels:
		var client := _ada if label.get_meta(&"column") == 0 else _bo
		var ada := client.combat.body_of(_ada.slot)
		var bo := client.combat.body_of(_bo.slot)
		if ada == null or bo == null:
			continue
		label.text = (
			"On this screen: Ada %d  Bo %d   (server: Ada %d)"
			% [roundi(ada.health), roundi(bo.health), roundi(_rig.server_body(_ada).health)]
		)

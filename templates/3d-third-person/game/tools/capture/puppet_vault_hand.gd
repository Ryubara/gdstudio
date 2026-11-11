## Two puppets' planted hands on the course's 0.9 m wall, seen from Bo's screen alone (gdstudio
## #1228): Ada vaults it, then an AI the server runs vaults it on the same lane.
## Both are drawn on Bo's screen from the server (Ada's TICK entry, the AI's rows), plan the
## crossing themselves (`PuppetVault`) and hold the model on the clip's root of that plan
## (`VaultAnimation`), so the left hand rests on the top. Everything runs in this process
## (`tests/fixtures/online_rig.gd`, lockstep over a `LoopbackListener`).
##
## `gds capture frames --project game --scene res://tools/capture/puppet_vault_hand.tscn
## --seconds 5 --fps 60`. It lives in tools/, which the export leaves out.
extends Node

## The course's 0.9 m wall's west face (x) and its middle (z); it is 2.5 m long.
const FACE := -15.7
const WALL_Z := -12.0
## The lane Ada and then the AI run along: the wall's near half, as seen from Bo.
const LANE := WALL_Z + 0.5
## Where Ada is put once over, out of the AI's way and out of the picture.
const ADA_AWAY := Vector3(-19.0, 0.0, -6.0)
## Where they start: 1.3 m before the face, clear of the 0.5 m wall before it.
const START_BEFORE := 1.3
## Metres before the face (past the body's radius) the jump is pressed.
const PRESS_BEFORE := 0.6
const BO_AT := Vector3(-13.4, 0.0, -9.4)
const VIEW := Vector2i(1920, 1080)

var _rig: OnlineRig
var _ada: NetClient
var _bo: NetClient
var _runner: AiCharacter


func _ready() -> void:
	_rig = OnlineRig.new()
	_rig.view_size = VIEW
	add_child(_rig)
	_rig.start()
	_ada = await _rig.join("Ada")
	_bo = await _rig.join("Bo")
	_put(_ada, Vector3(FACE - START_BEFORE, 0.0, LANE), PI / 2.0)
	_put(_bo, BO_AT, PI)
	var rig := _bo.player.get_parent() as PlayerRig
	rig.camera_rig.yaw = 20.0
	rig.camera_rig.pitch = 14.0
	_runner = AiNetStage.walker(Vector3(FACE - START_BEFORE, 0.0, LANE))
	_runner.facing = PI / 2.0
	AiNetStage.server_map(_rig.server).add_child(_runner)
	_show()
	await _rig.wait(40)
	await _ada_vaults()
	_put(_ada, ADA_AWAY, 0.0)
	await _rig.wait(20)
	await _ai_vaults()


func _ada_vaults() -> void:
	var radius := _ada.player.tuning.radius
	var pressed := false
	for _tick in 90:
		var command := PlayerCommand.new()
		command.set_from_world(
			Vector3.ZERO if _ada.player.global_position.x > FACE + 1.5 else Vector3.RIGHT
		)
		if not pressed and _ada.player.global_position.x >= FACE - radius - PRESS_BEFORE:
			command.jump = true
			command.jump_pressed = true
			pressed = true
		_rig.controllers[0].next = command
		await get_tree().physics_frame
	_rig.controllers[0].next = PlayerCommand.new()


func _ai_vaults() -> void:
	var controller := _runner.controller as AiController
	var radius := _runner.tuning.radius
	AiNetStage.walk(_runner, Vector3.RIGHT)
	for _tick in 120:
		await get_tree().physics_frame
		if _runner.global_position.x >= FACE - radius - PRESS_BEFORE:
			break
	controller.jump = true
	await _rig.wait(4)
	controller.jump = false
	for _tick in 120:
		await get_tree().physics_frame
		if _runner.global_position.x > FACE + 1.5:
			break
	AiNetStage.walk(_runner, Vector3.ZERO)


func _put(client: NetClient, spot: Vector3, heading: float) -> void:
	_rig.server_body(client).teleport(spot, heading)
	client.player.teleport(spot, heading)


func _show() -> void:
	var picture := TextureRect.new()
	picture.texture = _rig.views[1].get_texture()
	picture.size = Vector2(VIEW)
	add_child(picture)
	var label := Label.new()
	label.text = "Bo's screen: Ada, then an AI, drawn from the server"
	label.position = Vector2(12, 8)
	label.add_theme_font_size_override(&"font_size", 32)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 4)
	add_child(label)

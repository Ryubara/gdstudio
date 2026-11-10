## Films the camera shake by pressing the input actions a player would: a sprint with the sprint
## shake turned up, four shots from the aim with the shot kick turned up, and two blasts through
## the one-line call, one close and one far past its radius. It prints a `SHAKE` line each physics
## frame (the time and the turn of the view in degrees: pitch, yaw, roll) for the numbers.
##
## `gds capture frames --project game --scene res://tools/capture/shake_tour.tscn --seconds 10`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const BLAST := preload("res://core/camera_shake/presets/explosion.tres")
## The sprint shake and the shot kick are turned well up from their defaults (0) to be seen.
const SPRINT_AMPLITUDE := 1.0
const KICK_AMPLITUDE := 1.2

var _clock := 0.0
var _fired := 0
var _blasted := 0

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	_rig.sprint_shake_amplitude = SPRINT_AMPLITUDE
	_rig.shot_kick_amplitude = KICK_AMPLITUDE
	_rig.shot_kick_duration = 0.25
	_player.teleport(Vector3(4.0, 0.0, 23.0))


func _physics_process(delta: float) -> void:
	_clock += delta
	var sprinting := _clock > 0.8 and _clock < 3.4
	_press(&"move_forward", sprinting)
	_press(&"sprint", sprinting)
	var aiming := _clock > 4.0 and _clock < 7.0
	_press(&"aim", aiming)
	# Four shots, a quarter of a second apart, once the arm is up.
	if aiming and _clock > 5.0 and _fired < 4 and _clock > 5.0 + 0.5 * _fired:
		Input.action_press(&"fire")
		_fired += 1
	elif _fired > 0 and _clock > 5.0 + 0.5 * (_fired - 1) + 0.1:
		Input.action_release(&"fire")
	if _clock > 7.6 and _blasted == 0:
		_blasted = 1
		CameraShake.shake(BLAST, _player.global_position + Vector3(6.0, 0.0, 0.0))
	if _clock > 9.0 and _blasted == 1:
		_blasted = 2
		CameraShake.shake(BLAST, _player.global_position + Vector3(BLAST.radius * 2.0, 0.0, 0.0))
	var turn := _rig.current_shake()
	print("SHAKE %.2f %.3f %.3f %.3f" % [_clock, turn.x, turn.y, turn.z])
	if _clock > 10.5:
		set_physics_process(false)
		_finish()


func _press(action: StringName, down: bool) -> void:
	if down and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not down and Input.is_action_pressed(action):
		Input.action_release(action)


func _finish() -> void:
	Input.action_release(&"fire")
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()

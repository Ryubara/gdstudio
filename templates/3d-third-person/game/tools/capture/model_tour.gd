## Films the player's model from the front, walking toward the camera, then from behind with the
## pistol up, for the pull request's screenshots of each mannequin. It presses the input actions
## the way a player would and turns the camera with `orbit()`. It films whichever model
## `player.tscn` holds: to film the other mannequin, make a game from the template and point the
## scene's model at `mannequin_male.glb` the way the editor does it (the template's
## `tools/editor_swap/` does that).
##
## Record it with Movie Maker through the kit:
## `gds capture frames --project game --scene res://tools/capture/model_tour.tscn --seconds 6`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## Seconds of standing, walking toward the camera and aiming.
const STAND := 1.0
const WALK := 1.8
const AIM := 1.4
## Camera pitch, in degrees, while filming.
const PITCH := 6.0

var _clock := 0.0

@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _physics_process(delta: float) -> void:
	_clock += delta
	if _clock < STAND:
		_hold([])
		_face(180.0)
	elif _clock < STAND + WALK:
		_hold([&"move_back"])
		_face(180.0)
	elif _clock < STAND + WALK + AIM:
		_hold([&"aim"])
		_face(0.0)
	else:
		_hold([])
		_finish()


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits
# (a voice still playing at exit is reported as a leak).
func _finish() -> void:
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()


# Turns the camera to a heading (degrees, 0 looks along -Z), a few degrees a frame.
func _face(yaw: float) -> void:
	var by_yaw := clampf(wrapf(yaw - _rig.yaw, -180.0, 180.0), -6.0, 6.0)
	var by_pitch := clampf(PITCH - _rig.pitch, -2.0, 2.0)
	_rig.orbit(Vector2(-by_yaw, by_pitch))


func _hold(actions: Array[StringName]) -> void:
	for action: StringName in [&"move_back", &"aim"]:
		if actions.has(action):
			Input.action_press(action)
		else:
			Input.action_release(action)

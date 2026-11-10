## Fires the pistol the way a player would, in slow motion, for a clip of the muzzle flash. The
## character stands in front of the orange block of the ragdoll ledge and aims at it with the aim
## button, then fires single shots (the fire button, held for a moment each) with a pause between
## them: the first `SHOTS_ON` with the flash on, the last `SHOTS_OFF` with the weapon's
## `muzzle_flash_enabled` off, to show the difference.
##
## It runs the game at `SLOW` times real speed (`Engine.time_scale`), so a flash that lasts a tenth
## of a second takes many frames. Record it with Movie Maker through the kit (the frames land in
## the scratch folder; add `--rendering-method gl_compatibility` after `--` for the web look):
## `gds capture frames --project game --scene res://tools/capture/muzzle_flash_tour.tscn
## --seconds 24 --fps 30`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

enum Phase { AIM, FIRE, PAUSE }

## The speed of the game: a hundredth of a second of play is this much of a second of film.
const SLOW := 0.15
## The crosshair is on the point within this many pixels.
const AIM_PIXELS := 5.0
## The share of the crosshair's distance from the point that one frame turns.
const AIM_GAIN := 0.35
## How long the fire button is held for a shot, and the pause after it (seconds of play).
const SHOT_HOLD := 0.1
const SHOT_PAUSE := 0.3
## Where the character stands and what it shoots at.
const STAND := Vector3(-6.0, 0.0, 14.5)
const TARGET := Vector3(-6.0, 0.9, 18.5)
## How many shots are fired with the flash on and then off.
const SHOTS_ON := 3
const SHOTS_OFF := 1

var _phase := Phase.AIM
var _clock := 0.0
var _shots := 0
var _warmup := 0.4
var _pitch_sign := 1.0
var _last_error := INF
var _held: Array[StringName] = []

@onready var _player: Player = $Main/Player
@onready var _rig: PlayerCamera = $Main/PlayerCamera
@onready var _camera: Camera3D = $Main/Camera


func _ready() -> void:
	Engine.time_scale = SLOW
	_player.teleport(STAND, 0.0)


func _physics_process(delta: float) -> void:
	if _warmup > 0.0:
		_warmup -= delta
		return
	if _shots >= SHOTS_ON + SHOTS_OFF:
		_hold([])
		_finish()
		return
	_player.weapon.muzzle_flash_enabled = _shots < SHOTS_ON
	match _phase:
		Phase.AIM:
			_hold([&"aim"])
			if _aim(TARGET):
				_phase = Phase.FIRE
				_clock = 0.0
		Phase.FIRE:
			_hold([&"aim", &"fire"])
			_clock += delta
			if _clock >= SHOT_HOLD:
				_phase = Phase.PAUSE
				_clock = 0.0
		Phase.PAUSE:
			_hold([&"aim"])
			_clock += delta
			if _clock >= SHOT_PAUSE:
				_phase = Phase.AIM
				_shots += 1


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits.
func _finish() -> void:
	set_physics_process(false)
	Engine.time_scale = 1.0
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()


# Turns the camera until the crosshair is over `at`; true when it is (within a few pixels).
func _aim(at: Vector3) -> bool:
	var centre := get_viewport().get_visible_rect().size / 2.0
	var error := _camera.unproject_position(at) - centre
	var focal := centre.y / tan(deg_to_rad(_camera.fov) / 2.0)
	if error.length() > _last_error + 0.5:
		_pitch_sign = -_pitch_sign
	_last_error = error.length()
	var turn := Vector2(rad_to_deg(atan(error.x / focal)), rad_to_deg(atan(error.y / focal)))
	_rig.orbit(Vector2(turn.x, turn.y * _pitch_sign) * AIM_GAIN)
	return error.length() < AIM_PIXELS


# Holds exactly these actions down and lets go of the rest.
func _hold(actions: Array) -> void:
	for action in _held:
		if not actions.has(action):
			Input.action_release(action)
	_held.clear()
	for action: StringName in actions:
		Input.action_press(action)
		_held.append(action)

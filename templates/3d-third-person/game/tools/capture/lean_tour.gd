## Films the gait lean (gdstudio #1158, its cost #1403): the player, stepped by commands as a
## server steps it, sprints from standing (the body leans forward), stops (back) and sprints in a
## turn (to the side). `LEAN_DISTANCE` is how far the camera stands, in metres (default 6; 25 is
## the animation throttle's `far_distance`), its lens narrowed so the body fills the frame at any
## distance, as a scope would: from the side for the sprint and the stop, from behind for the
## turn. `LEAN_HEIGHT` raises it (metres over the chest; default 0), as a scope on a roof sees
## over the sample map's walls. A label shows the distance and the lean, and every physics frame
## prints the lean on a line starting `LEANTOUR`.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --seconds 5.4 --fps 10 --name lean` with `--scene
## res://tools/capture/lean_tour.tscn` (`LEAN_DISTANCE=25 LEAN_HEIGHT=9` in its environment).
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## An open spot of the sample map.
const SPOT := Vector3(4.0, 0.0, 18.0)
## The height of the view the lens frames at any distance (m).
const VIEW_HEIGHT := 2.4
## The parts: a title, seconds, whether the body sprints ahead, how fast the way it is asked to
## go turns (degrees a second) and whether the camera looks from behind (else from the side).
const PARTS: Array[Array] = [
	["Standing", 0.6, false, 0.0, false],
	["Sprint from standing", 1.0, true, 0.0, false],
	["Stop", 1.2, false, 0.0, false],
	["Sprint, turning", 2.4, true, 80.0, true],
]

var _part := -1
var _clock := 0.0
var _label: Label
var _distance := 6.0
var _height := 0.0
var _yaw := 0.0
var _command := PlayerCommand.new()

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera
@onready var _animation: CharacterAnimation = $Main/PlayerRig/Player/Animation


func _ready() -> void:
	var asked := OS.get_environment("LEAN_DISTANCE")
	if asked.is_valid_float():
		_distance = maxf(asked.to_float(), 1.0)
	var high := OS.get_environment("LEAN_HEIGHT")
	if high.is_valid_float():
		_height = high.to_float()
	_player.teleport(SPOT, 0.0)
	# Stepped here by commands: no controller, no input.
	if _player.controller != null:
		_player.controller.queue_free()
		_player.controller = null
	_player.set_physics_process(false)
	# The game's camera, placed here: its Phantom Camera host (its child) stops moving it.
	for host in _rig.camera.get_children():
		host.process_mode = Node.PROCESS_MODE_DISABLED
	_rig.camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_priority = 1 << 20
	process_physics_priority = 1 << 20
	_build_label()
	_next()


func _physics_process(delta: float) -> void:
	_clock += delta
	if _part >= PARTS.size():
		return
	var part: Array = PARTS[_part]
	_yaw += deg_to_rad(part[3]) * delta
	_command.clear()
	_command.yaw = _yaw
	if part[2]:
		_command.move = Vector2(0.0, 1.0)
		_command.sprint = true
	_player.step(_command, delta)
	var lean := _animation.gait.lean.amount
	_label.text = (
		"%s, seen from %.0f m\nlean: %+.2f to the right, %+.2f forward"
		% [part[0], _distance, lean.x, lean.y]
	)
	print("LEANTOUR ", _part, " ", snappedf(_clock, 0.01), " ", lean)
	if _clock >= part[1]:
		_next()
	_place_camera()


func _process(_delta: float) -> void:
	_place_camera()


# Level with the chest, from the body's right side (a forward lean is a profile) or from behind
# (a lean to the side).
func _place_camera() -> void:
	if _part >= PARTS.size():
		return
	var camera := _rig.camera
	var body := _player.global_position
	var forward := Vector3.BACK.rotated(Vector3.UP, _player.facing)
	var away := -forward if PARTS[_part][4] else forward.cross(Vector3.UP)
	camera.fov = rad_to_deg(2.0 * atan(VIEW_HEIGHT * 0.5 / _distance))
	camera.far = maxf(_distance * 4.0, 100.0)
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	camera.global_position = body + away * _distance + Vector3(0.0, 1.0 + _height, 0.0)
	camera.look_at(body + Vector3(0.0, 0.95, 0.0))


func _next() -> void:
	_part += 1
	_clock = 0.0
	if _part >= PARTS.size():
		_finish()


func _build_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	_label = Label.new()
	_label.position = Vector2(24.0, 80.0)
	_label.add_theme_font_size_override(&"font_size", 28)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(_label)
	add_child(layer)


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits.
func _finish() -> void:
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame_count in 8:
		await get_tree().process_frame
	get_tree().quit()

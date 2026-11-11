## Swaps the camera between shoulders twice: once while sprinting without aiming, along an orange
## line drawn on the ground where the run started, and once while aiming at a board with a blue
## marker on the point under the crosshair. By default (`keep_aim_when_not_aiming` off) the
## sprinting swap only slides the view, so the character keeps running along the line, and the
## aimed swap keeps the marker under the crosshair. A label names each part and shows the view's
## yaw and the run's heading. It moves with the same actions a player presses and swaps with
## `swap_shoulder()`, the call the `shoulder_swap` action makes. Every physics frame it prints the
## yaw and the heading (the line starts with `SPRINTSWAP`).
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --seconds 8 --fps 30 --name sprint-swap`
## with `--scene res://tools/capture/sprint_swap_tour.tscn`.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## An open spot of the sample map, looking north (-Z) with room to sprint ahead.
const SPOT := Vector3(4.0, 0.0, 18.0)
## How far ahead of the character the board of the aimed part stands.
const BOARD_DISTANCE := 5.0
## Seconds of the sprint before the swap, and after it.
const RUN_UP := 0.8
const RUN_ON := 1.0
## Seconds of the aimed part before the swap, and after it.
const AIM_UP := 1.0
const AIM_ON := 1.4

var _part := 0
var _clock := 0.0
var _swapped := false
var _marker: MeshInstance3D
var _board: StaticBody3D
var _label: Label
var _title := ""

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera
@onready var _camera: Camera3D = $Main/PlayerRig/Camera


func _ready() -> void:
	_player.teleport(SPOT, 0.0)
	_rig.yaw = 0.0
	_rig.pitch = 8.0
	_build_line()
	_build_board()
	_build_label()
	_title = "Sprinting, not aiming: shoulder swap"
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")


func _physics_process(delta: float) -> void:
	_clock += delta
	var run := Vector2(_player.velocity.x, _player.velocity.z)
	var heading := rad_to_deg(atan2(-run.x, -run.y)) if run.length() > 0.5 else 0.0
	print(
		"SPRINTSWAP part ",
		_part,
		" t ",
		snappedf(_clock, 0.01),
		" yaw ",
		snappedf(_rig.yaw, 0.01),
		" heading ",
		snappedf(heading, 0.01),
		" x ",
		snappedf(_player.global_position.x, 0.01)
	)
	_label.text = "%s\nview yaw %.2f deg   run heading %.2f deg" % [_title, _rig.yaw, heading]
	if _part == 0:
		if not _swapped and _clock >= RUN_UP:
			_swapped = true
			_rig.swap_shoulder()
		elif _clock >= RUN_UP + RUN_ON:
			_start_aimed_part()
	elif _part == 1:
		if not _swapped and _clock >= AIM_UP:
			_swapped = true
			_rig.swap_shoulder()
		elif _clock >= AIM_UP + AIM_ON:
			_finish()


func _start_aimed_part() -> void:
	_part = 1
	_clock = 0.0
	_swapped = false
	_title = "Aiming: shoulder swap (blue marker: the point aimed at)"
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	Input.action_press(&"aim")
	_player.teleport(SPOT, 0.0)
	_rig.shoulder = PlayerCamera.Shoulder.RIGHT
	_rig.yaw = 0.0
	_rig.pitch = 4.0
	_board.global_position = SPOT + Vector3(0.0, 1.6, -BOARD_DISTANCE)
	_board.visible = true
	await get_tree().create_timer(AIM_UP * 0.7, true, true).timeout
	_marker.global_position = _rig.crosshair_point()
	_marker.visible = true


# A thin orange stripe on the ground straight north from the spot: the line of the run.
func _build_line() -> void:
	var stripe := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(0.12, 0.02, 30.0)
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(1.0, 0.45, 0.05)
	orange.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar.material = orange
	stripe.mesh = bar
	add_child(stripe)
	stripe.global_position = SPOT + Vector3(0.0, 0.02, -15.0)


func _build_board() -> void:
	_board = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 4.0, 0.2)
	shape.shape = box
	_board.add_child(shape)
	var mesh := MeshInstance3D.new()
	var face := BoxMesh.new()
	face.size = box.size
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.85, 0.85, 0.8)
	face.material = paint
	mesh.mesh = face
	_board.add_child(mesh)
	add_child(_board)
	# Out of the way (and of the run) until the aimed part.
	_board.global_position = SPOT + Vector3(0.0, -50.0, 0.0)
	_board.visible = false
	_marker = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.1
	dot.height = 0.2
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(0.1, 0.35, 1.0)
	blue.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot.material = blue
	_marker.mesh = dot
	_marker.visible = false
	add_child(_marker)


func _build_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	_label = Label.new()
	_label.position = Vector2(24.0, 24.0)
	_label.add_theme_font_size_override(&"font_size", 26)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(_label)
	add_child(layer)


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits
# (a voice still playing at exit is reported as a leak).
func _finish() -> void:
	set_physics_process(false)
	Input.action_release(&"aim")
	AudioSettings.stop_players(get_tree().root)
	for _frame_count in 8:
		await get_tree().process_frame
	get_tree().quit()

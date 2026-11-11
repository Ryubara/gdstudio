## Swaps the camera between shoulders in front of a board with a blue marker on the point under the
## crosshair, three times: with `keep_aim_on_swap` off (the view slides and the crosshair leaves the
## marker), on (the marker stays under the crosshair) and on with a look to the right in the middle
## of the swap (the marker moves by the look alone). A label names each part. It swaps with
## `swap_shoulder()`, the call the `shoulder_swap` action makes, and looks with `orbit()`, the call
## the mouse and the stick make. Every physics frame it prints how far the marker sits off the
## crosshair (the line starts with `SWAP`).
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --seconds 9 --fps 30 --name swap`
## with `--scene res://tools/capture/shoulder_swap_tour.tscn`.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## An open spot of the sample map, looking north (-Z) with nothing between it and the board.
const SPOT := Vector3(4.0, 0.0, 18.0)
## How far ahead of the character the board stands.
const BOARD_DISTANCE := 4.5

## Each part: its label, whether the anchor is on and the look (degrees right) made mid-swap.
const PARTS: Array[Dictionary] = [
	{"label": "Anchor off: the view slides, the aim drifts", "keep": false, "look": 0.0},
	{"label": "Anchor on: the point stays under the crosshair", "keep": true, "look": 0.0},
	{"label": "Anchor on, look right mid-swap: the look adds", "keep": true, "look": 4.0},
]
## Seconds of each part: settle, swap, hold on the new shoulder.
const SETTLE := 0.9
const HOLD := 1.6

var _part := -1
var _clock := 0.0
var _swapped := false
var _looked := false
var _marker: MeshInstance3D
var _label: Label
var _start_yaw := 0.0

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera
@onready var _camera: Camera3D = $Main/PlayerRig/Camera


func _ready() -> void:
	# Aiming shows the crosshair; a swap then takes `aim_shoulder_time`.
	Input.action_press(&"aim")
	_player.teleport(SPOT, 0.0)
	_rig.yaw = 0.0
	_rig.pitch = 4.0
	_start_yaw = _rig.yaw
	_build_board()
	_build_label()


func _physics_process(delta: float) -> void:
	if _part >= 0 and _marker.visible:
		var centre := _camera.get_viewport().get_visible_rect().size / 2.0
		var from := _camera.project_ray_origin(centre)
		var off := rad_to_deg(
			_camera.project_ray_normal(centre).angle_to(_marker.global_position - from)
		)
		print("SWAP part ", _part, " t ", snappedf(_clock, 0.01), " off ", snappedf(off, 0.01))
	_clock += delta
	if _part < 0:
		if _clock >= SETTLE:
			_next_part()
		return
	var part := PARTS[_part]
	if not _swapped and _clock >= SETTLE:
		_swapped = true
		_rig.swap_shoulder()
	if _swapped and not _looked and _clock >= SETTLE + _rig.aim_shoulder_time * 0.4:
		_looked = true
		if float(part["look"]) != 0.0:
			_rig.orbit(Vector2(float(part["look"]), 0.0))
	if _clock >= SETTLE + HOLD:
		if _part + 1 >= PARTS.size():
			_finish()
			return
		_next_part()


func _next_part() -> void:
	_part += 1
	_clock = 0.0
	_swapped = false
	_looked = false
	var part := PARTS[_part]
	_label.text = part["label"]
	_rig.keep_aim_on_swap = false
	# Back to the right shoulder and the first heading, then the marker goes on what the
	# crosshair holds once the view is there.
	_rig.shoulder = PlayerCamera.Shoulder.RIGHT
	_rig.yaw = _start_yaw
	_rig.pitch = 4.0
	_marker.visible = false
	await get_tree().create_timer(SETTLE * 0.6, true, true).timeout
	_rig.keep_aim_on_swap = part["keep"]
	_marker.global_position = _rig.crosshair_point()
	_marker.visible = true


func _build_board() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 4.0, 0.2)
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var face := BoxMesh.new()
	face.size = box.size
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.85, 0.85, 0.8)
	face.material = paint
	mesh.mesh = face
	body.add_child(mesh)
	add_child(body)
	body.global_position = SPOT + Vector3(0.0, 1.6, -BOARD_DISTANCE)
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

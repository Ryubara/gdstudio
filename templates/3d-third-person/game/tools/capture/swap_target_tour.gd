## Swaps the camera between shoulders while aiming, twice, with a blue marker on the point under the
## crosshair when the swap starts: at a wall (the view moves to the other shoulder without turning,
## so the marker slides off the crosshair) and at a character (the view turns so the marker stays
## under the crosshair). A label names each part. The swap is the swap key itself (Q, sent through
## the engine's input path) and the aim is the `aim` action held. Every physics frame it prints how
## far the marker sits off the crosshair and how far the view has turned (the line starts with
## `SWAP`).
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --seconds 8 --fps 30 --name swap-target`
## with `--scene res://tools/capture/swap_target_tour.tscn`.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## An open spot of the sample map, looking north (-Z).
const SPOT := Vector3(4.0, 0.0, 18.0)
const WALL_DISTANCE := 4.5
const CHARACTER_DISTANCE := 6.0
const DRESSED := "res://gameplay/character/character_dressed.tscn"
const PARTS: Array[String] = [
	"Aimed at a wall: the view moves over without turning",
	"Aimed at a character: the view turns, the point stays",
]
## Seconds of each part: settle, then swap and hold on the new shoulder.
const SETTLE := 1.2
const HOLD := 2.2

var _part := -1
var _clock := 0.0
var _swapped := false
var _yaw_at_swap := 0.0
var _wall: StaticBody3D
var _target: Character
var _marker: MeshInstance3D
var _label: Label

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera
@onready var _camera: Camera3D = $Main/PlayerRig/Camera


func _ready() -> void:
	Input.action_press(&"aim")
	_player.teleport(SPOT, 0.0)
	_rig.yaw = 0.0
	_rig.pitch = 4.0
	_build_wall()
	_build_marker()
	_build_label()


func _physics_process(delta: float) -> void:
	if _part >= 0 and _marker.visible:
		var centre := _camera.get_viewport().get_visible_rect().size / 2.0
		var from := _camera.project_ray_origin(centre)
		var off := rad_to_deg(
			_camera.project_ray_normal(centre).angle_to(_marker.global_position - from)
		)
		var turn := rad_to_deg(angle_difference(deg_to_rad(_yaw_at_swap), deg_to_rad(_rig.yaw)))
		print(
			"SWAP part ",
			_part,
			" t ",
			snappedf(_clock, 0.01),
			" off ",
			snappedf(off, 0.01),
			" turn ",
			snappedf(turn, 0.01)
		)
	_clock += delta
	if _part < 0:
		if _clock >= SETTLE * 0.5:
			_next_part()
		return
	if not _swapped and _clock >= SETTLE:
		_swapped = true
		_yaw_at_swap = _rig.yaw
		_press_swap()
	if _clock >= SETTLE + HOLD:
		if _part + 1 >= PARTS.size():
			_finish()
			return
		_next_part()


func _next_part() -> void:
	_part += 1
	_clock = 0.0
	_swapped = false
	_label.text = PARTS[_part]
	# Back to the right shoulder and the first heading.
	_rig.shoulder = PlayerCamera.Shoulder.RIGHT
	_rig.yaw = 0.0
	_rig.pitch = 4.0
	_yaw_at_swap = 0.0
	_marker.visible = false
	if _part == 1:
		_wall.queue_free()
	await get_tree().create_timer(SETTLE * 0.4, true, true).timeout
	if _part == 1:
		# Placed once the view is back on the right shoulder, so it stands on the crosshair.
		_place_target()
	await get_tree().create_timer(SETTLE * 0.3, true, true).timeout
	_marker.global_position = _rig.crosshair_point()
	_marker.visible = true


# The swap key as a player presses it: a press and a release through the engine's input path.
func _press_swap() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_Q
		event.physical_keycode = KEY_Q
		event.pressed = pressed
		Input.parse_input_event(event)


# A character standing where the crosshair's ray is `CHARACTER_DISTANCE` out, facing the player.
func _place_target() -> void:
	var centre := _camera.get_viewport().get_visible_rect().size / 2.0
	var ahead := (
		_camera.project_ray_origin(centre)
		+ _camera.project_ray_normal(centre) * (CHARACTER_DISTANCE + _rig.current_distance())
	)
	_target = (load(DRESSED) as PackedScene).instantiate() as Character
	_target.position = Vector3(ahead.x, SPOT.y, ahead.z)
	add_child(_target)
	_target.facing = 0.0


func _build_wall() -> void:
	_wall = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 4.0, 0.2)
	shape.shape = box
	_wall.add_child(shape)
	var mesh := MeshInstance3D.new()
	var face := BoxMesh.new()
	face.size = box.size
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.85, 0.85, 0.8)
	face.material = paint
	mesh.mesh = face
	_wall.add_child(mesh)
	add_child(_wall)
	_wall.global_position = SPOT + Vector3(0.0, 1.6, -WALL_DISTANCE)


func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.06
	dot.height = 0.12
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(0.1, 0.35, 1.0)
	blue.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blue.no_depth_test = true
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

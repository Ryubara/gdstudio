class_name ModelPreview
extends Control
## The character as it stands in the game, drawn in a menu: a `SubViewport` of the game's own world
## whose `Camera` sees only the render layer `preview_layer`, which this node adds to every mesh
## under the character's `Model` slot while it shows. So the picture is the live model with the
## weapon in its hand, it follows a model swap (a mesh added under the slot is flagged at once), and
## nothing else of the map is drawn: the card behind shows through the clear background.
##
## Drag across it (mouse or finger) or push the right stick (`look_left`, `look_right`) to turn the
## view around the character. The viewport renders only while the preview is visible, at the
## window's pixels for the control's size (capped at `max_height`).

## The view turned; `angle` is in degrees from the character's front.
signal turned(angle: float)

@export_group("Nodes")
## The character's `Model` slot: its meshes are drawn. Set by the screen from its player.
@export var model_slot: Node3D:
	set(value):
		if model_slot == value:
			return
		_unflag_all()
		_watch(false)
		model_slot = value
		if is_inside_tree() and is_visible_in_tree():
			_watch(true)
			_flag_all()

@export_group("View")
## The render layer the preview draws (1 to 20). Pick one nothing else in the game uses alone: the
## layer is added to the model's meshes, never taken from them, so the game's cameras still see
## them.
@export_range(1, 20, 1) var preview_layer := 20
## How far the camera stands from the character.
@export_range(0.5, 10.0, 0.05, "suffix:m") var distance := 3.2
## How high above the character's feet the camera stands.
@export_range(0.0, 3.0, 0.01, "suffix:m") var camera_height := 1.15
## The height above the feet the camera looks at.
@export_range(0.0, 3.0, 0.01, "suffix:m") var look_height := 0.95
## The camera's vertical field of view.
@export_range(10.0, 90.0, 0.5, "suffix:deg") var field_of_view := 34.0
## Where the view starts, in degrees from the character's front (0 looks at its face).
@export_range(-180.0, 180.0, 1.0, "suffix:deg") var start_angle := -25.0

@export_group("Turning")
## Degrees the view turns for each pixel dragged.
@export_range(0.0, 2.0, 0.01, "suffix:deg/px") var drag_turn := 0.45
## Degrees a second the view turns with the stick held over.
@export_range(0.0, 720.0, 1.0, "suffix:deg/s") var stick_turn := 160.0

@export_group("Quality")
## The tallest the viewport is drawn, in pixels (a 4K window draws it at this height).
@export_range(120, 2160, 1, "suffix:px") var max_height := 1440
## The viewport's own multisampling (the project setting does not reach a `SubViewport`).
@export var msaa := Viewport.MSAA_4X:
	set(value):
		msaa = value
		if _viewport != null:
			_viewport.msaa_3d = msaa

## Degrees from the character's front the view is turned to.
var angle := 0.0
var _flagged: Array[VisualInstance3D] = []
var _dragging := false

@onready var _viewport: SubViewport = %Viewport
@onready var _camera: Camera3D = %Camera
@onready var _picture: TextureRect = %Picture


func _ready() -> void:
	angle = start_angle
	_viewport.msaa_3d = msaa
	_picture.texture = _viewport.get_texture()
	resized.connect(_fit_viewport)
	visibility_changed.connect(_on_visibility_changed)
	get_tree().root.size_changed.connect(_fit_viewport)
	_fit_viewport()
	_on_visibility_changed()


func _exit_tree() -> void:
	_unflag_all()
	_watch(false)


func _process(delta: float) -> void:
	var push := 0.0
	if InputMap.has_action(&"look_left") and InputMap.has_action(&"look_right"):
		push = Input.get_axis(&"look_left", &"look_right")
	if push != 0.0:
		turn(push * stick_turn * delta)
	_place_camera()


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		turn(motion.relative.x * drag_turn)
		accept_event()
		return
	var drag := event as InputEventScreenDrag
	if drag != null:
		turn(drag.relative.x * drag_turn)
		accept_event()


## Turns the view by `degrees` around the character.
func turn(degrees: float) -> void:
	if is_zero_approx(degrees):
		return
	angle = wrapf(angle + degrees, -180.0, 180.0)
	_place_camera()
	turned.emit(angle)


## The meshes the preview draws now (those under the model slot).
func flagged() -> Array[VisualInstance3D]:
	return _flagged.duplicate()


## The camera inside the viewport.
func camera() -> Camera3D:
	return _camera


## The viewport the picture shows.
func viewport() -> SubViewport:
	return _viewport


# Stands the camera `distance` from the slot's owner, at `angle` from the way the model faces.
func _place_camera() -> void:
	if _camera == null or model_slot == null or not model_slot.is_inside_tree():
		return
	_camera.fov = field_of_view
	_camera.cull_mask = 1 << (preview_layer - 1)
	var feet := model_slot.global_position
	# The model faces +Z turned by its yaw (a `Character`'s `facing`).
	var front := model_slot.global_basis.z
	front.y = 0.0
	front = front.normalized() if front.length_squared() > 0.0001 else Vector3.BACK
	var around := front.rotated(Vector3.UP, deg_to_rad(angle))
	var eye := feet + around * distance + Vector3.UP * camera_height
	var focus := feet + Vector3.UP * look_height
	_camera.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(focus, Vector3.UP)


# The viewport at the window's pixels for this control's size, so the picture is sharp.
func _fit_viewport() -> void:
	if _viewport == null or not is_inside_tree():
		return
	var pixels := size * get_viewport().get_final_transform().get_scale()
	if pixels.y > max_height:
		pixels *= max_height / pixels.y
	_viewport.size = Vector2i(maxi(int(pixels.x), 2), maxi(int(pixels.y), 2))


func _on_visibility_changed() -> void:
	var shown := is_visible_in_tree()
	_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED
	)
	set_process(shown)
	_watch(shown)
	if shown:
		_flag_all()
		_place_camera()
	else:
		_unflag_all()


func _watch(on: bool) -> void:
	if model_slot == null or not is_instance_valid(model_slot):
		return
	var linked := model_slot.child_entered_tree.is_connected(_on_slot_child_added)
	if on and not linked:
		model_slot.child_entered_tree.connect(_on_slot_child_added)
	elif not on and linked:
		model_slot.child_entered_tree.disconnect(_on_slot_child_added)


# A model dropped into the slot while the preview shows: flag it once its own children are in.
func _on_slot_child_added(_node: Node) -> void:
	_flag_all.call_deferred()


func _flag_all() -> void:
	if model_slot == null or not is_instance_valid(model_slot):
		return
	var bit := 1 << (preview_layer - 1)
	for node in model_slot.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		if visual not in _flagged:
			_flagged.append(visual)
		visual.layers |= bit


func _unflag_all() -> void:
	var bit := 1 << (preview_layer - 1)
	for visual in _flagged:
		if is_instance_valid(visual):
			visual.layers &= ~bit
	_flagged.clear()

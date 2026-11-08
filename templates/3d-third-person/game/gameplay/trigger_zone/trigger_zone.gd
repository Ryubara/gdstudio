@tool
class_name TriggerZone
extends Area3D
## An invisible box that notices bodies. It says when the first one comes in and when the last
## one leaves, so a pressure plate, a checkpoint or a "door ahead" area is one node and a signal
## connection. It works on its own: connect `activated` and `deactivated` to anything.

## The first body came in (or, with `fire_once`, the only time).
signal activated(body: Node3D)
## The last body left.
signal deactivated

@export_group("Zone")
## The box's width (x), height (y) and depth (z).
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var size := Vector3(3.0, 1.0, 3.0):
	set(value):
		size = value.max(Vector3.ONE * 0.1)
		_update_shape()
## Only bodies in this group count. Empty counts every body on the layers below.
@export var required_group: StringName = &""
## The area only works once: after `activated` it ignores everything.
@export var fire_once := false
## Shows a flat plate in the game, so a pressure pad can be seen. Off keeps the zone invisible.
@export var show_plate := false:
	set(value):
		show_plate = value
		_update_plate()
## The plate's colour while nothing stands on it.
@export var plate_idle_color := Color(0.75, 0.2, 0.15)
## The plate's colour while something stands on it.
@export var plate_active_color := Color(0.3, 0.75, 0.3)

var _inside: Array[Node3D] = []
var _spent := false
var _shape: CollisionShape3D
var _plate: MeshInstance3D


func _init() -> void:
	_shape = CollisionShape3D.new()
	_shape.name = "Shape"
	_shape.shape = BoxShape3D.new()
	add_child(_shape)


func _ready() -> void:
	_update_shape()
	_update_plate()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)


## True while at least one counted body is inside.
func is_active() -> bool:
	return not _inside.is_empty()


## How many counted bodies are inside.
func occupant_count() -> int:
	return _inside.size()


func _counts(body: Node3D) -> bool:
	return required_group == &"" or body.is_in_group(required_group)


func _on_body_entered(body: Node3D) -> void:
	if _spent or not _counts(body) or _inside.has(body):
		return
	_inside.append(body)
	if _inside.size() == 1:
		_set_plate(true)
		activated.emit(body)
		if fire_once:
			_spent = true


func _on_body_exited(body: Node3D) -> void:
	if not _inside.has(body):
		return
	_inside.erase(body)
	if _inside.is_empty():
		_set_plate(false)
		deactivated.emit()


func _update_shape() -> void:
	if _shape == null:
		return
	(_shape.shape as BoxShape3D).size = size
	_update_plate()


func _update_plate() -> void:
	if _shape == null:
		return
	if not show_plate:
		if _plate != null:
			_plate.queue_free()
			_plate = null
		return
	if _plate == null:
		_plate = MeshInstance3D.new()
		_plate.name = "Plate"
		_plate.material_override = StandardMaterial3D.new()
		add_child(_plate)
	var slab := BoxMesh.new()
	slab.size = Vector3(size.x, 0.1, size.z)
	_plate.mesh = slab
	_plate.position = Vector3(0.0, -size.y / 2.0 + 0.05, 0.0)
	_set_plate(is_active())


func _set_plate(active: bool) -> void:
	if _plate != null:
		(_plate.material_override as StandardMaterial3D).albedo_color = (
			plate_active_color if active else plate_idle_color
		)

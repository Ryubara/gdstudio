@tool
class_name MovingPlatform
extends AnimatableBody3D
## A platform that carries whatever stands on it between two points. Set the travel in the
## inspector, or call `start()`, `stop()` and `send_to_end()` from a trigger. It moves in the
## physics step at a fixed speed, so a rider and a test see the same ride every time.
##
## Its parts are nodes of `moving_platform.tscn`: `Mesh` and `Shape` are the slab, and `EndPreview`
## is a ghost of the platform at the far end (shown in the editor only), so changing `size` or
## `travel` in the inspector moves what you see at once.

## The platform reached its far end.
signal reached_end
## The platform came back to its start.
signal reached_start

enum Mode {
	PING_PONG,  ## Goes to the end, waits, comes back, waits, again.
	ONCE,  ## Goes to the end and stays.
	ON_CALL,  ## Moves only when `send_to_end()` or `send_to_start()` is called.
}

@export_group("Platform")
## The platform's width (x), thickness (y) and depth (z).
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var size := Vector3(4.0, 1.0, 4.0):
	set(value):
		size = value.max(Vector3.ONE * 0.1)
		_rebuild()
## The platform's material. Empty uses a plain grey.
@export var material: Material:
	set(value):
		material = value
		_rebuild()

@export_group("Travel")
## Where the far end is, from the start, in the platform's own axes.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var travel := Vector3(0.0, 0.0, 4.0):
	set(value):
		travel = value
		_update_preview()
## How fast it moves.
@export_range(0.1, 20.0, 0.1, "or_greater", "suffix:m/s") var speed := 2.0
## How long it waits at each end.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:s") var wait_time := 1.0
## What it does between the ends.
@export var mode: Mode = Mode.PING_PONG
## Starts moving when the scene starts. Off holds it at the start until `start()`.
@export var autostart := true

var _distance := 0.0
var _direction := 1.0
var _waiting := 0.0
var _running := false
var _home := Transform3D.IDENTITY


func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	var ghost := _preview()
	if ghost != null:
		ghost.visible = false
	sync_to_physics = true
	_home = transform
	_running = autostart and mode != Mode.ON_CALL


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _running:
		return
	if _waiting > 0.0:
		_waiting -= delta
		return
	var length := travel.length()
	if length <= 0.0:
		return
	_distance = clampf(_distance + _direction * speed * delta, 0.0, length)
	_place()
	if _distance >= length and _direction > 0.0:
		_arrive(true)
	elif _distance <= 0.0 and _direction < 0.0:
		_arrive(false)


## Fraction of the way to the far end, 0 to 1.
func progress() -> float:
	var length := travel.length()
	return _distance / length if length > 0.0 else 0.0


## Moves in the current mode from where it is.
func start() -> void:
	_running = true


## Holds where it is.
func stop() -> void:
	_running = false


## Heads for the far end (in ON_CALL and ONCE it stops there).
func send_to_end() -> void:
	_direction = 1.0
	_waiting = 0.0
	_running = true


## Heads for the start (in ON_CALL and ONCE it stops there).
func send_to_start() -> void:
	_direction = -1.0
	_waiting = 0.0
	_running = true


func _arrive(at_end: bool) -> void:
	if at_end:
		reached_end.emit()
	else:
		reached_start.emit()
	match mode:
		Mode.PING_PONG:
			_direction = -_direction
			_waiting = wait_time
		_:
			_running = false


func _place() -> void:
	var length := travel.length()
	var along := travel * (_distance / length) if length > 0.0 else Vector3.ZERO
	transform = _home.translated_local(along)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if _mesh() == null or _shape() == null or _preview() == null:
		warnings.append("The scene needs `Mesh`, `Shape` and `EndPreview` nodes.")
	return warnings


func _mesh() -> MeshInstance3D:
	return get_node_or_null("%Mesh") as MeshInstance3D


func _shape() -> CollisionShape3D:
	return get_node_or_null("%Shape") as CollisionShape3D


func _preview() -> MeshInstance3D:
	return get_node_or_null("%EndPreview") as MeshInstance3D


# Puts `size` and `material` on the slab's own mesh and shape (each platform has its own copies:
# they are local to the scene), then moves the ghost.
func _rebuild() -> void:
	var mesh := _mesh()
	var shape := _shape()
	var ghost := _preview()
	if mesh == null or shape == null or ghost == null:
		return
	(mesh.mesh as BoxMesh).size = size
	mesh.material_override = material
	(shape.shape as BoxShape3D).size = size
	(ghost.mesh as BoxMesh).size = size
	_update_preview()


func _update_preview() -> void:
	var ghost := _preview()
	if ghost != null:
		ghost.position = travel

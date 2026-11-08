@tool
class_name Door
extends AnimatableBody3D
## A door that slides or swings open. It works on its own: open it from a signal (`open()`), from a
## trigger, or let it open when a body comes near (`auto_open_range`). The panel moves in the
## physics step with the same fixed timestep every run, so a test sees the same door a player does.

## The door finished opening.
signal opened
## The door finished closing.
signal closed
## Something asked a locked door to open.
signal blocked

enum Style {
	SLIDE_UP,  ## The panel rises into the lintel.
	SLIDE_SIDE,  ## The panel slides along its width.
	SWING,  ## The panel turns on a hinge at its left edge.
}

@export_group("Panel")
## The panel's width (x), height (y) and thickness (z).
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var panel_size := Vector3(2.0, 3.0, 0.25):
	set(value):
		panel_size = value.max(Vector3.ONE * 0.05)
		_rebuild_panel()
## The panel's material. Empty uses a plain grey.
@export var panel_material: Material:
	set(value):
		panel_material = value
		_rebuild_panel()

@export_group("Motion")
## How the door opens.
@export var style: Style = Style.SLIDE_UP
## How far a sliding panel travels. Zero slides it by its own height or width, whichever the style
## moves.
@export_range(0.0, 10.0, 0.05, "or_greater", "suffix:m") var slide_distance := 0.0
## How far a swinging panel turns.
@export_range(10.0, 170.0, 1.0, "suffix:deg") var swing_angle := 100.0
## Seconds to go from closed to open.
@export_range(0.05, 10.0, 0.05, "or_greater", "suffix:s") var open_time := 0.8

@export_group("Behaviour")
## Starts open.
@export var start_open := false
## A locked door ignores `open()` until `unlock()` and emits `blocked`.
@export var locked := false
## Closes by itself this long after it opened. Zero keeps it open.
@export_range(0.0, 60.0, 0.1, "or_greater", "suffix:s") var close_after := 0.0
## Opens when a body on the layers below comes within this distance of the door. Zero turns it off.
@export_range(0.0, 20.0, 0.1, "or_greater", "suffix:m") var auto_open_range := 0.0
## Which physics layers count as something that opens the door.
@export_flags_3d_physics var auto_open_mask := 1

var _openness := 0.0
var _target := 0.0
var _open_for := 0.0
var _home := Transform3D.IDENTITY
var _panel: MeshInstance3D
var _shape: CollisionShape3D
var _sensor: Area3D


func _ready() -> void:
	_rebuild_panel()
	if Engine.is_editor_hint():
		return
	sync_to_physics = true
	_home = transform
	_build_sensor()
	_openness = 1.0 if start_open else 0.0
	_target = _openness
	_apply()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if auto_open_range > 0.0 and not locked:
		if _sensor.has_overlapping_bodies():
			open()
	if _target > _openness:
		_openness = minf(_openness + delta / open_time, _target)
		_apply()
		if _openness == 1.0:
			opened.emit()
	elif _target < _openness:
		_openness = maxf(_openness - delta / open_time, _target)
		_apply()
		if _openness == 0.0:
			closed.emit()
	elif _openness == 1.0 and close_after > 0.0:
		_open_for += delta
		if _open_for >= close_after and not _sensor_holds_open():
			close()


## True once the door is fully open.
func is_open() -> bool:
	return _openness >= 1.0


## True while the door is moving.
func is_moving() -> bool:
	return _openness != _target


## 0 when closed, 1 when open.
func openness() -> float:
	return _openness


func open() -> void:
	if locked:
		blocked.emit()
		return
	_open_for = 0.0
	_target = 1.0


func close() -> void:
	_target = 0.0


func toggle() -> void:
	if _target > 0.0:
		close()
	else:
		open()


func lock() -> void:
	locked = true


func unlock() -> void:
	locked = false


func _sensor_holds_open() -> bool:
	return auto_open_range > 0.0 and _sensor.has_overlapping_bodies()


func _apply() -> void:
	var offset := Transform3D.IDENTITY
	match style:
		Style.SLIDE_UP:
			var rise := slide_distance if slide_distance > 0.0 else panel_size.y
			offset.origin = Vector3.UP * rise * _openness
		Style.SLIDE_SIDE:
			var run := slide_distance if slide_distance > 0.0 else panel_size.x
			offset.origin = Vector3.RIGHT * run * _openness
		Style.SWING:
			var hinge := Vector3(-panel_size.x / 2.0, 0.0, 0.0)
			var turn := Basis(Vector3.UP, deg_to_rad(-swing_angle) * _openness)
			offset = Transform3D(turn, hinge - turn * hinge)
	transform = _home * offset


func _rebuild_panel() -> void:
	if _panel == null:
		_panel = MeshInstance3D.new()
		_panel.name = "Panel"
		add_child(_panel)
		_shape = CollisionShape3D.new()
		_shape.name = "Shape"
		add_child(_shape)
	var box := BoxMesh.new()
	box.size = panel_size
	_panel.mesh = box
	_panel.material_override = panel_material
	var collider := BoxShape3D.new()
	collider.size = panel_size
	_shape.shape = collider
	_panel.position = Vector3(0.0, panel_size.y / 2.0, 0.0)
	_shape.position = _panel.position


func _build_sensor() -> void:
	_sensor = Area3D.new()
	_sensor.name = "Sensor"
	_sensor.collision_layer = 0
	_sensor.collision_mask = auto_open_mask
	_sensor.monitoring = auto_open_range > 0.0
	var ball := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(auto_open_range, 0.01)
	ball.shape = sphere
	_sensor.add_child(ball)
	add_child(_sensor)
	_sensor.position = Vector3(0.0, panel_size.y / 2.0, 0.0)

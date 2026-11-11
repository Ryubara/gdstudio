@tool
class_name Door
extends AnimatableBody3D
## A door that slides or swings open. It works on its own: open it from a signal (`open()`),
## from a trigger, or let it open when a body comes near (`auto_open_range`). The panel moves in
## the physics step with the same fixed timestep every run, so a test sees the same door a
## player does.
##
## Its parts are nodes of `door.tscn`: `Panel` (the mesh), `Shape` (what blocks the way),
## `Sensor` (an area, its sphere is `auto_open_range`, drawn by the editor) and `Interactable`
## (where a character's interact button finds it; its `interacted` signal is connected to
## `interact()` in the scene), so open the scene to restyle the door. `panel_size` and
## `auto_open_range` follow the inspector live.

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
		_apply_live()
## The panel's material. Empty uses a plain grey.
@export var panel_material: Material:
	set(value):
		panel_material = value
		_rebuild_panel()

@export_group("Motion")
## How the door opens.
@export var style: Style = Style.SLIDE_UP:
	set(value):
		style = value
		_apply_live()
## How far a sliding panel travels. Zero slides it by its own height or width, whichever the
## style moves.
@export_range(0.0, 10.0, 0.05, "or_greater", "suffix:m") var slide_distance := 0.0:
	set(value):
		slide_distance = value
		_apply_live()
## How far a swinging panel turns.
@export_range(10.0, 170.0, 1.0, "suffix:deg") var swing_angle := 100.0:
	set(value):
		swing_angle = value
		_apply_live()
## Seconds to go from closed to open.
@export_range(0.05, 10.0, 0.05, "or_greater", "suffix:s") var open_time := 0.8

@export_group("Behaviour")
## Starts open.
@export var start_open := false
## A locked door ignores `open()` until `unlock()` and emits `blocked`.
@export var locked := false
## Closes by itself this long after it opened. Zero keeps it open.
@export_range(0.0, 60.0, 0.1, "or_greater", "suffix:s") var close_after := 0.0
## Opens when a character (a `CharacterBody3D` on the layers below) comes within this distance
## of the door, and closes `close_after` seconds after the last one left. Walls, floors, props and
## the door itself never count. Closing the door by hand while a character stands in range keeps
## it shut until that character leaves and comes back. Zero turns it off.
@export_range(0.0, 20.0, 0.1, "or_greater", "suffix:m") var auto_open_range := 0.0:
	set(value):
		auto_open_range = value
		_update_sensor()
## Which physics layers a character must be on to open the door: Characters
## (`PhysicsLayers.CHARACTER_SENSOR_MASK`), so the sensor never hears of the walls and floor around
## it. A body that is not a `CharacterBody3D` never opens it either, whatever its layer.
@export_flags_3d_physics var auto_open_mask := PhysicsLayers.CHARACTER_SENSOR_MASK:
	set(value):
		auto_open_mask = value
		_update_sensor()
## Lets a character open and close the door with its interact button: switches the door's
## `Interactable` on or off.
@export var player_can_use := true:
	set(value):
		player_can_use = value
		_update_usable()

var _openness := 0.0
var _target := 0.0
var _open_for := 0.0
var _home := Transform3D.IDENTITY
var _usable_home := Transform3D.IDENTITY
# Set when the door is closed with a character in range: auto-open waits for the range to empty.
var _held_shut := false
# The characters inside the auto-open range, kept by the sensor's signals (no query a tick).
var _near: Array[CharacterBody3D] = []


func _ready() -> void:
	_rebuild_panel()
	_update_sensor()
	if Engine.is_editor_hint():
		return
	var sensor := _sensor()
	if sensor != null:
		sensor.body_entered.connect(_on_sensor_entered)
		sensor.body_exited.connect(_on_sensor_exited)
	sync_to_physics = true
	_home = transform
	var usable := _interactable()
	if usable != null:
		_usable_home = usable.transform
	_update_usable()
	_openness = 1.0 if start_open else 0.0
	_target = _openness
	_apply()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if auto_open_range > 0.0:
		if not _character_near():
			_held_shut = false
		elif not locked and not _held_shut:
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
		_open_for = 0.0 if _character_near() else _open_for + delta
		if _open_for >= close_after:
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
	_held_shut = false
	_target = 1.0


## Closes the door. With a character in the auto-open range it stays shut until the range empties.
func close() -> void:
	_target = 0.0
	_held_shut = _character_near()


## What the door's `Interactable` calls when a character uses it: opens a closed door, closes an
## open one.
func interact(_by: Node3D = null) -> void:
	toggle()


func toggle() -> void:
	if _target > 0.0:
		close()
	else:
		open()


func lock() -> void:
	locked = true


func unlock() -> void:
	locked = false


# True while a character is inside the auto-open range. The mask keeps the level out; only a
# `CharacterBody3D` counts as well, for a game whose mask also lists the level or props.
func _character_near() -> bool:
	return auto_open_range > 0.0 and not _near.is_empty()


func _on_sensor_entered(body: Node3D) -> void:
	if body is CharacterBody3D and not _near.has(body):
		_near.append(body)


func _on_sensor_exited(body: Node3D) -> void:
	_near.erase(body)


# Moves the panel to where the new motion settings put it, while the game runs.
func _apply_live() -> void:
	if is_node_ready() and not Engine.is_editor_hint():
		_apply()


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
	# The sensor measures from where the closed door stands, so it does not ride up with the panel.
	var sensor := _sensor()
	var panel := _panel()
	if sensor != null and panel != null:
		sensor.transform = offset.affine_inverse() * Transform3D(Basis.IDENTITY, panel.position)
	# So does the `Interactable`: a gate that swings away is still found where it stands closed.
	var usable := _interactable()
	if usable != null:
		usable.transform = offset.affine_inverse() * _usable_home


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if _panel() == null or _shape() == null or _sensor() == null:
		(
			warnings
			. append(
				"The scene needs `Panel` (MeshInstance3D), `Shape` (CollisionShape3D) and `Sensor` (Area3D)."
			)
		)
	if player_can_use and _interactable() == null:
		warnings.append(
			"`player_can_use` is on but the door has no `Interactable` child: nobody can use it."
		)
	return warnings


func _panel() -> MeshInstance3D:
	return get_node_or_null("%Panel") as MeshInstance3D


func _shape() -> CollisionShape3D:
	return get_node_or_null("%Shape") as CollisionShape3D


func _sensor() -> Area3D:
	return get_node_or_null("%Sensor") as Area3D


func _interactable() -> Interactable:
	for child in get_children():
		if child is Interactable:
			return child
	return null


# Puts `panel_size` and `panel_material` on the panel's own mesh and shape (each door has its own
# copies: they are local to the scene).
func _rebuild_panel() -> void:
	var panel := _panel()
	var shape := _shape()
	if panel == null or shape == null:
		return
	(panel.mesh as BoxMesh).size = panel_size
	panel.material_override = panel_material
	(shape.shape as BoxShape3D).size = panel_size
	panel.position = Vector3(0.0, panel_size.y / 2.0, 0.0)
	shape.position = panel.position
	var sensor := _sensor()
	if sensor != null:
		sensor.position = panel.position


# Puts the range and the mask on the sensor, which watches only when there is a range.
func _update_sensor() -> void:
	var sensor := _sensor()
	if sensor == null:
		return
	sensor.collision_mask = auto_open_mask
	sensor.monitoring = auto_open_range > 0.0 and not Engine.is_editor_hint()
	if not sensor.monitoring:
		_near.clear()
	var ball := sensor.get_node_or_null("%SensorShape") as CollisionShape3D
	if ball != null:
		(ball.shape as SphereShape3D).radius = maxf(auto_open_range, 0.01)


# A usable door's `Interactable` is on; a character's interactor passes over one that is off.
func _update_usable() -> void:
	var usable := _interactable()
	if usable != null:
		usable.enabled = player_can_use
	update_configuration_warnings()

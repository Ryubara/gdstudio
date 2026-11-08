@tool
class_name Pickup
extends Area3D
## Something to collect: a coin, a key, a health pack. It spins and bobs, and when a body on the
## chosen layers touches it (the Collision > Mask below), `collected` says who took what. It
## does nothing else: the game decides what an item means (a body with a `collect(item_id,
## amount)` method, like `Player`, is also told). It works on its own and can come back after a
## while.
##
## Its look is two nodes of `pickup.tscn`, `Visual` (the mesh) and `Shape` (what a body touches),
## so open the scene to restyle it. `tint` and `item_size` follow the inspector live.

## A body took the pickup. `item_id` and `amount` are the inspector's values.
signal collected(collector: Node3D, item_id: StringName, amount: int)
## The pickup came back after `respawn_time`.
signal respawned

@export_group("Item")
## What the item is called; the game reads this to decide what it gives.
@export var item_id: StringName = &"coin"
## How many of it one pickup is worth.
@export_range(1, 999, 1, "or_greater") var amount := 1
## The shape's colour.
@export var tint := Color(1.0, 0.78, 0.2):
	set(value):
		tint = value
		_update_look()

@export_group("Look")
## How wide the item is.
@export_range(0.1, 3.0, 0.05, "suffix:m") var item_size := 0.5:
	set(value):
		item_size = value
		_update_look()
## Turn speed. Zero keeps it still.
@export_range(0.0, 720.0, 1.0, "suffix:deg/s") var spin_speed := 120.0
## How far it rises and falls. Zero keeps it still.
@export_range(0.0, 1.0, 0.01, "suffix:m") var bob_height := 0.12
## Seconds for one rise and fall.
@export_range(0.2, 10.0, 0.1, "suffix:s") var bob_period := 1.6

@export_group("Respawn")
## Comes back this long after it was taken. Zero collects it once and removes it.
@export_range(0.0, 600.0, 0.5, "or_greater", "suffix:s") var respawn_time := 0.0

var _phase := 0.0
var _hidden_for := -1.0


func _ready() -> void:
	_update_look()
	if Engine.is_editor_hint():
		set_process(false)
		return
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_phase += delta
	var visual := _visual()
	visual.rotation.y = deg_to_rad(spin_speed) * _phase
	visual.position.y = sin(TAU * _phase / bob_period) * bob_height
	if _hidden_for >= 0.0:
		_hidden_for += delta
		if respawn_time > 0.0 and _hidden_for >= respawn_time:
			_show_again()


## True while the item can be taken.
func is_available() -> bool:
	return monitoring and _visual().visible


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if _visual() == null or _shape() == null:
		warnings.append(
			"The scene needs a `Visual` (MeshInstance3D) and a `Shape` (CollisionShape3D)."
		)
	return warnings


func _visual() -> MeshInstance3D:
	return get_node_or_null("%Visual") as MeshInstance3D


func _shape() -> CollisionShape3D:
	return get_node_or_null("%Shape") as CollisionShape3D


func _on_body_entered(body: Node3D) -> void:
	if not is_available():
		return
	collected.emit(body, item_id, amount)
	# A body that keeps count (`Player`) is told too, so no wiring is needed to carry a coin.
	if body.has_method(&"collect"):
		body.call(&"collect", item_id, amount)
	_hide_now()
	if respawn_time <= 0.0:
		queue_free()


func _hide_now() -> void:
	_visual().visible = false
	set_deferred("monitoring", false)
	_hidden_for = 0.0


func _show_again() -> void:
	_visual().visible = true
	monitoring = true
	_hidden_for = -1.0
	respawned.emit()


# Puts `tint` and `item_size` on the nodes' own resources (each pickup has its own copies:
# they are local to the scene).
func _update_look() -> void:
	var visual := _visual()
	var shape := _shape()
	if visual == null or shape == null:
		return
	var gem := visual.mesh as SphereMesh
	gem.radius = item_size / 2.0
	gem.height = item_size
	var paint := visual.material_override as StandardMaterial3D
	paint.albedo_color = tint
	paint.emission = tint
	(shape.shape as SphereShape3D).radius = maxf(item_size, 0.5) * 0.75

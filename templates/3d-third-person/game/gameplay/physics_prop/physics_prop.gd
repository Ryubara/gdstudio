@tool
class_name PhysicsProp
extends RigidBody3D
## A crate, barrel or ball that falls, rolls and gets pushed. One shape, one size and one weight
## in the inspector; the mesh and the collision follow. A prop that ends up below `fall_limit`
## (it was pushed off the map) goes back to where it started, so a level never loses one.
##
## `physics_prop.tscn` holds all three shapes as nodes (`CrateMesh` and `CrateShape`, `BarrelMesh`
## and `BarrelShape`, `BallMesh` and `BallShape`) and `shape` shows one of them, so each can be
## restyled in the scene. Everything below follows the inspector live.

## The prop went back to its start after falling out of the map.
signal returned

enum Shape {
	BOX,  ## A crate.
	BARREL,  ## A cylinder standing up.
	BALL,  ## A sphere.
}

@export_group("Shape")
## What the prop is.
@export var shape: Shape = Shape.BOX:
	set(value):
		shape = value
		_rebuild()
## Width (x), height (y) and depth (z). A barrel uses x as its diameter; a ball uses x as its
## diameter.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var size := Vector3.ONE:
	set(value):
		size = value.max(Vector3.ONE * 0.1)
		_rebuild()
## The prop's material. Empty uses a plain grey.
@export var material: Material:
	set(value):
		material = value
		_rebuild()

@export_group("Body")
## How heavy it is.
@export_range(0.1, 1000.0, 0.1, "or_greater", "suffix:kg") var weight := 10.0:
	set(value):
		weight = value
		mass = value
## How much it slides: 0 is ice, 1 is rubber.
@export_range(0.0, 1.0, 0.01) var grip := 0.6:
	set(value):
		grip = value
		_update_surface()
## How much it bounces.
@export_range(0.0, 1.0, 0.01) var bounciness := 0.1:
	set(value):
		bounciness = value
		_update_surface()

@export_group("Safety")
## Below this height (y) the prop returns to its start. Set it under the lowest floor.
@export_range(-1000.0, 0.0, 1.0, "or_greater", "suffix:m") var fall_limit := -20.0

var _start := Transform3D.IDENTITY


func _ready() -> void:
	mass = weight
	_update_surface()
	_rebuild()
	_start = transform


## Mass and surface come from `weight`, `grip` and `bounciness`, so the inspector shows those
## only and the scene keeps neither.
func _validate_property(property: Dictionary) -> void:
	if property.name in ["mass", "physics_material_override"]:
		property.usage = PROPERTY_USAGE_NONE


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if global_position.y < fall_limit:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		transform = _start
		returned.emit()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	for part_name in [
		"CrateMesh", "CrateShape", "BarrelMesh", "BarrelShape", "BallMesh", "BallShape"
	]:
		if get_node_or_null("%" + part_name) == null:
			warnings.append("The scene needs a node named `%s`." % part_name)
	return warnings


# Puts `grip` and `bounciness` on the body's surface (made once, kept by the engine).
func _update_surface() -> void:
	if physics_material_override == null:
		physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = grip
	physics_material_override.bounce = bounciness


# Shows the chosen shape, sizes the three shapes and their meshes from `size`, and paints them
# with `material`. Each prop has its own mesh and shape resources (they are local to the scene).
func _rebuild() -> void:
	var crate := _mesh("Crate")
	var barrel := _mesh("Barrel")
	var ball := _mesh("Ball")
	if crate == null or barrel == null or ball == null:
		return
	if _collider("Crate") == null or _collider("Barrel") == null or _collider("Ball") == null:
		return
	(crate.mesh as BoxMesh).size = size
	(_collider("Crate").shape as BoxShape3D).size = size
	var cylinder := barrel.mesh as CylinderMesh
	cylinder.top_radius = size.x / 2.0
	cylinder.bottom_radius = size.x / 2.0
	cylinder.height = size.y
	var barrel_shape := _collider("Barrel").shape as CylinderShape3D
	barrel_shape.radius = size.x / 2.0
	barrel_shape.height = size.y
	var sphere := ball.mesh as SphereMesh
	sphere.radius = size.x / 2.0
	sphere.height = size.x
	(_collider("Ball").shape as SphereShape3D).radius = size.x / 2.0
	for index in 3:
		var part_name: String = ["Crate", "Barrel", "Ball"][index]
		_mesh(part_name).visible = index == shape
		_mesh(part_name).material_override = material
		_collider(part_name).disabled = index != shape


func _mesh(part_name: String) -> MeshInstance3D:
	return get_node_or_null("%" + part_name + "Mesh") as MeshInstance3D


func _collider(part_name: String) -> CollisionShape3D:
	return get_node_or_null("%" + part_name + "Shape") as CollisionShape3D

@tool
class_name PhysicsProp
extends RigidBody3D
## A crate, barrel or ball that falls, rolls and gets pushed. One shape, one size and one weight in
## the inspector; the mesh and the collision follow. A prop that ends up below `fall_limit` (it was
## pushed off the map) goes back to where it started, so a level never loses one.

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
@export_range(0.0, 1.0, 0.01) var grip := 0.6
## How much it bounces.
@export_range(0.0, 1.0, 0.01) var bounciness := 0.1

@export_group("Safety")
## Below this height (y) the prop returns to its start. Set it under the lowest floor.
@export_range(-1000.0, 0.0, 1.0, "or_greater", "suffix:m") var fall_limit := -20.0

var _start := Transform3D.IDENTITY
var _mesh: MeshInstance3D
var _collision: CollisionShape3D


func _ready() -> void:
	mass = weight
	var surface := PhysicsMaterial.new()
	surface.friction = grip
	surface.bounce = bounciness
	physics_material_override = surface
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


func _rebuild() -> void:
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_mesh.name = "Mesh"
		add_child(_mesh)
		_collision = CollisionShape3D.new()
		_collision.name = "Shape"
		add_child(_collision)
	match shape:
		Shape.BOX:
			var box := BoxMesh.new()
			box.size = size
			_mesh.mesh = box
			var collider := BoxShape3D.new()
			collider.size = size
			_collision.shape = collider
		Shape.BARREL:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = size.x / 2.0
			cylinder.bottom_radius = size.x / 2.0
			cylinder.height = size.y
			cylinder.radial_segments = 20
			cylinder.rings = 1
			_mesh.mesh = cylinder
			var collider := CylinderShape3D.new()
			collider.radius = size.x / 2.0
			collider.height = size.y
			_collision.shape = collider
		Shape.BALL:
			var sphere := SphereMesh.new()
			sphere.radius = size.x / 2.0
			sphere.height = size.x
			sphere.radial_segments = 24
			sphere.rings = 12
			_mesh.mesh = sphere
			var collider := SphereShape3D.new()
			collider.radius = size.x / 2.0
			_collision.shape = collider
	_mesh.material_override = material

@tool
class_name Projectile
extends CharacterBody3D
## A sphere that flies where the `Weapon` sent it. Each physics tick it moves along its velocity
## (falling by `gravity`), and when it touches something it pushes a `RigidBody3D` with `impulse`,
## tells a body that has a `take_shot(projectile, point)` method (a `Target`), reports the hit to
## the level's `Impacts` (the mark, effect and sound of the surface), and then either
## bounces off the level (`bounces`) or stops. It is gone after `lifetime` seconds.
##
## Its look is two nodes of `projectile.tscn`, `Mesh` and `Shape`, so open the scene to restyle
## it. `size` and `tint` follow the inspector live. `Weapon` sets every number below from its own
## inspector when it fires, so tune the weapon, not the scene.

## The projectile touched `collider` at `point`; `normal` points away from the surface.
signal impacted(collider: Node, point: Vector3, normal: Vector3)

@export_group("Body")
## The sphere's diameter.
@export_range(0.02, 1.0, 0.01, "suffix:m") var size := 0.14:
	set(value):
		size = value
		_update_look()
## The sphere's colour (it glows, so it reads in shadow).
@export var tint := Color(1.0, 0.85, 0.35):
	set(value):
		tint = value
		_update_look()

@export_group("Flight")
## How fast it falls. Zero flies straight.
@export_range(0.0, 30.0, 0.1, "suffix:m/s²") var gravity := 0.0
## It disappears this long after it was fired.
@export_range(0.2, 20.0, 0.1, "suffix:s") var lifetime := 3.0

@export_group("Hit")
## The push it gives a physics body it hits, along its flight (momentum, in newton seconds: a
## 60 kg cube given 40 moves at about 0.7 m/s).
@export_range(0.0, 500.0, 0.5, "suffix:N·s") var impulse := 40.0
## How many times it bounces off the level before it stops.
@export_range(0, 8, 1) var bounces := 0
## The share of its speed a bounce keeps.
@export_range(0.0, 1.0, 0.01) var bounce_keep := 0.6

@export_group("Impact")
## On: where it lands it tells the level's `Impacts` (a mark, an effect and a sound by the kind
## of surface). Off: it lands without a trace. A `Weapon` turns this off for its shots when its own
## `impacts` is off.
@export var impact_effects := true

var _age := 0.0
var _bounces_left := 0


func _ready() -> void:
	_bounces_left = bounces
	_update_look()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	velocity.y -= gravity * delta
	var collision := move_and_collide(velocity * delta)
	if collision != null:
		_touch(collision)


## Starts it flying from `origin` along `direction` at `speed`. Skips `shooter`, so it never hits
## the one who fired it. Call it after the projectile is in the tree.
func launch(
	origin: Vector3, direction: Vector3, speed: float, shooter: CollisionObject3D = null
) -> void:
	_bounces_left = bounces
	if shooter != null:
		add_collision_exception_with(shooter)
	global_position = origin
	velocity = direction.normalized() * speed
	reset_physics_interpolation()


## How long it has flown, in seconds.
func age() -> float:
	return _age


func _touch(collision: KinematicCollision3D) -> void:
	var collider := collision.get_collider()
	var point := collision.get_position()
	var normal := collision.get_normal()
	var direction := velocity.normalized()
	var movable := false
	if collider is RigidBody3D:
		var body := collider as RigidBody3D
		body.apply_impulse(direction * impulse, point - body.global_position)
		movable = true
	if collider != null and collider.has_method(&"take_shot"):
		collider.call(&"take_shot", self, point)
		movable = true
	impacted.emit(collider, point, normal)
	if impact_effects and collider != null:
		get_tree().call_group(&"impacts", &"impact", collider, point, normal)
	if _bounces_left > 0 and not movable:
		_bounces_left -= 1
		velocity = velocity.bounce(normal) * bounce_keep
		return
	queue_free()


# Puts `size` and `tint` on the nodes' own resources (each projectile has its own copies: they
# are local to the scene).
func _update_look() -> void:
	var mesh_node := get_node_or_null("%Mesh") as MeshInstance3D
	var shape_node := get_node_or_null("%Shape") as CollisionShape3D
	if mesh_node == null or shape_node == null:
		return
	var sphere := mesh_node.mesh as SphereMesh
	sphere.radius = size / 2.0
	sphere.height = size
	(shape_node.shape as SphereShape3D).radius = size / 2.0
	var paint := mesh_node.material_override as StandardMaterial3D
	paint.albedo_color = tint
	paint.emission = tint


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if get_node_or_null("%Mesh") == null or get_node_or_null("%Shape") == null:
		warnings.append(
			"The scene needs a `Mesh` (MeshInstance3D) and a `Shape` (CollisionShape3D)."
		)
	return warnings

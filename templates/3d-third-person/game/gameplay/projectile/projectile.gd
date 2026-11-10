@tool
class_name Projectile
extends CharacterBody3D
## A sphere that flies where the `Weapon` sent it. Each physics tick it moves along its velocity
## (falling by `gravity`), and when it touches something it pushes a `RigidBody3D` with `impulse`,
## hits a character on the body part in its path (the character's `HitZones`: `damage` times the
## part's multiplier; between the parts it flies on), tells a body that has a
## `take_shot(projectile, point)` method (a `Target`), reports the hit to
## the level's `Impacts` (the mark, effect and sound of the surface), and then either
## bounces off the level (`bounces`) or stops. It is gone after `lifetime` seconds.
##
## Its look is two nodes of `projectile.tscn`, `Mesh` and `Shape`, so open the scene to restyle
## it. `size` and `tint` follow the inspector live. `Weapon` sets every number below from its
## `WeaponDef` when it fires, so tune the definition, not the scene.
##
## Every projectile of one size shares one mesh and one shape, and every one of one colour one
## material (the scene's material, tinted), so a thousand shots make three resources, not three
## thousand. A `Weapon` keeps its projectiles in a pool: a finished one (`recycled`) parks out of
## the physics, hidden, and says `finished` instead of freeing itself, and is fired again.

## The projectile touched `collider` at `point`; `normal` points away from the surface.
signal impacted(collider: Node, point: Vector3, normal: Vector3)
## The projectile ended (it hit, or its lifetime ran out) and, `recycled`, parked to be fired again.
signal finished(projectile: Projectile)

# The shared looks: one sphere mesh and one shape a size, one material a base material and colour.
static var _meshes: Dictionary[float, SphereMesh] = {}
static var _shapes: Dictionary[float, SphereShape3D] = {}
static var _paints: Dictionary[String, Material] = {}
# Projectiles alive: the last one to go empties the shared looks, which a static would otherwise
# hold past the engine's exit (CI refuses a run that prints `leaked at exit`).
static var _alive := 0

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
## The damage of a hit on a character, before its hit zone's multiplier.
@export_range(0.0, 1000.0, 0.5, "or_greater") var damage := 34.0
## How many times it bounces off the level before it stops.
@export_range(0, 8, 1) var bounces := 0
## The share of its speed a bounce keeps.
@export_range(0.0, 1.0, 0.01) var bounce_keep := 0.6

@export_group("Impact")
## On: where it lands it tells the level's `Impacts` (a mark, an effect and a sound by the kind
## of surface). Off: it lands without a trace. A `Weapon` turns this off for its shots when its own
## `impacts` is off.
@export var impact_effects := true

## On: when it ends it parks and says `finished` (a `Weapon`'s pool fires it again). Off: it frees
## itself.
var recycled := false
## `impact_effects` as the scene has it, kept for a pooled projectile that a weapon set off once.
var scene_impact_effects := true

var _age := 0.0
var _bounces_left := 0
var _flying := false
var _base_paint: Material
var _readied := false
var _shooter: CollisionObject3D


func _init() -> void:
	_alive += 1


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	_alive -= 1
	if _alive <= 0:
		_alive = 0
		_meshes.clear()
		_shapes.clear()
		_paints.clear()


func _ready() -> void:
	if not _readied:
		_readied = true
		scene_impact_effects = impact_effects
		var mesh_node := get_node_or_null("%Mesh") as MeshInstance3D
		if mesh_node != null and _base_paint == null:
			_base_paint = mesh_node.material_override
	_bounces_left = bounces
	_update_look()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _flying:
		return
	_age += delta
	if _age >= lifetime:
		_end()
		return
	velocity.y -= gravity * delta
	var collision := move_and_collide(velocity * delta)
	# A shot that passes between a character's parts flies on through the capsule, this tick.
	for attempt in 3:
		if collision == null or not _touch(collision):
			return
		collision = move_and_collide(collision.get_remainder())


## Starts it flying from `origin` along `direction` at `speed`. Skips `shooter`, so it never hits
## the one who fired it. Call it after the projectile is in the tree.
func launch(
	origin: Vector3, direction: Vector3, speed: float, shooter: CollisionObject3D = null
) -> void:
	_bounces_left = bounces
	_age = 0.0
	_flying = true
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	_shooter = shooter
	# A pooled projectile flew through other characters' capsules before: it meets them again.
	for skipped in get_collision_exceptions():
		remove_collision_exception_with(skipped)
	if shooter != null:
		add_collision_exception_with(shooter)
	global_position = origin
	velocity = direction.normalized() * speed
	reset_physics_interpolation()


## How long it has flown, in seconds.
func age() -> float:
	return _age


## True from `launch()` until it hits or its lifetime runs out.
func is_flying() -> bool:
	return _flying


## Stops it where it is, with no hit (a pool taking its oldest projectile back to fire it again).
func halt() -> void:
	_flying = false
	velocity = Vector3.ZERO


# It hit, or its time is up: it parks for its pool, or frees itself.
func _end() -> void:
	_flying = false
	velocity = Vector3.ZERO
	if not recycled:
		queue_free()
		return
	visible = false
	# Out of the physics space (the default disable mode removes the body) and out of the process,
	# once the physics callback it ended in is over.
	_park.call_deferred()
	finished.emit(self)


func _park() -> void:
	if not _flying:
		process_mode = Node.PROCESS_MODE_DISABLED


# Answers a touch; true when the shot passed between a character's parts and flies on.
func _touch(collision: KinematicCollision3D) -> bool:
	var collider := collision.get_collider()
	var point := collision.get_position()
	var normal := collision.get_normal()
	var direction := velocity.normalized()
	var movable := false
	var zones := HitZones.of(collider)
	if zones != null:
		var record := zones.shot(
			collider, point, direction, damage, impulse, _shooter as Node3D, global_position
		)
		if record == null:
			add_collision_exception_with(collider)
			return true
		zones.deliver(record)
		movable = true
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
		return false
	_end()
	return false


# Puts `size` and `tint` on the nodes through the shared resources of that size and colour.
func _update_look() -> void:
	var mesh_node := get_node_or_null("%Mesh") as MeshInstance3D
	var shape_node := get_node_or_null("%Shape") as CollisionShape3D
	if mesh_node == null or shape_node == null:
		return
	if Engine.is_editor_hint():
		# In the editor the scene's own resources show the inspector's numbers.
		var own := mesh_node.mesh as SphereMesh
		if own != null:
			own.radius = size / 2.0
			own.height = size
		var own_shape := shape_node.shape as SphereShape3D
		if own_shape != null:
			own_shape.radius = size / 2.0
		return
	var key := snappedf(size, 0.001)
	if not _meshes.has(key):
		var sphere := SphereMesh.new()
		var template := mesh_node.mesh as SphereMesh
		if template != null:
			sphere.radial_segments = template.radial_segments
			sphere.rings = template.rings
		sphere.radius = key / 2.0
		sphere.height = key
		_meshes[key] = sphere
		var ball := SphereShape3D.new()
		ball.radius = key / 2.0
		_shapes[key] = ball
	mesh_node.mesh = _meshes[key]
	shape_node.shape = _shapes[key]
	if _base_paint == null:
		_base_paint = mesh_node.material_override
	mesh_node.material_override = _paint(_base_paint, tint)


## The shared material of `base` in `tint` (made once for each pair).
static func _paint(base: Material, colour: Color) -> Material:
	var standard := base as StandardMaterial3D
	if standard == null:
		return base
	var key := "%d:%s" % [base.get_instance_id(), colour.to_html()]
	if not _paints.has(key):
		var made := standard.duplicate() as StandardMaterial3D
		made.albedo_color = colour
		made.emission = colour
		_paints[key] = made
	return _paints[key]


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if get_node_or_null("%Mesh") == null or get_node_or_null("%Shape") == null:
		warnings.append(
			"The scene needs a `Mesh` (MeshInstance3D) and a `Shape` (CollisionShape3D)."
		)
	return warnings

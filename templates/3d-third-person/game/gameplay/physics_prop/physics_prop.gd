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
##
## Online (its `NetEntity` child, kind `prop`) the server simulates it and pushes it; its records
## ride each TICK while it is awake (`PropState`: where it is, how it is turned, whether it fell
## asleep). A client's copy is a frozen static body put where the records say at the tick of the
## command it predicts (`PropTrack`: blended between records, moved on at their speed past the
## newest), so the predicted body meets it about where the server's body does; it is pushed by no
## one and falls nowhere (third-person/net-world.md#props).

## The prop went back to its start after falling out of the map.
signal returned

enum Shape {
	BOX,  ## A crate.
	BARREL,  ## A cylinder standing up.
	BALL,  ## A sphere.
}

## Ticks after a return to the start during which the server's records say it jumped (two TICKs).
const JUMP_TICKS := 2 * NetLimits.TICK_RATE / NetLimits.SNAPSHOT_RATE

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

@export_group("Pushing")
## The speed the character gives this prop when it pushes it (the character walks a little
## faster, so it stays against it). A low number (a heavy cube pushed at 1.2 m/s) keeps the push
## animation readable. Zero leaves it to the character's own pushing
## (`CharacterTuning.push_strength`).
@export_range(0.0, 6.0, 0.05, "suffix:m/s") var push_speed := 0.0

@export_group("Safety")
## Below this height (y) the prop returns to its start. Set it under the lowest floor.
@export_range(-1000.0, 0.0, 1.0, "or_greater", "suffix:m") var fall_limit := -20.0

var _start := Transform3D.IDENTITY
# The prop's place in an online game (its `NetEntity` child), or null.
var _net: NetEntity
# On a client: the server's records, and the tick the copy was last put at.
var _track: PropTrack
var _placed_tick := -1
# On a client: the copy stands where the newest record, an asleep one, put it (nothing to place
# until the next record: a prop at rest costs nothing a step).
var _resting := false
# On the server: the last record said the prop was asleep; the tick it went back to its start.
var _said_asleep := false
var _jumped_at := -1


func _ready() -> void:
	mass = weight
	_update_surface()
	_rebuild()
	_start = transform
	if Engine.is_editor_hint():
		return
	_net = NetEntity.of(self)
	if _net != null:
		_net.serve(net_write, net_read, net_set_role, net_place)
		_net.streams(net_streams)


## Mass and surface come from `weight`, `grip` and `bounciness`, so the inspector shows those
## only and the scene keeps neither.
func _validate_property(property: Dictionary) -> void:
	if property.name in ["mass", "physics_material_override"]:
		property.usage = PROPERTY_USAGE_NONE


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _is_remote():
		return
	if global_position.y < fall_limit:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		transform = _start
		_jumped_at = _net.now() if _net != null else -1
		returned.emit()


# --- Online (NetEntity) ---


## Who runs the prop (`NetWorld` sets it). On the server it stays a rigid body and is never put at
## a tick; on a client it is frozen as a static body, which a body stepped in the same frame meets
## at once where `net_place` put it (third-person/net-world.md#net-world).
func net_set_role(role: NetEntity.Role) -> void:
	match role:
		NetEntity.Role.SERVER:
			_net.place = Callable()
		NetEntity.Role.CLIENT:
			_track = PropTrack.new()
			freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			freeze = true
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			_net.stream = Callable()


## On a client: puts the copy where the server's records have the prop at `tick`.
func net_place(tick: int) -> void:
	if tick == _placed_tick or _resting or _track == null or _track.is_empty():
		return
	_placed_tick = tick
	var goal := _track.sample(tick, global_transform)
	_resting = _track.newest().asleep and tick >= _track.newest_tick()
	if goal.is_equal_approx(global_transform):
		return
	global_transform = goal
	force_update_transform()


## On the server: whether this TICK carries the prop: while it is awake, and once more as it falls
## asleep (that record says so, and none follows until it wakes).
func net_streams() -> bool:
	if not sleeping:
		_said_asleep = false
		return true
	if _said_asleep:
		return false
	_said_asleep = true
	return true


## The prop's state as the server has it now (`PropState`, 11 bytes; a prop is not a function of
## the tick, so `at_tick` is where a client files it, and a record within `JUMP_TICKS` of a return
## to the start says it jumped).
func net_write(at_tick: int) -> PackedByteArray:
	var jumped := _jumped_at >= 0 and absi(at_tick - _jumped_at) <= JUMP_TICKS
	var state := PropState.make(
		global_position, global_basis.get_rotation_quaternion(), sleeping, jumped
	)
	return state.write()


## On a client: files a record written as at server tick `at_tick` (false for one that is not a
## prop's).
func net_read(state: PackedByteArray, at_tick: int) -> bool:
	var read := PropState.read(state)
	if read == null or _track == null:
		return false
	_track.push(at_tick, read)
	_placed_tick = -1
	_resting = false
	if read.jumped:
		returned.emit()
	return true


## The server's records this client holds (null off a client; a test reads them).
func net_track() -> PropTrack:
	return _track


# A client of an online game: the server's records move this prop.
func _is_remote() -> bool:
	return _net != null and _net.role == NetEntity.Role.CLIENT


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

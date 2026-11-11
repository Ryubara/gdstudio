@tool
class_name MovingPlatform
extends AnimatableBody3D
## A platform that carries whatever stands on it between two points. Set the travel in the
## inspector, or call `start()`, `stop()` and `send_to_end()` from a trigger. Where it is is a pure
## function of the physics tick (`position_at`): each change starts a ride at a tick, so a rider
## and a test see the same ride every time, and in an online game the server and a predicting
## client put the slab at the same place for the same tick (its `NetEntity`, `NetWorld`).
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

## Platforms driven by an online world in this process (`PlatformRider` looks for one only then).
static var online_count := 0


## Where a ride is at one moment: the distance from the start along `travel`, which way it goes,
## the seconds it still waits at an end, whether it moves at all, and the ends it reached since the
## ride began (the last of them the far end when `at_end`).
class Ride:
	extends RefCounted
	var distance := 0.0
	var direction := 1.0
	var wait := 0.0
	var running := false
	var arrivals := 0
	var at_end := false

	func copy() -> Ride:
		var out := Ride.new()
		out.distance = distance
		out.direction = direction
		out.wait = wait
		out.running = running
		out.arrivals = arrivals
		out.at_end = at_end
		return out


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
		var ride := _ride_now()
		travel = value
		_rebase(ride)
		_update_preview()
## How fast it moves.
@export_range(0.1, 20.0, 0.1, "or_greater", "suffix:m/s") var speed := 2.0:
	set(value):
		var ride := _ride_now()
		speed = value
		_rebase(ride)
## How long it waits at each end.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:s") var wait_time := 1.0:
	set(value):
		var ride := _ride_now()
		wait_time = value
		_rebase(ride)
## What it does between the ends.
@export var mode: Mode = Mode.PING_PONG:
	set(value):
		var ride := _ride_now()
		mode = value
		_rebase(ride)
## Starts moving when the scene starts. Off holds it at the start until `start()`.
@export var autostart := true

## The tick the world last put the slab at (online: `net_place`; offline: this step).
var placed_tick := 0

# The ride under way, as it was at tick `_start`; before `_start`, the ride before it.
var _start := 0
var _ride := Ride.new()
var _was_start := 0
var _was := Ride.new()
# The ticks this platform has stepped: its clock when no server drives it.
var _tick := 0
var _seen_arrivals := 0
var _home := Transform3D.IDENTITY
# The platform's place in an online game (its `NetEntity` child), or null.
var _net: NetEntity
var _counted := false


func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	var ghost := _preview()
	if ghost != null:
		ghost.visible = false
	sync_to_physics = true
	_home = transform
	_net = NetEntity.of(self)
	_ride.running = autostart and mode != Mode.ON_CALL
	_was = _ride.copy()


func _exit_tree() -> void:
	if _counted:
		_counted = false
		online_count -= 1


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _is_online():
		_tick += 1
		placed_tick = _tick
		transform = transform_at(_tick)
	var ride := ride_at(_now())
	if ride.arrivals > _seen_arrivals:
		if ride.at_end:
			reached_end.emit()
		else:
			reached_start.emit()
	_seen_arrivals = ride.arrivals


## Where the ride is at physics tick `tick`.
func ride_at(tick: int) -> Ride:
	if tick < _start:
		return _advance(_was, (tick - _was_start) / float(Engine.physics_ticks_per_second))
	return _advance(_ride, (tick - _start) / float(Engine.physics_ticks_per_second))


## The platform's transform (in its parent) at physics tick `tick`.
func transform_at(tick: int) -> Transform3D:
	var length := travel.length()
	if length <= 0.0:
		return _home
	return _home.translated_local(travel * (ride_at(tick).distance / length))


## Where the platform is in the world at physics tick `tick`.
func position_at(tick: int) -> Vector3:
	var parent := get_parent() as Node3D
	var local := transform_at(tick).origin
	return parent.global_transform * local if parent != null else local


## Whether a body whose feet are at `point` (world) stands on the slab as it is at `tick`: over its
## top, within `margin` metres of its edges, and its feet within `margin` of the top.
func carries(point: Vector3, tick: int, margin := 0.3) -> bool:
	var parent := get_parent() as Node3D
	var place := transform_at(tick)
	if parent != null:
		place = parent.global_transform * place
	var local := place.affine_inverse() * point
	var half := size / 2.0
	return (
		absf(local.x) <= half.x + margin
		and absf(local.z) <= half.z + margin
		and absf(local.y - half.y) <= margin
	)


## Fraction of the way to the far end, 0 to 1.
func progress() -> float:
	var length := travel.length()
	return ride_at(_now()).distance / length if length > 0.0 else 0.0


## Moves in the current mode from where it is.
func start() -> void:
	_change(func(ride: Ride) -> void: ride.running = true)


## Holds where it is.
func stop() -> void:
	_change(func(ride: Ride) -> void: ride.running = false)


## Heads for the far end (in ON_CALL and ONCE it stops there).
func send_to_end() -> void:
	_change(_send.bind(1.0))


## Heads for the start (in ON_CALL and ONCE it stops there).
func send_to_start() -> void:
	_change(_send.bind(-1.0))


# --- Online (NetEntity) ---


## Who runs the platform (`NetWorld` sets it). Online the slab is a static body that the world puts
## at each tick's place (`net_place`), so a body stepped in the same frame stands on it at once,
## and a rider is carried by `PlatformRider` from the same function (a kinematic body moves only in
## the next physics step and gives its riders the engine's velocity: third-person/net-world.md).
func net_set_role(role: NetEntity.Role) -> void:
	if role == NetEntity.Role.OFFLINE or _counted:
		return
	_counted = true
	online_count += 1
	sync_to_physics = false
	PhysicsServer3D.body_set_mode(get_rid(), PhysicsServer3D.BODY_MODE_STATIC)


## Whether an online world drives the platform (its riders are carried by `PlatformRider`).
func is_online() -> bool:
	return _is_online()


## Puts the slab where it is at `tick`, at once for the physics queries of this frame.
func net_place(tick: int) -> void:
	placed_tick = tick
	var place := transform_at(tick)
	if place == transform:
		return
	transform = place
	force_update_transform()


## The state as at server tick `at_tick`: u8 flags (1 running, 2 heading for the far end), u16 the
## distance (of 65535 of the travel), u16 the ticks it still waits at an end, u8 the ticks from
## `at_tick` to the ride's start. 6 bytes.
func net_write(at_tick: int) -> PackedByteArray:
	var ride := _ride if _start > at_tick else ride_at(at_tick)
	var length := travel.length()
	var out := PackedByteArray([0, 0, 0, 0, 0, clampi(_start - at_tick, 0, 255)])
	out[0] = (1 if ride.running else 0) | (2 if ride.direction > 0.0 else 0)
	var share := clampf(ride.distance / length, 0.0, 1.0) if length > 0.0 else 0.0
	out.encode_u16(1, roundi(share * 65535.0))
	out.encode_u16(3, clampi(roundi(ride.wait * Engine.physics_ticks_per_second), 0, 65535))
	return out


## Reads a state written as at `at_tick` (false for one that is not a platform's).
func net_read(state: PackedByteArray, at_tick: int) -> bool:
	if state.size() != 6:
		return false
	var ride := Ride.new()
	ride.running = state[0] & 1 != 0
	ride.direction = 1.0 if state[0] & 2 else -1.0
	ride.distance = state.decode_u16(1) / 65535.0 * travel.length()
	ride.wait = state.decode_u16(3) / float(Engine.physics_ticks_per_second)
	_begin(at_tick + state[5], ride)
	return true


func _now() -> int:
	return _net.now() if _is_online() else _tick


func _is_online() -> bool:
	return _net != null and _net.is_online()


# A change of the ride (`edit` changes it) from the tick it starts at: this tick offline, the
# server's tick and its lead online, where it is rounded as the wire carries it. On a client only
# the server's records change the ride.
func _change(edit: Callable) -> void:
	if _net != null and _net.role == NetEntity.Role.CLIENT:
		return
	var begin_at := _net.start_tick() if _is_online() else _tick
	var ride := ride_at(begin_at)
	edit.call(ride)
	if _is_online():
		var state := _quantized(ride)
		ride.distance = state.distance
		ride.wait = state.wait
	_begin(begin_at, ride)
	if _net != null:
		_net.report()


func _send(ride: Ride, direction: float) -> void:
	ride.direction = direction
	ride.wait = 0.0
	ride.running = true


func _begin(begin_at: int, ride: Ride) -> void:
	_was_start = _start
	_was = _ride
	_start = begin_at
	_ride = ride.copy()
	_ride.arrivals = 0
	_seen_arrivals = 0


func _quantized(ride: Ride) -> Ride:
	var out := ride.copy()
	var length := travel.length()
	if length > 0.0:
		out.distance = roundi(clampf(ride.distance / length, 0.0, 1.0) * 65535.0) / 65535.0 * length
	var rate := Engine.physics_ticks_per_second
	out.wait = clampi(roundi(ride.wait * rate), 0, 65535) / float(rate)
	return out


# Where the ride is now, before a tuning change (null before the platform runs).
func _ride_now() -> Ride:
	if not is_node_ready() or Engine.is_editor_hint():
		return null
	return ride_at(_now())


# After a tuning change, the ride goes on from where it was (`ride`) with the new numbers.
func _rebase(ride: Ride) -> void:
	if ride == null:
		return
	var length := travel.length()
	ride.distance = clampf(ride.distance, 0.0, length)
	_begin(_now(), ride)


# The ride `seconds` after `from`: the wait left, the leg to the end it heads for, then whole
# legs of a ping-pong (a wait and a crossing each) at once, then what is left.
func _advance(from: Ride, seconds: float) -> Ride:
	var ride := from.copy()
	var length := travel.length()
	if not ride.running or seconds <= 0.0 or length <= 0.0:
		return ride
	if seconds <= ride.wait:
		ride.wait -= seconds
		return ride
	seconds -= ride.wait
	ride.wait = 0.0
	var leg := ((length - ride.distance) if ride.direction > 0.0 else ride.distance) / speed
	if seconds < leg:
		ride.distance = clampf(ride.distance + ride.direction * speed * seconds, 0.0, length)
		return ride
	seconds -= leg
	_arrive(ride, length)
	if not ride.running:
		return ride
	var half := wait_time + length / speed
	var turns := floori(seconds / half)
	if turns > 0:
		seconds -= turns * half
		ride.arrivals += turns
		if turns % 2 == 1:
			ride.direction = -ride.direction
			ride.distance = length - ride.distance
			ride.at_end = not ride.at_end
	if seconds <= ride.wait:
		ride.wait -= seconds
		return ride
	seconds -= ride.wait
	ride.wait = 0.0
	ride.distance = clampf(ride.distance + ride.direction * speed * seconds, 0.0, length)
	return ride


# The ride reaches the end it was heading for: in PING_PONG it turns and waits, otherwise it stops.
func _arrive(ride: Ride, length: float) -> void:
	ride.at_end = ride.direction > 0.0
	ride.distance = length if ride.at_end else 0.0
	ride.arrivals += 1
	if mode == Mode.PING_PONG:
		ride.direction = -ride.direction
		ride.wait = wait_time
	else:
		ride.running = false


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

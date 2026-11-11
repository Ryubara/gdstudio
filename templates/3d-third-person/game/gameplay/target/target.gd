@tool
class_name Target
extends StaticBody3D
## A shooting-range target: a round board on a post that a shot knocks over. Its `Health` child
## takes the hits (a `Projectile` finds it with `Health.of()`): when the health reaches zero the
## board tilts back and changes colour, and it stands up again, its health full, after
## `reset_time`. The `Health`'s `max_value` sets how much it takes (1: any shot). It works on its
## own and says what happened through signals; with no `Health` it takes no shot and says so in a
## configuration warning.
##
## Its parts are nodes of `target.tscn` (`Post`, `Pivot` holding `Board`, and `Shape`, the board's
## collision, which a body takes only from its own children and so stays upright), so open the
## scene to restyle it; `size`, `tint` and `hit_tint` follow the inspector live. The board faces
## +Z: turn the target to face the shooter.
##
## Online (its `NetEntity` child, kind `target`) the server's target is the one that falls and
## stands: each change is an `entity` event (1 byte: down), which a client plays with the hit it
## goes with (`NetEntity.with_puppets`), and a late joiner reads in its WELCOME. A client's board
## falls when the server's health reaches zero (a HIT) or its record says so, and stands only when
## the record says so: it keeps no clock of its own (third-person/net-world.md#targets).

## A shot hit the board (standing or down).
signal shot(hit: HitRecord)
## The board went down (its `Health` reached zero).
signal knocked_down
## The board stood up again.
signal stood_up

## The group every target joins, so a network names one by its place among them (`NetHits`).
const GROUP := &"target"

@export_group("Look")
## The board's diameter.
@export_range(0.2, 3.0, 0.05, "suffix:m") var size := 1.0:
	set(value):
		size = value
		_update_look()
## The board's colour while it stands.
@export var tint := Color(0.9, 0.25, 0.2):
	set(value):
		tint = value
		_update_look()
## The board's colour while it is down.
@export var hit_tint := Color(0.95, 0.95, 0.95):
	set(value):
		hit_tint = value
		_update_look()

@export_group("Reaction")
## How far the board tips back when it is down.
@export_range(0.0, 90.0, 1.0, "suffix:deg") var drop_angle := 80.0:
	set(value):
		drop_angle = value
		_wake()
## Seconds the board takes to tip back or to stand up.
@export_range(0.02, 2.0, 0.01, "suffix:s") var drop_time := 0.18
## It stands up again after this long. Zero leaves it down.
@export_range(0.0, 60.0, 0.1, "or_greater", "suffix:s") var reset_time := 3.0:
	set(value):
		reset_time = value
		_wake()

var _down := false
var _tilt := 0.0
var _down_for := 0.0
# The target's place in an online game (its `NetEntity` child), or null.
var _net: NetEntity


func _ready() -> void:
	_update_look()
	# A board that stands still costs nothing: it is processed only while it tips or waits to stand.
	set_process(false)
	if Engine.is_editor_hint():
		return
	add_to_group(GROUP)
	_net = NetEntity.of(self)
	if _net != null:
		_net.serve(net_write, net_read, func(_role: NetEntity.Role) -> void: pass)
		_net.with_puppets = true
	var health := Health.of(self)
	if health != null:
		health.hit_taken.connect(_on_hit_taken)
		health.died.connect(_on_died)


func _process(delta: float) -> void:
	if _waits_to_stand():
		_down_for += delta
		if _down_for >= reset_time:
			_stand()
	var goal := drop_angle if _down else 0.0
	_tilt = move_toward(_tilt, goal, drop_angle / maxf(drop_time, 0.001) * delta)
	var pivot := _pivot()
	if pivot != null:
		pivot.rotation.x = -deg_to_rad(_tilt)
	if _tilt == goal and not _waits_to_stand():
		set_process(false)


func _on_hit_taken(hit: HitRecord) -> void:
	_wake()
	shot.emit(hit)
	if _down:
		_down_for = 0.0


func _on_died(_hit: HitRecord) -> void:
	if _down:
		return
	_down = true
	_down_for = 0.0
	_wake()
	_update_look()
	knocked_down.emit()
	_report()


## True while the board is down.
func is_down() -> bool:
	return _down


## How far the board has tipped back right now, in degrees.
func tilt() -> float:
	return _tilt


func _stand() -> void:
	_down = false
	_down_for = 0.0
	var health := Health.of(self)
	if health != null:
		health.reset()
	_wake()
	_update_look()
	stood_up.emit()
	_report()


# --- Online (NetEntity) ---


## The state: u8 flags (1 down). 1 byte; the board's tilt is each screen's own.
func net_write(_at_tick: int) -> PackedByteArray:
	return PackedByteArray([1 if _down else 0])


## On a client: the server's target fell or stood (false for a state that is not a target's).
func net_read(state: PackedByteArray, _at_tick: int) -> bool:
	if state.size() != 1:
		return false
	var down := state[0] & 1 != 0
	if down and not _down:
		var health := Health.of(self)
		if health != null and not health.is_dead():
			health.kill()
		else:
			_on_died(null)
	elif not down and _down:
		_stand()
	return true


# The server's target says each change; a client's and an offline one say nothing.
func _report() -> void:
	if _net != null:
		_net.report()


# Counting down to stand up: offline and on the server, never on a client (the server says when).
func _waits_to_stand() -> bool:
	return _down and reset_time > 0.0 and not _is_remote()


func _is_remote() -> bool:
	return _net != null and _net.role == NetEntity.Role.CLIENT


# Processes the board again (it was shot, or a number it moves by changed while it ran).
func _wake() -> void:
	if is_node_ready() and not Engine.is_editor_hint():
		set_process(true)


func _pivot() -> Node3D:
	return get_node_or_null("%Pivot") as Node3D


# Puts the sizes and colours on the nodes' own resources (each target has its own copies: they
# are local to the scene).
func _update_look() -> void:
	var board := get_node_or_null("%Board") as MeshInstance3D
	var shape := get_node_or_null("%Shape") as CollisionShape3D
	var pivot := _pivot()
	if board == null or shape == null or pivot == null:
		return
	var disc := board.mesh as CylinderMesh
	disc.top_radius = size / 2.0
	disc.bottom_radius = size / 2.0
	(shape.shape as CylinderShape3D).radius = size / 2.0
	(board.material_override as StandardMaterial3D).albedo_color = hit_tint if _down else tint
	pivot.position.y = size / 2.0 + 0.5
	shape.position.y = pivot.position.y
	var post := get_node_or_null("%Post") as MeshInstance3D
	if post != null:
		var stick := post.mesh as BoxMesh
		stick.size = Vector3(0.1, pivot.position.y, 0.1)
		post.position.y = pivot.position.y / 2.0


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	for part_name in ["Pivot", "Board", "Shape", "Post"]:
		if get_node_or_null("%" + part_name) == null:
			warnings.append("The scene needs a node named `%s`." % part_name)
	if Health.of(self) == null:
		warnings.append("No `Health` child: shots pass without knocking the board down.")
	return warnings

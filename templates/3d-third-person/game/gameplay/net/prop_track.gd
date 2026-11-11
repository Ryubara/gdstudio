class_name PropTrack
extends RefCounted
## A client's recent records of one pushed prop (`PropState`), by server tick, and where the prop
## is at any tick: between two records it is blended, past the newest it goes on at the speed of the
## last two records for at most `AHEAD_TICKS` (a client puts the prop at the tick of the command it
## predicts, which is a round trip ahead of the newest record, so a body pushing it meets it about
## where the server's body does). A record that is asleep or jumped is held, never guessed past.
## Plain code with no node (third-person/net-world.md#props).

## Records kept (a second of TICKs at the snapshot rate).
const KEEP := NetLimits.SNAPSHOT_RATE
## Ticks past the newest record the prop is moved on at its last speed, at most (250 ms).
const AHEAD_TICKS := NetLimits.TICK_RATE / 4
## Two records further apart than this (ticks) give no speed: the prop slept between them.
const SPEED_GAP_TICKS := 3 * NetLimits.TICK_RATE / NetLimits.SNAPSHOT_RATE

## Samples asked for past the newest record of an awake prop (moved on at its speed).
var ahead := 0

var _ticks := PackedInt64Array()
var _states: Array[PropState] = []


## Adds the record of server tick `at_tick`; one older than the newest is ignored, one of the same
## tick replaces it (a WELCOME row and the TICK of its tick), and a jumped one forgets the rest.
func push(at_tick: int, state: PropState) -> void:
	if not _ticks.is_empty() and at_tick < _ticks[-1]:
		return
	if state.jumped:
		_ticks.clear()
		_states.clear()
	if not _ticks.is_empty() and at_tick == _ticks[-1]:
		_states[-1] = state
		return
	_ticks.append(at_tick)
	_states.append(state)
	if _ticks.size() > KEEP:
		_ticks.remove_at(0)
		_states.remove_at(0)


func is_empty() -> bool:
	return _ticks.is_empty()


func size() -> int:
	return _ticks.size()


## The newest record's tick, or -1.
func newest_tick() -> int:
	return _ticks[-1] if not _ticks.is_empty() else -1


func newest() -> PropState:
	return _states[-1] if not _states.is_empty() else null


## The prop's transform at server tick `at_tick`, or `fallback` when no record is held.
func sample(at_tick: int, fallback: Transform3D) -> Transform3D:
	if _ticks.is_empty():
		return fallback
	if at_tick <= _ticks[0]:
		return _transform(_states[0].position, _states[0].rotation)
	var last := _ticks.size() - 1
	if at_tick >= _ticks[last]:
		return _ahead(at_tick)
	var index := _ticks.bsearch(at_tick, false) - 1
	var a := _states[index]
	var b := _states[index + 1]
	var weight := float(at_tick - _ticks[index]) / float(_ticks[index + 1] - _ticks[index])
	return _transform(a.position.lerp(b.position, weight), a.rotation.slerp(b.rotation, weight))


# Past the newest record: moved on at the speed of the last two, when the prop is awake and they
# are close enough in time to give one.
func _ahead(at_tick: int) -> Transform3D:
	var last := _ticks.size() - 1
	var newest_state := _states[last]
	var at := newest_state.position
	var turned := newest_state.rotation
	if at_tick == _ticks[last] or newest_state.asleep or last == 0:
		return _transform(at, turned)
	var gap := _ticks[last] - _ticks[last - 1]
	if gap <= 0 or gap > SPEED_GAP_TICKS:
		return _transform(at, turned)
	ahead += 1
	var before := _states[last - 1]
	var share := float(mini(at_tick - _ticks[last], AHEAD_TICKS)) / float(gap)
	at += (newest_state.position - before.position) * share
	var turn := newest_state.rotation * before.rotation.inverse()
	if turn.w < 0.0:
		turn = -turn
	# The axis from the vector part itself: a turn of a few thousandths of a degree can leave it
	# zero while `w` is under 1, and `Quaternion(axis, angle)` refuses an axis that is not a unit.
	var axis := Vector3(turn.x, turn.y, turn.z)
	if axis.length_squared() > 1e-10:
		var angle := 2.0 * atan2(axis.length(), turn.w)
		turned = Quaternion(axis.normalized(), angle * share) * turned
	return _transform(at, turned.normalized())


static func _transform(at: Vector3, turned: Quaternion) -> Transform3D:
	return Transform3D(Basis(turned), at)

class_name InterpolationTrack
extends RefCounted
## One remote player's recent snapshots, by server time, and where it was at any moment between
## them: `RemotePlayers` draws each puppet a little in the past (`RemotePlayers.delay`), between
## the two snapshots around that moment, so a puppet moves smoothly at the snapshot rate whatever
## the jitter. Plain code with no node.
##
## A moment past the newest snapshot holds the newest (no guess ahead) and counts as `starved`;
## two snapshots further apart than `WARP_DISTANCE` are a warp (a respawn, a teleport): the puppet
## jumps to the later one rather than sliding through the map.

## Seconds of snapshots kept.
const KEEP := 1.0
## Metres between two snapshots past which the move is a warp.
const WARP_DISTANCE := 6.0

## Samples asked for past the newest snapshot (the buffer ran dry).
var starved := 0
## Samples asked for before the oldest snapshot kept.
var early := 0

var _times := PackedFloat64Array()
var _entries: Array[PlayerEntry] = []


## Adds the snapshot of server time `at` (seconds); one no newer than the newest is ignored.
func push(at: float, entry: PlayerEntry) -> void:
	if not _times.is_empty() and at <= _times[-1]:
		return
	_times.append(at)
	_entries.append(entry)
	while _times.size() > 2 and _times[-1] - _times[1] > KEEP:
		_times.remove_at(0)
		_entries.remove_at(0)


func is_empty() -> bool:
	return _times.is_empty()


## The server time of the newest snapshot, or -1.
func newest_time() -> float:
	return _times[-1] if not _times.is_empty() else -1.0


func newest() -> PlayerEntry:
	return _entries[-1] if not _entries.is_empty() else null


## Snapshots held.
func size() -> int:
	return _times.size()


## The player at server time `at`, written into `into` (position and facing blended, the state and
## the flags from the snapshot before, `halt` from the one after), and its velocity (m/s) between
## the two snapshots around it.
## Answers the velocity; `into` is left alone when the track is empty.
func sample(at: float, into: PlayerEntry) -> Vector3:
	if _times.is_empty():
		return Vector3.ZERO
	if at >= _times[-1]:
		if at > _times[-1]:
			starved += 1
		_copy(_entries[-1], into)
		return _velocity(_times.size() - 2)
	if at <= _times[0]:
		early += 1
		_copy(_entries[0], into)
		return Vector3.ZERO
	var index := _times.bsearch(at, false) - 1
	var a := _entries[index]
	var b := _entries[index + 1]
	_copy(a, into)
	# The goal is the one the drawn move heads for: a stop begins as the move toward a halted
	# snapshot does, a start as the move away from one does (gdstudio #1420).
	into.halt = b.halt
	into.goal_step = b.goal_step
	if a.position.distance_to(b.position) > WARP_DISTANCE:
		return Vector3.ZERO
	var share := (at - _times[index]) / (_times[index + 1] - _times[index])
	into.position = a.position.lerp(b.position, share)
	into.yaw = lerp_angle(a.yaw, b.yaw, share)
	into.pitch = lerpf(a.pitch, b.pitch, share)
	into.aim_yaw = lerp_angle(a.aim_yaw, b.aim_yaw, share)
	into.peek = lerpf(a.peek, b.peek, share)
	return _velocity(index)


## The velocity (m/s) the snapshots head for: the one between the two newest, ahead of the moment
## a puppet is drawn at. A puppet's animation reads it as the goal a stepped body's command gives
## (`CharacterGoal.motion`, with the entry's `halt` for a stop), so a start begins as the body
## sets off (gdstudio #1420).
func heading() -> Vector3:
	return _velocity(_times.size() - 2)


func clear() -> void:
	_times.clear()
	_entries.clear()


# The velocity from snapshot `index` to the next, zero for a warp or when there is no next.
func _velocity(index: int) -> Vector3:
	if index < 0 or index + 1 >= _times.size():
		return Vector3.ZERO
	var moved := _entries[index + 1].position - _entries[index].position
	if moved.length() > WARP_DISTANCE:
		return Vector3.ZERO
	return moved / (_times[index + 1] - _times[index])


static func _copy(from: PlayerEntry, into: PlayerEntry) -> void:
	into.slot = from.slot
	into.position = from.position
	into.yaw = from.yaw
	into.state = from.state
	into.crouch = from.crouch
	into.aim = from.aim
	into.sprint = from.sprint
	into.air = from.air
	into.rising = from.rising
	into.dead = from.dead
	into.halt = from.halt
	into.goal_step = from.goal_step
	into.pitch = from.pitch
	into.aim_yaw = from.aim_yaw
	into.peek = from.peek

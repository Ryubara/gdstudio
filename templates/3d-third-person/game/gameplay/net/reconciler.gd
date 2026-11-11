class_name Reconciler
extends RefCounted
## Takes a predicting client's own body toward where the server says it is, without replaying a
## command (a step pushes props and fires: `CharacterState`). Plain code with no node, so a test
## closes the loop in one dimension.
##
## The client records where each numbered command left its body (`record`). A TICK says which
## command the server applied last (`ack`) and where the server's body stands after it (`answer`):
## the error is the server's point less the recorded one. The body then moves a quarter of what is
## left of the error each frame (`take`), and every remembered point of an unanswered command is
## shifted by the same amount, so the next answer does not count a correction already made (the
## Deadnight #483 divergence). An error past `SNAP_DISTANCE` is taken in one frame; one past
## `LOST_DISTANCE` is counted as `lost` (the body is snapped as well: the client and the server
## disagree about the world, `multiplayer.md#the-two-worlds-must-hold-the-same-solid-things`);
## after several stalls of the client's thread with no answer between them (`resync`) the answer
## may be that many walk-ons of the server's body long, so it is lost past that many times. An
## error inside `DEAD_ZONE` is the wire's rounding (a TICK carries centimetres) and is left alone.
## A part the world will not let the body take (it put the body inside a ledge it stands on:
## `NetClient`) is followed by the rest at once (`take_rest`): taken in parts, each would be pushed
## back out and the two bodies would never meet (gdstudio #1119).

## The share of the error left that one frame takes.
const SHARE := 0.25
## Metres off past which the body is put on the server's point at once.
const SNAP_DISTANCE := 2.5
## Metres off past which the client counts the body as lost.
const LOST_DISTANCE := 6.0
## Metres off that are the wire's rounding: a TICK's centimetres are half a centimetre off on
## each axis at most (0.87 cm in all), so less than this is never corrected.
const DEAD_ZONE := 0.01
## Commands remembered: four seconds at the tick rate, more than any round trip that plays.
const KEEP := NetLimits.TICK_RATE * NetLimits.STALL_SECONDS

## Answers with an error above `DEAD_ZONE`, snaps, and answers past `LOST_DISTANCE`.
var corrections := 0
var snaps := 0
var lost := 0
## The error of each snap taken for its size (past `SNAP_DISTANCE`, not a resync's), metres, in
## order: a report tells them from the join's and a stall's (`tools/net/bad_network.py`).
var size_snaps := PackedFloat32Array()
## Corrections taken whole because a part was pushed back by the world (`take_rest`).
var stuck_snaps := 0
## The largest error an answer measured, metres.
var worst_error := 0.0
## The error of the last answer, metres.
var last_error := 0.0
## Metres the body was moved by corrections in all, the rests `take_rest` handed out included
## (snaps for size and after a stall not counted).
var corrected := 0.0
## The next answer is taken whole, whatever its size (after a stall: `StallGuard`).
var snap_next := false
## Stalls of the client's own thread since an answer was last taken (`resync`). The server walks
## its body on through each silence (`NetServer.command_ticks` steps of the last command, 0.5 s),
## so stalls closer together than a round trip, with no answer between them, add their runs into
## the one answer taken whole after them (gdstudio #1070).
var stacked_stalls := 0
## The most stalls one answer came after.
var most_stacked := 0
## The largest error an answer measured for each stall it came after, metres: `worst_error` for
## an answer after one stall or none, a share of it after several. What one stall can cost.
var worst_stall_error := 0.0

var _seqs := PackedInt64Array()
var _points := PackedVector3Array()
var _pending := Vector3.ZERO
# A snap the next `take` hands out whole (the remembered points were shifted by it already).
var _snapped := Vector3.ZERO


## Remembers where command `seq` left the body.
func record(seq: int, point: Vector3) -> void:
	_seqs.append(seq)
	_points.append(point)
	if _seqs.size() > KEEP:
		_seqs = _seqs.slice(_seqs.size() - KEEP)
		_points = _points.slice(_points.size() - KEEP)


## The server applied command `ack` last and its body stands at `server_point`: sets the
## correction the next frames take. False when `ack` is not remembered (already answered, or
## older than `KEEP`): nothing changes.
func answer(ack: int, server_point: Vector3) -> bool:
	var index := _seqs.find(ack)
	if index < 0:
		return false
	var error := server_point - _points[index]
	_seqs = _seqs.slice(index + 1)
	_points = _points.slice(index + 1)
	last_error = error.length()
	worst_error = maxf(worst_error, last_error)
	# An answer taken whole after stalls may hold one run of the server's body for each.
	var runs := maxi(stacked_stalls, 1) if snap_next else 1
	most_stacked = maxi(most_stacked, stacked_stalls)
	stacked_stalls = 0
	worst_stall_error = maxf(worst_stall_error, last_error / runs)
	if last_error <= DEAD_ZONE:
		snap_next = false
		_pending = Vector3.ZERO
		return true
	if snap_next or last_error > SNAP_DISTANCE:
		if last_error > LOST_DISTANCE * runs:
			lost += 1
		snaps += 1
		if not snap_next:
			size_snaps.append(last_error)
		snap_next = false
		_pending = Vector3.ZERO
		_snapped += error
		_shift(error)
		return true
	corrections += 1
	_pending = error
	return true


## What the body moves this frame (add it to the body's position): a snap whole, else a quarter
## of the error left. The remembered points move with it.
func take() -> Vector3:
	if _snapped != Vector3.ZERO:
		var whole := _snapped
		_snapped = Vector3.ZERO
		return whole
	if _pending == Vector3.ZERO:
		return Vector3.ZERO
	var part := _pending * SHARE
	if _pending.length() * (1.0 - SHARE) <= DEAD_ZONE * 0.1:
		part = _pending
	_pending -= part
	corrected += part.length()
	_shift(part)
	return part


## The correction not yet taken, whole (add it to the body's position): the part `take` handed out
## put the body inside the world, so parts would be pushed back out each frame and never arrive
## (a body on a ledge whose server body stands below it, gdstudio #1119). The remembered points
## move with it, as with a part.
func take_rest() -> Vector3:
	var rest := _pending
	if rest == Vector3.ZERO:
		return rest
	_pending = Vector3.ZERO
	stuck_snaps += 1
	corrected += rest.length()
	_shift(rest)
	return rest


## The correction not yet taken, metres.
func pending() -> Vector3:
	return _pending


## Commands recorded and not yet answered.
func unanswered() -> int:
	return _seqs.size()


## Forgets every recorded point and the correction under way (after the body was moved by hand,
## a teleport or a stall).
func reset() -> void:
	_seqs.clear()
	_points.clear()
	_pending = Vector3.ZERO
	_snapped = Vector3.ZERO


## The client's own thread stalled (`StallGuard`): forgets every point, takes the next answer
## whole and counts the stall in `stacked_stalls`.
func resync() -> void:
	reset()
	snap_next = true
	stacked_stalls += 1


func _shift(by: Vector3) -> void:
	for index in _points.size():
		_points[index] += by

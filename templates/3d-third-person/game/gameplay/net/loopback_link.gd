class_name LoopbackLink
extends NetLink
## Two ends of a link in one process, for tests that need no socket and for a game whose server runs
## inside it: `LoopbackLink.pair()` makes them. A packet sent in tick t is read by the other end in
## tick t+1, whichever end is polled first, as long as both are polled once per tick. Packets are
## copied, so neither end can change what the other reads.
##
## `close()` reaches the other end as a clean goodbye (1000) on its next tick; `drop()` as a network
## that went (no close frame), for tests of what a dropped player leaves. Each end holds the other
## weakly (two ends that held each other would never be freed), so keep both ends; an end whose
## other was freed reads it as a network that went.

var _other_ref: WeakRef
var _tick := 0
var _inbox: Array[Dictionary] = []
var _open := true
var _announced := false
var _close_code := NetLink.CLOSE_NONE
## The close the other end sent, and the tick it was sent in (read like a packet: a tick later).
var _close_from_other := 0
var _close_tick := -1
var _closed_emitted := false


## Two ends joined to each other: what one sends, the other reads a tick later.
static func pair() -> Array[LoopbackLink]:
	var a := LoopbackLink.new()
	var b := LoopbackLink.new()
	a._other_ref = weakref(b)
	b._other_ref = weakref(a)
	return [a, b]


func send(data: PackedByteArray) -> bool:
	if not is_open():
		return false
	_other()._inbox.append({"tick": _tick, "data": data.duplicate()})
	bytes_out += data.size()
	packets_out += 1
	return true


func poll() -> void:
	_tick += 1
	if _open and _other() == null:
		_open = false
		_close_code = NetLink.CLOSE_NONE
	if _open and not _announced:
		_announced = true
		connected.emit()
	while not _inbox.is_empty() and _inbox[0]["tick"] < _tick:
		var data: PackedByteArray = _inbox.pop_front()["data"]
		bytes_in += data.size()
		packets_in += 1
		packet_received.emit(data)
	if _close_tick >= 0 and _close_tick < _tick and _open:
		_open = false
		_close_code = _close_from_other
	if not _open and not _closed_emitted and _inbox.is_empty():
		_closed_emitted = true
		closed.emit()


func is_open() -> bool:
	return _open and _other() != null


func close() -> void:
	_end(NetLink.CLOSE_NORMAL)


## Ends the link as if the network had gone: the other end reads no close frame.
func drop() -> void:
	_end(NetLink.CLOSE_NONE)


func close_code() -> int:
	return _close_code


func _end(code: int) -> void:
	if not _open:
		return
	_open = false
	_close_code = code
	var other := _other()
	if other != null and other._close_tick < 0:
		other._close_from_other = code
		other._close_tick = _tick


func _other() -> LoopbackLink:
	return _other_ref.get_ref() as LoopbackLink if _other_ref != null else null

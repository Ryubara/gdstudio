class_name LinkConditioner
extends NetLink
## A bad network around any link, for tests, bots and a `--bad-network` option: every packet, in
## each direction, is held back `delay` seconds (plus a random `jitter` either way) and let through
## in the order it came, as TCP delivers: a packet never overtakes the one before it. A WebSocket
## cannot lose a packet, so what loss is on UDP is a **stall** here (a retransmission): with
## `stall_chance` a packet costs `stall_seconds` more, and everything behind it waits too.
## `stall_for(seconds)` holds both directions from now, as a network that hangs for a moment.
##
## Time is the caller's: `clock` returns seconds (a test gives it the physics frame count over the
## tick rate, so a slow machine meets the same network a quick one does, frame for frame); empty
## means the real clock. Randomness is seeded, so a run repeats. A packet is due within
## `DUE_SLACK` of its time: on a tick clock a hold of whole ticks (0.15 s at 60) passes on its own
## tick at every frame count, not one tick later where the sum's rounding lands it a hair past.

## Seconds a packet may pass before its time: far under a tick, far over the rounding of seconds
## counted in ticks (a frame count over the tick rate) a game runs for days.
const DUE_SLACK := 0.000001

## Seconds each packet is held, each way.
var delay := 0.0
## Seconds either way added at random to each packet's delay (never reordering).
var jitter := 0.0
## The chance that a packet needs a retransmission, and what that costs in seconds.
var stall_chance := 0.0
var stall_seconds := 0.2
## Seconds from game start (empty: the real clock).
var clock := Callable()

## Packets let through and packets that stalled, both directions, for the numbers of a run.
var passed := 0
var stalled := 0

var _inner: NetLink
var _rng := RandomNumberGenerator.new()
var _incoming := _Line.new()
var _outgoing := _Line.new()
var _inner_closed := false
var _closed_emitted := false


## Wraps `wrapped`, which this link now polls. `seed_value` seeds the jitter and the stalls.
func _init(wrapped: NetLink, delay_seconds := 0.0, jitter_seconds := 0.0, seed_value := 1) -> void:
	_inner = wrapped
	delay = delay_seconds
	jitter = jitter_seconds
	_rng.seed = seed_value
	# Method callables, not lambdas: a lambda that names `self` would keep this link alive from the
	# inner one's signals.
	_inner.packet_received.connect(_on_inner_packet)
	_inner.connected.connect(_on_inner_connected)
	_inner.closed.connect(_on_inner_closed)


## The link this one wraps.
func inner() -> NetLink:
	return _inner


func send(data: PackedByteArray) -> bool:
	if not _inner.is_open():
		return false
	_hold(_outgoing, data)
	return true


func poll() -> void:
	_inner.poll()
	var now := _now()
	for data in _incoming.due(now):
		bytes_in += data.size()
		packets_in += 1
		passed += 1
		packet_received.emit(data)
	for data in _outgoing.due(now):
		passed += 1
		if _inner.send(data):
			bytes_out += data.size()
			packets_out += 1
	# What arrived before the close is still read, at its time; then the link is finished.
	if _inner_closed and _incoming.waiting() == 0 and not _closed_emitted:
		_closed_emitted = true
		closed.emit()


func is_open() -> bool:
	return _inner.is_open()


func close() -> void:
	_inner.close()


func close_code() -> int:
	return _inner.close_code()


## Holds every packet, both ways, that is not through by `seconds` from now until then (and keeps
## the ones behind them in order).
func stall_for(seconds: float) -> void:
	var until := _now() + seconds
	_incoming.hold_until(until)
	_outgoing.hold_until(until)


## Packets still held, both directions.
func waiting() -> int:
	return _incoming.waiting() + _outgoing.waiting()


func _on_inner_packet(data: PackedByteArray) -> void:
	_hold(_incoming, data)


func _on_inner_connected() -> void:
	connected.emit()


func _on_inner_closed() -> void:
	_inner_closed = true


func _hold(line: _Line, data: PackedByteArray) -> void:
	var at := _now() + delay
	if jitter > 0.0:
		at += _rng.randf_range(-jitter, jitter)
	if stall_chance > 0.0 and _rng.randf() < stall_chance:
		at += stall_seconds
		stalled += 1
	line.push(data, at)


func _now() -> float:
	if clock.is_valid():
		return float(clock.call())
	return Time.get_ticks_usec() / 1000000.0


## One direction: packets in the order they came, each with the time it may pass.
class _Line:
	extends RefCounted
	var _queue: Array[Dictionary] = []
	var _last_at := -INF
	var _held_until := -INF

	func push(data: PackedByteArray, at: float) -> void:
		# In order: nothing passes before what came ahead of it, or before a stall ends.
		var when := maxf(maxf(at, _last_at), _held_until)
		_last_at = when
		_queue.append({"at": when, "data": data})

	func hold_until(until: float) -> void:
		_held_until = maxf(_held_until, until)
		for entry in _queue:
			entry["at"] = maxf(entry["at"], until)
		_last_at = maxf(_last_at, until)

	func due(now: float) -> Array[PackedByteArray]:
		var out: Array[PackedByteArray] = []
		while not _queue.is_empty() and _queue[0]["at"] <= now + DUE_SLACK:
			out.append(_queue.pop_front()["data"])
		return out

	func waiting() -> int:
		return _queue.size()

class_name StallGuard
extends RefCounted
## Tells a client's physics ticks that follow a stall of its own thread (a frozen tab, a slow
## load) from ordinary ones. After a stall the engine runs several physics ticks in one frame to
## catch up; a client that sent a command for each would send a burst the server must queue, and
## its predicted body would run ahead of the server's. So a tick more than `STALL_SECONDS` after
## the last one on the clock starts a resync (`resyncs`, and `check` answers `RESYNC`), and for
## `CATCH_UP_SECONDS` after it every tick that is not the first of its process frame is skipped
## (`SKIP`): no command, no step. Outside that window two ticks in one frame (a game drawn at 30
## frames a second) both step. Deadnight #483.

enum Verdict { STEP, RESYNC, SKIP }

## Seconds between two ticks that count as a stall.
const STALL_SECONDS := 0.25
## Seconds after a stall in which the engine's catch-up ticks are skipped.
const CATCH_UP_SECONDS := 0.5

## Stalls seen.
var resyncs := 0
## Seconds between the last stall's tick and the one before it.
var last_gap := 0.0
## Ticks skipped after a stall.
var skipped := 0
## Seconds for the clock; empty is the machine's.
var clock := Callable()

var _last := -1.0
var _last_frame := -1
var _skip_until := -1.0


## The verdict for this physics tick; `frame` is the process frame it runs in.
func check(frame: int) -> Verdict:
	var now := _now()
	var gap := now - _last if _last >= 0.0 else 0.0
	var same_frame := frame == _last_frame
	_last = now
	_last_frame = frame
	if gap > STALL_SECONDS:
		resyncs += 1
		last_gap = gap
		_skip_until = now + CATCH_UP_SECONDS
		return Verdict.RESYNC
	if same_frame and now < _skip_until:
		skipped += 1
		return Verdict.SKIP
	return Verdict.STEP


## Forgets the last tick (the next is never a stall).
func reset() -> void:
	_last = -1.0
	_last_frame = -1
	_skip_until = -1.0


func _now() -> float:
	if clock.is_valid():
		return float(clock.call())
	return Time.get_ticks_usec() / 1000000.0

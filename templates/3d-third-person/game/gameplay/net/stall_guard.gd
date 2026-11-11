class_name StallGuard
extends RefCounted
## Tells a client's physics ticks that follow a stall of its own thread (a frozen tab, a slow
## load) from ordinary ones. After a stall the engine runs several physics ticks in one frame to
## catch up; a client that sent a command for each would send a burst the server must queue, and
## its predicted body would run ahead of the server's. So a tick more than `STALL_SECONDS` after
## the last one on the clock starts a resync (`resyncs`, and `check` answers `RESYNC`), and the
## other ticks of that same frame are skipped (`SKIP`): no command, no step. Deadnight #483.

enum Verdict { STEP, RESYNC, SKIP }

## Seconds between two ticks that count as a stall.
const STALL_SECONDS := 0.25

## Stalls seen.
var resyncs := 0
## Ticks skipped after a stall.
var skipped := 0
## Seconds for the clock; empty is the machine's.
var clock := Callable()

var _last := -1.0
var _skip_frame := -1


## The verdict for this physics tick; `frame` is the process frame it runs in.
func check(frame: int) -> Verdict:
	var now := _now()
	var gap := now - _last if _last >= 0.0 else 0.0
	_last = now
	if frame == _skip_frame:
		skipped += 1
		return Verdict.SKIP
	if gap > STALL_SECONDS:
		resyncs += 1
		_skip_frame = frame
		return Verdict.RESYNC
	return Verdict.STEP


## Forgets the last tick (the next is never a stall).
func reset() -> void:
	_last = -1.0
	_skip_frame = -1


func _now() -> float:
	if clock.is_valid():
		return float(clock.call())
	return Time.get_ticks_usec() / 1000000.0

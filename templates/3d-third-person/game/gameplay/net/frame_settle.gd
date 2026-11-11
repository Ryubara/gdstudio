class_name FrameSettle
extends RefCounted
## Tells when a game's frames have settled: `frames` in a row each shorter than `longest` seconds,
## or `limit` seconds in all. `JoinWait` joins a server only then, after the level's warm-up: a
## software renderer still draws the warm-up's last frames a few hundred milliseconds each, and a
## seat taken during them met them as stalls (kit #1106, #1142).

## Frames in a row that must each be short.
var frames := 20
## Seconds a frame may take and count as short: the server's hold (four steps at 60 a second).
var longest := 4.0 / 60.0
## Seconds after which it counts as settled anyway.
var limit := 10.0

var _steady := 0
var _waited := 0.0


## Adds a frame of `seconds`; true once settled.
func push(seconds: float) -> bool:
	_waited += seconds
	_steady = _steady + 1 if seconds < longest else 0
	return is_settled()


## True once `frames` short frames came in a row or `limit` seconds went by.
func is_settled() -> bool:
	return _steady >= frames or _waited >= limit


## Seconds waited so far.
func waited() -> float:
	return _waited

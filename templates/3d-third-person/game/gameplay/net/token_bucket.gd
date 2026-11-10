class_name TokenBucket
extends RefCounted
## A budget that refills at a steady rate up to a burst: `take(now)` spends one token when there
## is one. Time is the caller's, in seconds (a server passes its tick clock, a test steps it by
## hand), so nothing here reads the engine's or the machine's clock.

var rate: float
var burst: float
var tokens: float
var _at := -1.0


func _init(per_second: float, most: float) -> void:
	rate = per_second
	burst = most
	tokens = most


## True (and one token spent) when there is a token at time `now`. A clock that goes back refills
## nothing.
func take(now: float) -> bool:
	if _at >= 0.0 and now > _at:
		tokens = minf(burst, tokens + (now - _at) * rate)
	_at = maxf(_at, now)
	if tokens < 1.0:
		return false
	tokens -= 1.0
	return true

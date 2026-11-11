class_name NetDrops
extends RefCounted
## Why packets were dropped, counted by reason: no decoder drops a packet silently. A server keeps
## one for each connection (`PeerLimits.drops`) and logs it when it hangs up; a test reads it.
## A decoder called without one counts into `NetDrops.unowned()`.

const EMPTY := &"empty"
const TOO_SHORT := &"too_short"
const TOO_LONG := &"too_long"
const UNKNOWN_TYPE := &"unknown_type"
const WRONG_SIZE := &"wrong_size"
const BAD_VERSION := &"bad_version"
const NOT_FINITE := &"not_finite"
const HELLO_TWICE := &"hello_twice"
const NAME_TOO_LONG := &"name_too_long"
const BAD_NAME := &"bad_name"
const COUNT_PAST_END := &"count_past_end"
const TOO_MANY := &"too_many"
const BAD_VALUE := &"bad_value"
const OVER_RATE := &"over_rate"
## A command whose number is not past the last one (`NetServer`: each is applied once, in order).
const OUT_OF_ORDER := &"out_of_order"
## A command before the HELLO was answered.
const NO_HELLO := &"no_hello"
## An AI delta whose baseline is not the snapshot this client holds (`AiSnapshot.apply`).
const NO_BASELINE := &"no_baseline"

static var _unowned: NetDrops

## Packets dropped for each reason.
var counts: Dictionary[StringName, int] = {}
## The reason of the last drop (empty before the first).
var last := &""


## The counter of decoders that were given none.
static func unowned() -> NetDrops:
	if _unowned == null:
		_unowned = NetDrops.new()
	return _unowned


## Counts one drop for `reason`; `drops` may be null (then `unowned()` counts it).
static func note(drops: NetDrops, reason: StringName) -> void:
	(drops if drops != null else unowned()).count(reason)


func count(reason: StringName) -> void:
	counts[reason] = counts.get(reason, 0) + 1
	last = reason


func of(reason: StringName) -> int:
	return counts.get(reason, 0)


func total() -> int:
	var sum := 0
	for reason: StringName in counts:
		sum += counts[reason]
	return sum


## One line for a log: `too_long=2 wrong_size=1`.
func summary() -> String:
	var parts := PackedStringArray()
	var reasons := counts.keys()
	reasons.sort()
	for reason: StringName in reasons:
		parts.append("%s=%d" % [reason, counts[reason]])
	return " ".join(parts)

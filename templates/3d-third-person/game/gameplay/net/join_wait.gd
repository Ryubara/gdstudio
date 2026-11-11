class_name JoinWait
extends RefCounted
## Waits until a level is ready to join a server, as a game joins behind its loading screen: the
## level's warm-up over (`EffectEmitter.warmed`: its tour of the reflection probes and first draws
## of every effect) and then its frames settled (`FrameSettle`: 20 in a row under the server's
## hold). A page that joined during the warm-up met its slow frames as stalls of the client, four
## to six in its first three seconds (kit #1106). `NetClient` joins after one (`join_after_warm_up`)
## and the bad-network probe (`NetPlayProbe`) does the same.

## Said when the wait moves on to another stage.
signal stage_changed(stage: Stage)
## Said once the level is ready to join.
signal finished

enum Stage { IDLE, WARMING, SETTLING, DONE }

## Where the wait is.
var stage := Stage.IDLE
## The frames that must settle after the warm-up (its `frames`, `longest` and `limit`).
var settle := FrameSettle.new()
## Milliseconds the frames took to settle after the warm-up (-1 until they did).
var settle_ms := -1
## Milliseconds from `run` to `finished` (-1 until then).
var waited_ms := -1


## True from `run` until `finished`.
func is_waiting() -> bool:
	return stage == Stage.WARMING or stage == Stage.SETTLING


## The stage as a word for a probe's report: `warming`, `settling`, `done` (or `idle`).
func stage_name() -> String:
	return str(Stage.find_key(stage)).to_lower()


## Waits for the warm-up of the level `from` is in and then for the frames to settle; says
## `finished` at the end. Stops without it when `from` leaves the tree meanwhile.
func run(from: Node) -> void:
	var began := Time.get_ticks_msec()
	var emitter := EffectEmitter.find(from)
	if emitter != null and emitter.is_warming():
		_enter(Stage.WARMING)
		await emitter.warmed
	_enter(Stage.SETTLING)
	var last := Time.get_ticks_usec()
	while not settle.is_settled():
		if not is_instance_valid(from) or not from.is_inside_tree():
			return
		await from.get_tree().process_frame
		var now := Time.get_ticks_usec()
		settle.push((now - last) / 1000000.0)
		last = now
	if not is_instance_valid(from) or not from.is_inside_tree():
		return
	settle_ms = roundi(settle.waited() * 1000.0)
	waited_ms = Time.get_ticks_msec() - began
	_enter(Stage.DONE)
	finished.emit()


func _enter(next: Stage) -> void:
	stage = next
	stage_changed.emit(next)

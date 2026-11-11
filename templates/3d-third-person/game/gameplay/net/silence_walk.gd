class_name SilenceWalk
extends RefCounted
## Steps a predicting client's own body through what the server did with its body while the
## client's thread stalled (`StallGuard`), so both bodies come out of the stall in the same state,
## their speed included. A server whose client goes silent holds the body `hold_ticks` steps,
## steps the last command again without its presses for `command_ticks` steps, then stands it
## (`PeerSlot.take`). The answer after the stall is taken whole (`Reconciler.resync`), which puts
## the client's body on the server's point but leaves it the speed it had before the stall; the
## two bodies then step the same commands at the same capped acceleration, so the gap in speed
## lasts until the speed cap closes it, and every answer meanwhile corrects the drift (0.2 to
## 0.6 m an answer in a browser, gdstudio #1127). So on a resync the client steps its own body the
## same way at once, and the answer after the stall measures centimetres.

## The server's hold and repeats (`NetServer.hold_ticks`, `command_ticks`).
var hold_ticks := NetServer.HOLD_TICKS
var command_ticks := NetServer.COMMAND_TICKS
## The most standing steps walked; a body at rest on the floor stops sooner. A stall longer than
## the repeats and this ends where a body at rest stands.
var most_standing := NetLimits.TICK_RATE * 2
## Stalls walked, and the steps walked in all.
var walks := 0
var steps := 0

var _last := PlayerCommand.new()
var _has_last := false


## Keeps the command the body stepped last: the one the server steps again through a silence.
func remember(command: PlayerCommand) -> void:
	_last.copy_from(command)
	_has_last = true


## Forgets the last command (a new seat: the server has none to repeat).
func reset() -> void:
	_has_last = false


## Steps `body` as the server stepped its own through `silent` steps without a command from this
## client (with `delta` each); returns the steps taken.
func walk(body: Character, silent: int, delta: float) -> int:
	if not _has_last or silent <= hold_ticks:
		return 0
	walks += 1
	var command := _last.clone()
	command.clear_edges()
	var repeats := mini(silent - hold_ticks, command_ticks)
	for _i in repeats:
		body.step(command, delta)
	command.clear()
	var standing := mini(silent - hold_ticks - repeats, most_standing)
	var stood := 0
	while stood < standing and not _at_rest(body):
		body.step(command, delta)
		stood += 1
	steps += repeats + stood
	return repeats + stood


# A body at rest on the floor stays where it is through any number of standing steps.
static func _at_rest(body: Character) -> bool:
	return body.velocity.is_zero_approx() and body.is_on_floor()

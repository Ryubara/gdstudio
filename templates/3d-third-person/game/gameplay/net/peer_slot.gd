class_name PeerSlot
extends RefCounted
## One connection to a `NetServer`: who it is (the listener's peer id, then the slot and name its
## HELLO earned), what it may send (`PeerLimits`), its body, and its commands. Plain code with no
## node, so a test can step it by hand.
##
## The commands: each one received with a `seq` past the last is queued; every server step takes
## up to `MAX_PER_STEP` of them, in order, and the body steps once for each (each command is applied
## exactly once). With none waiting, the last command is stepped again with its presses taken out
## (`PlayerCommand.clear_edges`) for `command_ticks` steps, then a command that asks for nothing
## (the view kept) until the next arrives: a client that stalls keeps walking a moment, then stands.
## Before the repeats the body waits `hold_ticks` steps for a late command without stepping
## (`HELD`): commands from another machine arrive a frame early or late as the two clocks drift,
## and a repeat made for a command that was merely late puts the body a step ahead of where the
## client predicted it (`NetClient`); a body held one step and stepped twice the next ends where
## one stepped once a step ends.
## `ack` is the `seq` of the last command applied, which every TICK to this client carries.

## The most commands one step applies for one peer: a client back from a stall catches up in a few
## steps, and a burst cannot freeze the server.
const MAX_PER_STEP := 6
## The most commands that may wait: a stall of `NetLimits.STALL_SECONDS`. When more come, the
## oldest is dropped and its presses go to the next (`PlayerCommand.merge_edges_from`).
const MAX_QUEUED := NetLimits.TICK_RATE * NetLimits.STALL_SECONDS
## What a step's entry in `history` says when no command of the client was applied.
const REPEATED := -1
const STOOD := -2
const IDLE := 0
const HELD := -3

## The listener's id of the connection.
var peer_id := 0
## The player's slot, 0 to `NetLimits.MAX_PLAYERS` - 1, or -1 before its HELLO is answered.
var slot := -1
var player_name := ""
var limits := PeerLimits.new()
## The body this player's commands step (null before the HELLO is answered).
var body: Character
## When the connection came, and when its last command came (the server's clock, seconds).
var connected_at := 0.0
var last_command_at := 0.0
## The `seq` of the last command applied (0 before the first).
var ack := 0
## The `seq` of the last command queued.
var last_seq := 0
## Steps since the last command applied (repeats, then standing).
var silent_steps := 0
## Steps the body was held waiting for a late command, and steps it repeated the last one
## (since the server last read and cleared them: `NetServer`'s stats).
var held := 0
var repeated := 0
## The connection is being hung up on (a refusal, a kick, a silence): nothing it sends counts.
var leaving := false
## Events that wait for the next TICK to this client (kept when a TICK could not be sent).
var events: Array[NetEvent] = []
## A TICK to this client was refused since the last stats line (its socket was full).
var stalled := false
## When on, every step appends the `seq` it applied, or `HELD`, `REPEATED`, `STOOD` or `IDLE` (a
## test replays the same steps offline).
var keep_history := false
var history := PackedInt64Array()
## With `keep_history`: how many of `history`'s entries each step stepped.
var history_steps := PackedInt32Array()

var _queue: Array[PlayerCommand] = []
## The command the last step used, written again by each step.
var _stepped := PlayerCommand.new()
var _has_command := false


func _init(id := 0, now := 0.0) -> void:
	peer_id = id
	connected_at = now
	last_command_at = now


func is_seated() -> bool:
	return slot >= 0


## Commands waiting.
func queued() -> int:
	return _queue.size()


## Starts the view of a body that has had no command yet (where it looks before the first).
func seat(at_slot: int, seated_body: Character, now: float) -> void:
	slot = at_slot
	body = seated_body
	last_command_at = now
	_stepped.yaw = seated_body.view_yaw
	_stepped.pitch = seated_body.view_pitch


## Queues a command; false (nothing queued) when its `seq` is not past the last one.
func push(command: PlayerCommand, now: float) -> bool:
	if command.seq <= last_seq:
		return false
	last_seq = command.seq
	last_command_at = now
	_queue.append(command)
	if _queue.size() > MAX_QUEUED:
		var oldest: PlayerCommand = _queue.pop_front()
		_queue[0].merge_edges_from(oldest)
	return true


## The commands one server step applies to the body, in order: up to `max_count` of the queue, or
## none for `hold_ticks` steps (the body waits for a late command), then the last one again
## without its presses for `command_ticks` steps, then one that asks for nothing. Each returned
## command is stepped once.
func take(max_count: int, command_ticks: int, hold_ticks := 0) -> Array[PlayerCommand]:
	var out: Array[PlayerCommand] = []
	while not _queue.is_empty() and out.size() < max_count:
		var command: PlayerCommand = _queue.pop_front()
		ack = command.seq
		_note(command.seq)
		out.append(command)
	if not out.is_empty():
		_stepped.copy_from(out[-1])
		_has_command = true
		silent_steps = 0
		_note_step(out.size())
		return out
	silent_steps += 1
	if not _has_command:
		_note(IDLE)
	elif silent_steps <= hold_ticks:
		held += 1
		_note(HELD)
		_note_step(1)
		return out
	elif silent_steps <= hold_ticks + command_ticks:
		repeated += 1
		_stepped.clear_edges()
		_note(REPEATED)
	else:
		_stepped.clear()
		_note(STOOD)
	out.append(_stepped)
	_note_step(1)
	return out


## Adds an event for the next TICK; past four TICKs' worth the oldest goes (the snapshot itself is
## whole, so only a name or a cosmetic is lost by a client that stopped reading).
func add_event(event: NetEvent) -> void:
	events.append(event)
	while events.size() > NetLimits.MAX_EVENTS * 4:
		events.pop_front()


## The events the next TICK carries (at most `NetLimits.MAX_EVENTS`; the rest wait).
func events_to_send() -> Array[NetEvent]:
	return events.slice(0, NetLimits.MAX_EVENTS)


## The TICK carrying `count` events left.
func sent_events(count: int) -> void:
	events = events.slice(count)


func _note(entry: int) -> void:
	if keep_history:
		history.append(entry)


func _note_step(count: int) -> void:
	if keep_history:
		history_steps.append(count)

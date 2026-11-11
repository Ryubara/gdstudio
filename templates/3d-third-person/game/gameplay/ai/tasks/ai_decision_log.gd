class_name AiDecisionLog
extends RefCounted
## The last decisions of one task runner, each with the beliefs that produced it: a ring of
## `CAPACITY` entries, written only when something is decided (a task assigned, started,
## suspended, resumed, ended, refused, deferred), never on a quiet step. A test compares two logs
## for a replay, and a stuck or dead character's log says why it did what it did.

## Entries kept; the oldest is written over.
const CAPACITY := 300

## Entries written since the runner started (more than `CAPACITY` once the ring is full).
var written := 0

var _ring: Array[Dictionary] = []


func _init() -> void:
	_ring.resize(CAPACITY)


## Writes one decision: `what` happened (`&"started"`, `&"failed"`...) to `task` at `time`.
func write(time: float, what: StringName, task: AiTask, beliefs: Dictionary) -> void:
	var entry := {
		&"time": snappedf(time, 0.0001),
		&"what": what,
		&"task": task.display_label() if task != null else "",
		&"layer": task.layer if task != null else -1,
		&"state": task.state if task != null else -1,
		&"reason": task.reason if task != null else 0,
		&"beliefs": beliefs.duplicate(),
	}
	_ring[written % CAPACITY] = entry
	written += 1


## The entries kept, oldest first.
func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var kept := mini(written, CAPACITY)
	for index in kept:
		out.append(_ring[(written - kept + index) % CAPACITY])
	return out


## The last entry, or an empty one.
func last() -> Dictionary:
	return _ring[(written - 1) % CAPACITY] if written > 0 else {}


## The entries as lines of text, oldest first (for a test's failure message or a dump).
func dump() -> String:
	var lines := PackedStringArray()
	for entry in entries():
		lines.append("%8.3f %-10s %-14s %s" % [entry.time, entry.what, entry.task, entry.beliefs])
	return "\n".join(lines)

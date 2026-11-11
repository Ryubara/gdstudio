@tool
class_name AiTaskRepeat
extends AiTaskComposite
## Runs its one child again each time it succeeds: a patrol is a repeat of a route. `count` 0
## repeats until something takes the character off (a routine), and such a repeat has no end of
## its own, so outside ROUTINE and DEFAULT it needs a hard timeout. A failure of the child ends
## the repeat unless the child's `on_fail` is SKIP, which starts the next round.

## Rounds to run; 0 repeats forever.
@export_range(0, 1000) var count := 0

## Rounds finished.
var rounds := 0


func start() -> void:
	rounds = 0
	for child in children:
		if child != null:
			child.reset()


func update(delta: float) -> Status:
	var child := _child()
	if child == null:
		return Status.SUCCEEDED
	var result := child.advance(delta, run_profile())
	if result == Status.RUNNING:
		return Status.RUNNING
	if result == Status.FAILED and not AiTaskComposite.skips(child):
		reason = child.reason
		return Status.FAILED
	rounds += 1
	if count > 0 and rounds >= count:
		return Status.SUCCEEDED
	child.reset()
	return Status.RUNNING


func suspend() -> void:
	var child := _child()
	if child != null:
		child.pause(suspended_at)


func resume() -> Resume:
	var child := _child()
	if child == null or child.state != State.SUSPENDED:
		return Resume.RESUME
	var answer := child.unpause(run_time())
	if answer == Resume.FAILED and not AiTaskComposite.skips(child):
		reason = child.reason
		return Resume.FAILED
	if answer == Resume.SUCCEEDED or answer == Resume.FAILED:
		child.reset()
	return Resume.RESUME


func cancel() -> void:
	_cancel_children(Reason.CANCELLED)


func has_end_condition() -> bool:
	return count > 0 or ends_on_condition


func _child() -> AiTask:
	return children[0] if not children.is_empty() else null

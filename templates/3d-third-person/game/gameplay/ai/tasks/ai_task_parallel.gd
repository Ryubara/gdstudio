@tool
class_name AiTaskParallel
extends AiTaskComposite
## Runs its children at the same time, each on channels of its own (walk while looking around,
## talk while walking): it succeeds when every child has, or when the first one does with
## `finish_on_first`. A child that fails ends it `FAILED` unless the child's `on_fail` is SKIP;
## the children still running are dropped when it ends.

## Ends when the first child succeeds (the rest are dropped) instead of when all have.
@export var finish_on_first := false


func start() -> void:
	for child in children:
		if child != null:
			child.reset()


func update(delta: float) -> Status:
	var running := 0
	for child in children:
		if child == null or child.is_done():
			continue
		var result := child.advance(delta, run_profile())
		if result == Status.RUNNING:
			running += 1
		elif result == Status.SUCCEEDED and finish_on_first:
			_cancel_children(Reason.CANCELLED)
			return Status.SUCCEEDED
		elif result == Status.FAILED and not AiTaskComposite.skips(child):
			reason = child.reason
			_cancel_children(Reason.CANCELLED)
			return Status.FAILED
	return Status.RUNNING if running > 0 else Status.SUCCEEDED


func suspend() -> void:
	for child in children:
		if child != null:
			child.pause(suspended_at)


func resume() -> Resume:
	for child in children:
		if child == null or child.state != State.SUSPENDED:
			continue
		if child.unpause(run_time()) == Resume.FAILED and not AiTaskComposite.skips(child):
			reason = child.reason
			return Resume.FAILED
	return Resume.RESUME


func cancel() -> void:
	_cancel_children(Reason.CANCELLED)


func authoring_problems() -> PackedStringArray:
	var problems := super()
	var seen := 0
	for child in children:
		if child == null:
			continue
		var mask := child.claimed_channels()
		if seen & mask:
			problems.append("%s: two children drive the same channel" % display_label())
		seen |= mask
	return problems

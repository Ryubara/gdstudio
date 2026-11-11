@tool
class_name AiTaskSequence
extends AiTaskComposite
## Runs its children one after another and succeeds when the last does: a patrol route is a
## sequence of walks and waits inside an `AiTaskRepeat`. A child that fails ends the sequence
## `FAILED` with the child's reason unless the child's `on_fail` is SKIP. When the sequence is
## taken off and comes back, the running child follows its own `when_interrupted`: resumed,
## restarted, or (SKIP_TO_NEXT) passed over for the next step; ABORT ends the whole sequence.

## The step running now (an index into `children`).
var step := 0


func start() -> void:
	step = 0
	for child in children:
		if child != null:
			child.reset()


func update(delta: float) -> Status:
	# A child that ends at once lets the next one start in the same step, at most one pass.
	for _pass in children.size() + 1:
		if step >= children.size():
			return Status.SUCCEEDED
		var child := children[step]
		if child == null:
			step += 1
			continue
		var result := child.advance(delta, run_profile())
		if result == Status.RUNNING:
			return Status.RUNNING
		if result == Status.FAILED and not AiTaskComposite.skips(child):
			reason = child.reason
			return Status.FAILED
		step += 1
		delta = 0.0
	return Status.RUNNING


func suspend() -> void:
	var child := _current()
	if child != null:
		child.pause(suspended_at)


func resume() -> Resume:
	var child := _current()
	if child == null or child.state != State.SUSPENDED:
		return Resume.RESUME
	match child.when_interrupted:
		WhenInterrupted.SKIP_TO_NEXT:
			child.drop(Reason.CANCELLED)
			step += 1
			return Resume.RESUME
		WhenInterrupted.ABORT:
			child.drop(Reason.CANCELLED)
			reason = Reason.CANCELLED
			return Resume.FAILED
	var answer := child.unpause(run_time())
	if answer == Resume.FAILED and not AiTaskComposite.skips(child):
		reason = child.reason
		return Resume.FAILED
	if answer == Resume.SUCCEEDED or answer == Resume.FAILED:
		step += 1
	return Resume.RESUME


func cancel() -> void:
	_cancel_children(Reason.CANCELLED)


func detail() -> String:
	var child := _current()
	if child == null:
		return ""
	var inner := child.detail()
	return child.display_label() + (" / " + inner if not inner.is_empty() else "")


func _current() -> AiTask:
	return children[step] if step < children.size() else null

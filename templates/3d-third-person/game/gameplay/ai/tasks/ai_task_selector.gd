@tool
class_name AiTaskSelector
extends AiTaskSequence
## Tries its children in order until one succeeds (take cover here, else there, else run): it
## succeeds with the first child that does and fails, with the last child's reason, when every
## child has failed. Suspension and resume work as in `AiTaskSequence`.


func update(delta: float) -> Status:
	for _pass in children.size() + 1:
		if step >= children.size():
			reason = reason if reason != Reason.NONE else Reason.BLOCKED
			return Status.FAILED
		var child := children[step]
		if child == null:
			step += 1
			continue
		var result := child.advance(delta, run_profile())
		if result == Status.RUNNING:
			return Status.RUNNING
		if result == Status.SUCCEEDED:
			return Status.SUCCEEDED
		if child.reason == Reason.INVALID:
			reason = Reason.INVALID
			return Status.FAILED
		reason = child.reason
		step += 1
		delta = 0.0
	return Status.RUNNING

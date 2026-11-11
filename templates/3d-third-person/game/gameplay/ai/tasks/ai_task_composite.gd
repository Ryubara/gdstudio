@tool
class_name AiTaskComposite
extends AiTask
## The base of the tasks made of tasks (`AiTaskSequence`, `AiTaskParallel`, `AiTaskSelector`):
## a list of children authored in the inspector, so a route or a plan is data, not code. A child
## runs under its own contract (time limits, `on_fail`, the watchdog); the composite binds them
## to its runner, adds up their channels and passes a suspension on to the ones running.

## The steps, in order.
@export var children: Array[AiTask] = []


func claimed_channels() -> int:
	var mask := channels
	for child in children:
		if child != null:
			mask |= child.claimed_channels()
	return mask


func bind(to: AiTaskRunner, body: Node, channels_of: AiController) -> void:
	super(to, body, channels_of)
	for child in children:
		if child != null:
			child.bind(to, body, channels_of)


func authoring_problems() -> PackedStringArray:
	var problems := super()
	for child in children:
		if child == null:
			problems.append("%s: an empty child slot" % display_label())
			continue
		if child.hard_timeout == 0.0 and not child.has_end_condition():
			problems.append(
				(
					"%s: child %s has no timeout and no end condition"
					% [display_label(), child.display_label()]
				)
			)
		problems.append_array(child.authoring_problems())
	return problems


## True when `child` ended in a failure its composite passes over (`on_fail = SKIP`); a script
## error (`INVALID`) is never passed over.
static func skips(child: AiTask) -> bool:
	return child.on_fail == OnFail.SKIP and child.reason != Reason.INVALID


func _fails_through_children() -> bool:
	return true


func _cancel_children(why: Reason) -> void:
	for child in children:
		if child != null:
			child.drop(why)

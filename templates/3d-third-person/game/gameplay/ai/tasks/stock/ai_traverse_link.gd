@tool
class_name AiTraverseLink
extends AiStockTask
## Crosses a navigation link the navigator stopped at (`auto_traverse_links` off: the brain's
## `link` event): from the link's start (`AiBrain.link_from`) to its end (`goal`), sprinting, with
## a jump `jump_after` metres past the start (a gap; a drop is simply walked off). It tells the
## navigator the link is crossed (`finish_link()`) once within `near_enough` of the end, or fails
## `BLOCKED` after `give_up_seconds`. A REACTION task: the walk it interrupts asks for its path
## again from the far side.

## Metres past the link's start where it jumps; 0 never jumps.
@export_range(0.0, 5.0, 0.05, "suffix:m") var jump_after := 0.4
## Arrives this near the link's end.
@export_range(0.1, 3.0, 0.05, "suffix:m") var near_enough := 0.8
## Seconds before it gives up.
@export_range(0.5, 30.0, 0.5, "suffix:s") var give_up_seconds := 4.0

var _from := Vector3.ZERO
var _jumped := false


func _init() -> void:
	id = &"traverse_link"
	layer = Layer.REACTION
	channels = Channel.MOVE
	interruptible = Interruptible.BY_HIGHER_LAYER


func start() -> void:
	var mind := brain()
	_from = mind.link_from if mind != null else (character as Node3D).global_position
	_jumped = false
	last_known = goal


func update(_delta: float) -> Status:
	controller.jump = false
	var at := (character as Node3D).global_position
	if flat_distance(goal) <= near_enough:
		_done()
		return Status.SUCCEEDED
	if elapsed >= give_up_seconds:
		_done()
		reason = Reason.BLOCKED
		return Status.FAILED
	var toward := goal - at
	toward.y = 0.0
	controller.walk_direction = toward.normalized()
	controller.walk_strength = 1.0
	controller.sprint = true
	var past := Vector2(at.x - _from.x, at.z - _from.z).length()
	if jump_after > 0.0 and not _jumped and past >= jump_after:
		controller.jump = true
		_jumped = true
	return Status.RUNNING


func has_end_condition() -> bool:
	return true


func _done() -> void:
	controller.sprint = false
	controller.jump = false
	var walker := nav()
	if walker != null:
		walker.finish_link()

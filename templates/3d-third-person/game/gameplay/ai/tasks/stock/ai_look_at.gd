@tool
class_name AiLookAt
extends AiStockTask
## Turns the look toward its subject (where it is believed to be) or, with none, its goal, for
## `seconds`; the look channel only, so a walk can go on beside it.

## How long it looks.
@export_range(0.1, 60.0, 0.1, "suffix:s") var seconds := 2.0


func _init() -> void:
	id = &"look_at"
	layer = Layer.RESPONSE
	channels = Channel.LOOK


func update(_delta: float) -> Status:
	var belief := belief_of(subject())
	var point := belief.last_position if belief != null else goal
	last_known = point
	look_toward(point)
	return Status.SUCCEEDED if elapsed >= seconds else Status.RUNNING


func has_end_condition() -> bool:
	return true

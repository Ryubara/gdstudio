@tool
class_name AiWait
extends AiStockTask
## Stands still for `seconds` (a pause in a route, a beat before going home). Drives no channel,
## so a look or a bark beside it in a parallel is free; interrupted, it resumes with the time left.

## How long it waits.
@export_range(0.0, 600.0, 0.1, "suffix:s") var seconds := 2.0


func _init() -> void:
	id = &"wait"
	channels = 0


func update(_delta: float) -> Status:
	return Status.SUCCEEDED if elapsed >= seconds else Status.RUNNING


func has_end_condition() -> bool:
	return true

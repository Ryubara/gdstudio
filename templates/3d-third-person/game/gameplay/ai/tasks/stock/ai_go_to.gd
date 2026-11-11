@tool
class_name AiGoTo
extends AiStockTask
## Walks to `goal` with the navigator and succeeds there; fails `NO_PATH` when the navigator gives
## the goal up. Interrupted, it stops the walk and asks for the path again when it resumes (a goal
## now unreachable ends it `FAILED(NO_PATH)`).

## How fast it goes.
@export var speed := Speed.WALK


func _init() -> void:
	id = &"go_to"
	channels = Channel.MOVE


func start() -> void:
	last_known = goal
	go(goal, speed)


func update(_delta: float) -> Status:
	match walk_state():
		Walk.ARRIVED:
			return Status.SUCCEEDED
		Walk.FAILED:
			reason = Reason.NO_PATH
			return Status.FAILED
	return Status.RUNNING


func resume() -> Resume:
	if not go(goal, speed):
		reason = Reason.NO_PATH
		return Resume.FAILED
	return Resume.RESUME


func has_end_condition() -> bool:
	return true

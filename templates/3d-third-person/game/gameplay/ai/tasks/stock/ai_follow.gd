@tool
class_name AiFollow
extends AiStockTask
## Keeps within `band` metres of its subject (an ally's player, a leader) with the navigator, for
## as long as it runs (a routine: no time limit); fails `TARGET_LOST` when the subject is gone.

## How near it keeps.
@export_range(0.5, 30.0, 0.1, "suffix:m") var band := 2.5
## How fast it catches up.
@export var speed := Speed.RUN


func _init() -> void:
	id = &"follow"
	layer = Layer.ROUTINE
	channels = Channel.MOVE
	hard_timeout = 0.0


func start() -> void:
	_follow()


func update(_delta: float) -> Status:
	var leader := subject()
	if leader == null:
		reason = Reason.TARGET_LOST
		return Status.FAILED
	var walker := nav()
	if walker != null and walker.mode != AiNavigator.Mode.FOLLOW:
		_follow()
	last_known = leader.global_position
	return Status.RUNNING


func resume() -> Resume:
	_follow()
	return Resume.RESUME


func _follow() -> void:
	var leader := subject()
	var walker := nav()
	if leader != null and walker != null:
		walker.follow(leader, band, speed_share(speed))

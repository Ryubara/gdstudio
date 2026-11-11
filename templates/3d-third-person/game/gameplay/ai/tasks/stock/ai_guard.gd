@tool
class_name AiGuard
extends AiStockTask
## Holds a place (`goal`: an order's point, or the character's home): walks back to it when more
## than `radius` away and looks around while there, until relieved (it ends only when taken off:
## an order revoked, a routine replaced). A guard's default task, and the answer to `order_hold`.

## How far it may stand from the place.
@export_range(0.2, 30.0, 0.1, "suffix:m") var radius := 1.5
## How far it looks to each side.
@export_range(0.0, 180.0, 1.0, "suffix:°") var sweep_degrees := 60.0
## Seconds of one look round.
@export_range(0.5, 30.0, 0.1, "suffix:s") var period := 6.0

var _heading := 0.0
var _walking := false


func _init() -> void:
	id = &"guard"
	layer = Layer.DEFAULT
	channels = Channel.MOVE | Channel.LOOK
	hard_timeout = 0.0
	ends_on_condition = true


func start() -> void:
	_heading = body().facing if body() != null else 0.0
	_walking = false


func update(_delta: float) -> Status:
	last_known = goal
	if flat_distance(goal) > radius:
		if not _walking or walk_state() == Walk.FAILED:
			_walking = go(goal, Speed.WALK)
		return Status.RUNNING
	if _walking:
		stop_walk()
		_walking = false
		_heading = body().facing
	var turn := deg_to_rad(sweep_degrees) * sin(elapsed / period * TAU)
	controller.look_direction = Vector3.BACK.rotated(Vector3.UP, _heading + turn)
	return Status.RUNNING


func resume() -> Resume:
	_walking = false
	return Resume.RESUME

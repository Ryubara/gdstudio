@tool
class_name AiInvestigate
extends AiStockTask
## Goes to look at a place (a noise, a glimpse): walks to `goal`, looking toward it, then looks
## around for `look_seconds`. A goal it cannot reach is looked at from where it stands. It ends
## at once when a hostile comes into view (the brain's noticed answer takes over); a newer noise
## merged into it sends it to the newer place.

## How fast it goes.
@export var speed := Speed.WALK
## How long it looks around once there.
@export_range(0.0, 60.0, 0.1, "suffix:s") var look_seconds := 3.0
## Stops this near the place.
@export_range(0.0, 10.0, 0.1, "suffix:m") var near_enough := 1.5

var _there_at := -1.0
var _heading := 0.0


func _init() -> void:
	id = &"investigate"
	layer = Layer.RESPONSE
	channels = Channel.MOVE | Channel.LOOK


func start() -> void:
	_there_at = -1.0
	last_known = goal
	if flat_distance(goal) <= near_enough or not go(goal, speed):
		_arrive()


func update(_delta: float) -> Status:
	if found_threat():
		return Status.SUCCEEDED
	if _there_at < 0.0:
		look_toward(goal)
		if flat_distance(goal) <= near_enough or walk_state() != Walk.GOING:
			stop_walk()
			_arrive()
		return Status.RUNNING
	var looked := elapsed - _there_at
	var turn := deg_to_rad(70.0) * sin(looked / 3.0 * TAU)
	controller.look_direction = Vector3.BACK.rotated(Vector3.UP, _heading + turn)
	return Status.SUCCEEDED if looked >= look_seconds else Status.RUNNING


func resume() -> Resume:
	if _there_at < 0.0 and not go(goal, speed):
		_arrive()
	return Resume.RESUME


## A newer noise of the same kind of task: it goes to the newer place.
func merge(incoming: AiTaskContract) -> void:
	var was := goal
	super(incoming)
	if state == State.RUNNING and goal.distance_to(was) > 1.0:
		start()


func has_end_condition() -> bool:
	return true


func _arrive() -> void:
	_there_at = elapsed
	var at := (character as Node3D).global_position
	var toward := goal - at
	_heading = atan2(toward.x, toward.z) if toward.length_squared() > 0.01 else body().facing

@tool
class_name AiSearch
extends AiStockTask
## Searches for a lost subject around where it was last believed (`goal`): goes there, then to
## `spots` seeded points within `radius` of it, looking around `look_seconds` at each, and ends
## after them (or `search_seconds`). It ends at once when a hostile comes into view (the brain's
## noticed answer takes over); when it ends without one, the routine it suspended resumes.

## How fast it goes.
@export var speed := Speed.WALK
## Points searched after the first.
@export_range(0, 12) var spots := 3
## How far from the place it looks.
@export_range(0.5, 50.0, 0.5, "suffix:m") var radius := 5.0
## How long it looks around at each point.
@export_range(0.0, 30.0, 0.1, "suffix:s") var look_seconds := 1.5
## The longest it searches.
@export_range(1.0, 300.0, 1.0, "suffix:s") var search_seconds := 20.0

## Points visited so far (the first is the place itself).
var visited := 0

var _rng := RandomNumberGenerator.new()
var _looking := -1.0
var _point := Vector3.ZERO


func _init() -> void:
	id = &"search"
	layer = Layer.RESPONSE
	channels = Channel.MOVE | Channel.LOOK


func start() -> void:
	var mind := brain()
	_rng.seed = (mind.random_seed if mind != null else 0) + int(goal.x * 100.0 + goal.z * 7.0)
	visited = 0
	last_known = goal
	_walk_to(goal)


func update(delta: float) -> Status:
	if found_threat():
		return Status.SUCCEEDED
	if elapsed >= search_seconds:
		return Status.SUCCEEDED
	if _looking >= 0.0:
		_looking += delta
		var turn := deg_to_rad(80.0) * sin(_looking / maxf(look_seconds, 0.1) * PI)
		controller.look_direction = Vector3.BACK.rotated(Vector3.UP, body().facing + turn)
		if _looking < look_seconds:
			return Status.RUNNING
		if visited > spots:
			return Status.SUCCEEDED
		var angle := _rng.randf() * TAU
		_walk_to(goal + Vector3(cos(angle), 0.0, sin(angle)) * radius * (0.5 + 0.5 * _rng.randf()))
		return Status.RUNNING
	look_toward(_point)
	if walk_state() != Walk.GOING or flat_distance(_point) < 1.0:
		stop_walk()
		visited += 1
		_looking = 0.0
	return Status.RUNNING


func resume() -> Resume:
	if _looking < 0.0:
		_walk_to(_point)
	return Resume.RESUME


func has_end_condition() -> bool:
	return true


func detail() -> String:
	return "%d/%d" % [mini(visited, spots + 1), spots + 1]


func _walk_to(point: Vector3) -> void:
	_point = point
	_looking = -1.0
	if not go(point, speed):
		visited += 1
		_looking = 0.0

@tool
class_name AiChase
extends AiStockTask
## Runs after a subject it lost sight of, to where it is believed to be (a memory, a telling, a
## noise updates the place, and the walk follows when the place moves `repath_distance`). It ends
## as soon as a hostile is in view again (the brain's noticed answer takes over); at the place with
## nothing in view, or after `give_up_seconds`, it fails `TARGET_LOST`, which the brain routes as
## `lost_trail` (a search).

## How fast it runs.
@export var speed := Speed.RUN
## A place that moved this far starts the walk again.
@export_range(0.2, 20.0, 0.1, "suffix:m") var repath_distance := 1.5
## The longest it chases.
@export_range(1.0, 120.0, 0.5, "suffix:s") var give_up_seconds := 12.0
## Arrives this near the place.
@export_range(0.2, 10.0, 0.1, "suffix:m") var near_enough := 1.5


func _init() -> void:
	id = &"chase"
	layer = Layer.RESPONSE
	channels = Channel.MOVE | Channel.LOOK
	answers_threat = true


func start() -> void:
	last_known = _place()
	go(last_known, speed)


func update(_delta: float) -> Status:
	if found_threat():
		return Status.SUCCEEDED
	var place := _place()
	if place.distance_to(last_known) > repath_distance:
		last_known = place
		go(place, speed)
	look_toward(last_known)
	if elapsed >= give_up_seconds:
		return _lost()
	if flat_distance(last_known) <= near_enough or walk_state() != Walk.GOING:
		return _lost()
	return Status.RUNNING


func resume() -> Resume:
	if not go(_place(), speed):
		reason = Reason.TARGET_LOST
		return Resume.FAILED
	return Resume.RESUME


func event_for(why: Reason) -> StringName:
	return AiBehaviourSet.LOST_TRAIL if why == Reason.TARGET_LOST else super(why)


func has_end_condition() -> bool:
	return true


func _place() -> Vector3:
	var belief := belief_of(subject())
	return belief.last_position if belief != null else goal


func _lost() -> Status:
	stop_walk()
	reason = Reason.TARGET_LOST
	return Status.FAILED

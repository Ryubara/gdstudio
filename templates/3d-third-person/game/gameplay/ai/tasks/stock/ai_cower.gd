@tool
class_name AiCower
extends AiStockTask
## Crouches where it is, facing the threat, until the threat has not been believed for the
## profile's `panic_recovery_seconds` (or `calm_seconds` when set); then it gets up and the
## situation calms to Alert. A frightened civilian's answer, and a flight's fallback.

## Seconds with no threat believed before it gets up; 0 takes the profile's
## `panic_recovery_seconds`.
@export_range(0.0, 120.0, 0.5, "suffix:s") var calm_seconds := 0.0

var _calm := 0.0


func _init() -> void:
	id = &"cower"
	layer = Layer.RESPONSE
	channels = Channel.MOVE | Channel.LOOK
	answers_threat = true
	ends_on_condition = true
	hard_timeout = 0.0


func start() -> void:
	_calm = 0.0
	stop_walk()


func update(delta: float) -> Status:
	controller.walk_direction = Vector3.ZERO
	controller.crouch = true
	var belief := belief_of(subject())
	if belief != null and belief.believed:
		last_known = belief.last_position
		_calm = 0.0
		look_toward(last_known)
	else:
		_calm += delta
	var wait_for := calm_seconds
	if wait_for <= 0.0:
		wait_for = run_profile().panic_recovery_seconds if run_profile() != null else 8.0
	if _calm < wait_for:
		return Status.RUNNING
	controller.crouch = false
	var at := body()
	if at != null and at.situation.current == AiSituation.Situation.FLEEING:
		at.situation.request(AiSituation.Situation.ALERT)
	return Status.SUCCEEDED


func suspend() -> void:
	super()
	if controller != null:
		controller.crouch = false


func cancel() -> void:
	super()
	if controller != null:
		controller.crouch = false

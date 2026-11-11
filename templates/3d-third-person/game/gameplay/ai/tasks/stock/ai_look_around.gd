@tool
class_name AiLookAround
extends AiStockTask
## Sweeps the look `sweep_degrees` to each side of the way it faced when it started, one sweep
## every `period` seconds, for `seconds` (0: for as long as it runs, a DEFAULT task).

## How long it looks around; 0 never ends.
@export_range(0.0, 600.0, 0.1, "suffix:s") var seconds := 3.0
## How far to each side.
@export_range(0.0, 180.0, 1.0, "suffix:°") var sweep_degrees := 70.0
## Seconds of one sweep, left and back and right and back.
@export_range(0.5, 30.0, 0.1, "suffix:s") var period := 3.0

var _heading := 0.0


func _init() -> void:
	id = &"look_around"
	layer = Layer.RESPONSE
	channels = Channel.LOOK


func start() -> void:
	_heading = body().facing if body() != null else 0.0


func update(_delta: float) -> Status:
	var turn := deg_to_rad(sweep_degrees) * sin(elapsed / period * TAU)
	if controller != null:
		controller.look_direction = Vector3.BACK.rotated(Vector3.UP, _heading + turn)
	if seconds > 0.0 and elapsed >= seconds:
		return Status.SUCCEEDED
	return Status.RUNNING


func has_end_condition() -> bool:
	return seconds > 0.0

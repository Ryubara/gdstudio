@tool
class_name AiWander
extends AiStockTask
## Strolls between seeded points within the brain's `home_radius` of its home, pausing between
## `pause_min` and `pause_max` seconds at each, for as long as it runs (a civilian's routine). It
## roams: it does not run while the character plays Safe.

## How fast it strolls.
@export var speed := Speed.WALK
## The pause at each point, from and to.
@export_range(0.0, 60.0, 0.1, "suffix:s") var pause_min := 1.0
@export_range(0.0, 60.0, 0.1, "suffix:s") var pause_max := 3.0

var _rng := RandomNumberGenerator.new()
var _pause := -1.0
var _point := Vector3.ZERO


func _init() -> void:
	id = &"wander"
	layer = Layer.ROUTINE
	channels = Channel.MOVE
	hard_timeout = 0.0
	roams = true


func start() -> void:
	var mind := brain()
	_rng.seed = (mind.random_seed if mind != null else 0) + hash(String(character.name))
	_next_point()


func update(delta: float) -> Status:
	if _pause >= 0.0:
		_pause -= delta
		if _pause < 0.0:
			_next_point()
		return Status.RUNNING
	if walk_state() != Walk.GOING:
		_pause = _rng.randf_range(pause_min, maxf(pause_min, pause_max))
	return Status.RUNNING


func resume() -> Resume:
	if _pause < 0.0:
		go(_point, speed)
	return Resume.RESUME


func _next_point() -> void:
	var mind := brain()
	var centre := mind.home if mind != null else (character as Node3D).global_position
	var radius := mind.home_radius if mind != null else 6.0
	var angle := _rng.randf() * TAU
	var far := radius * sqrt(_rng.randf())
	_point = centre + Vector3(cos(angle), 0.0, sin(angle)) * far
	_pause = -1.0
	go(_point, speed)

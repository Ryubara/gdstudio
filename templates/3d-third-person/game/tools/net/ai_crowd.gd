class_name AiCrowd
extends Node
## A crowd of AI characters for a server under measurement (`tools/net/gate_server.gd --ai N`,
## gdstudio #970): `count` characters of `character_scene` set out in a grid over `area` of the
## map, each walking its own circle (the deciding parts taken out, so every one moves every tick
## and the wire carries the most it can: the bytes are an upper bound for a crowd that also
## stands), or, with `real`, the scene's own guards as they are, deciding for themselves.
## Positions and phases come from `seed_value`, never the clock, so a run repeats.

const CHARACTER_SCENE := "res://gameplay/ai/ai_character.tscn"
const GUARD_SCENE := "res://gameplay/ai/ai_guard.tscn"
## The slots a walker has taken out.
const SLOTS: Array[StringName] = [&"Navigator", &"Brain", &"Senses", &"AiTasks"]

## How many characters.
@export var count := 40
## The map's ground they stand on (x and z), centred on its origin.
@export var area := Rect2(-22.0, -22.0, 44.0, 44.0)
## A walker's circle, metres, and seconds a lap (a walk of about 1.3 m/s).
@export var radius := 1.5
@export var lap_seconds := 7.0
## The guards as they are (senses, brain, tasks, navigator) instead of walkers.
@export var real := false
@export var seed_value := 970

var characters: Array[AiCharacter] = []
var _centres: PackedVector3Array = []
var _phases: PackedFloat32Array = []
var _tick := 0


## Puts the crowd in `map` (the server's `World`).
func spawn(map: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var columns := maxi(ceili(sqrt(float(count))), 1)
	var step := Vector2(area.size.x / columns, area.size.y / columns)
	var scene := load(GUARD_SCENE if real else CHARACTER_SCENE) as PackedScene
	for index in count:
		var cell := Vector2(index % columns, index / columns)
		var at := area.position + step * (cell + Vector2(0.5, 0.5))
		var centre := Vector3(at.x, 0.3, at.y)
		var body := scene.instantiate() as AiCharacter
		body.name = "Crowd%d" % index
		if not real:
			_strip(body)
		body.position = centre + Vector3(radius, 0.0, 0.0)
		map.add_child(body)
		characters.append(body)
		_centres.append(centre)
		_phases.append(rng.randf() * TAU)


func _physics_process(_delta: float) -> void:
	if real:
		return
	_tick += 1
	var turn := TAU * _tick / (lap_seconds * NetLimits.TICK_RATE)
	for index in characters.size():
		var body := characters[index]
		if not is_instance_valid(body):
			continue
		var angle := turn + _phases[index]
		# The tangent of its circle, toward the circle when it drifted off.
		var goal := _centres[index] + Vector3(cos(angle), 0.0, sin(angle)) * radius
		var controller := body.controller as AiController
		var way := goal - body.global_position
		way.y = 0.0
		controller.walk_direction = way.normalized() if way.length() > 0.05 else Vector3.ZERO
		controller.walk_strength = 0.6


static func _strip(body: AiCharacter) -> void:
	body.navigator = null
	body.brain = null
	body.senses = null
	body.task_runner = null
	for slot in SLOTS:
		var part := body.get_node_or_null(NodePath(slot))
		if part != null:
			body.remove_child(part)
			part.free()

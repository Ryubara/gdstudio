# On the clock: a ruler is fixed work timed on the wall clock, the divisor of a cost gate.
class_name PhysicsRuler
extends Node3D
## A fixed piece of the engine's native work, timed beside a cost gate's measured ticks, so the
## gate holds a timing as a ratio of work the machine did in the same seconds (kit
## docs/engines/godot/performance-budgets.md#reading-a-timing-on-a-shared-machine): a capsule
## walks a small circle round a post (`move_and_slide`) and casts a ray at it each move, the work
## an AI step spends most on, on a floor of its own far from the arena so nothing else touches
## it. Over 150 runs on GitHub's Linux runners (four processor models) it followed the AI's step
## and think better than a loop of GDScript or of `sin` (third-person/ai-characters.md#cost-gate).
## Add it to the tree before timing; free it with the arena.

## Moves (and rays) a timing, about 8 ms on the desktop and 9 to 11 on a runner.
const ROUNDS := 400
## Where the ruler's floor and body stand, metres, far off every arena.
const SPOT := Vector3(400.0, 0.0, 400.0)

var _body: CharacterBody3D


func _ready() -> void:
	_add_box(SPOT + Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
	_add_box(SPOT + Vector3(3.0, 1.0, 0.0), Vector3(1.0, 2.0, 1.0))
	_body = CharacterBody3D.new()
	var capsule := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.8
	capsule.shape = shape
	capsule.position.y = 0.9
	_body.add_child(capsule)
	_body.position = SPOT
	add_child(_body)


## Milliseconds the ruler takes now. The body is put back where it started.
func measure_ms() -> float:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.exclude = [_body.get_rid()]
	var start := Time.get_ticks_usec()
	var hits := 0
	for index in ROUNDS:
		var angle := TAU * index / 40.0
		_body.velocity = Vector3(cos(angle), -1.0, sin(angle)) * 4.0
		_body.move_and_slide()
		query.from = _body.global_position + Vector3(0.0, 1.5, 0.0)
		query.to = SPOT + Vector3(3.0, 1.0 + (index % 3) * 0.3, (index % 5) * 0.2 - 0.4)
		if not space.intersect_ray(query).is_empty():
			hits += 1
	var spent := (Time.get_ticks_usec() - start + hits * 0) / 1000.0
	_body.global_position = SPOT
	_body.velocity = Vector3.ZERO
	return spent


func _add_box(spot: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = spot
	add_child(body)

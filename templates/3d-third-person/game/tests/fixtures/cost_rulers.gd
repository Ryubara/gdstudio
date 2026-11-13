# On the clock: a ruler is fixed work timed on the wall clock, the divisor of a cost gate.
class_name CostRulers
extends Node3D
## Fixed pieces of work timed beside a cost gate's measured ticks, so a gate can hold a timing as
## a ratio of work the machine did in the same seconds (kit
## docs/engines/godot/performance-budgets.md#reading-a-timing-on-a-shared-machine). Each ruler is
## work of one kind: `script_ms()` GDScript (vectors, an array, a dictionary) and `physics_ms()`
## the engine's native work an AI step spends most on (a capsule's `move_and_slide` and ray
## queries), on a floor of its own far from the arena so nothing else touches it. Add it to the
## tree before timing `physics_ms()`; free it with the arena.

## Rounds of the script ruler (about 10 ms on the desktop the gate was set on).
const SCRIPT_ROUNDS := 60000
## Moves and rays of the physics ruler.
const PHYSICS_ROUNDS := 400
## Where the ruler's floor and body stand, metres, far off every arena.
const SPOT := Vector3(400.0, 0.0, 400.0)

var _body: CharacterBody3D


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position = SPOT + Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)
	var post := StaticBody3D.new()
	var post_shape := CollisionShape3D.new()
	var post_box := BoxShape3D.new()
	post_box.size = Vector3(1.0, 2.0, 1.0)
	post_shape.shape = post_box
	post.add_child(post_shape)
	post.position = SPOT + Vector3(3.0, 1.0, 0.0)
	add_child(post)
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


## Milliseconds the script ruler takes now: GDScript work of the AI's kind, no C library maths.
static func script_ms() -> float:
	var start := Time.get_ticks_usec()
	var points: Array[Vector3] = []
	var seen := {}
	var total := 0.0
	for index in SCRIPT_ROUNDS:
		var point := Vector3(index % 17, index % 5, index % 11) * 0.5
		points.append(point)
		total += point.length_squared() + point.dot(Vector3.UP)
		seen[index % 97] = total
		if points.size() > 64:
			points.clear()
	return (Time.get_ticks_usec() - start + int(total * 0.0) + seen.size() * 0) / 1000.0


## Milliseconds the physics ruler takes now: the body walks a small circle round the post
## (`move_and_slide`) and casts a ray at it each move. The body is put back where it started.
func physics_ms() -> float:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.exclude = [_body.get_rid()]
	var start := Time.get_ticks_usec()
	var hits := 0
	for index in PHYSICS_ROUNDS:
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

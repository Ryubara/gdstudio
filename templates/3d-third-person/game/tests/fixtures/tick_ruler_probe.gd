# On the clock: a probe that times a small ruler inside every physics tick (experiment, kit #1526).
class_name TickRulerProbe
extends Node3D
## Times a small `move_and_slide` and ray loop and a small GDScript loop in its own
## `_physics_process`, every tick, so a gate can divide the director's step by work timed in the
## same tick. `process_physics_priority` puts it before or after the director.

const ROUNDS := 60
const SPOT := Vector3(-400.0, 0.0, 400.0)

var physics_ms := PackedFloat64Array()
var script_ms := PackedFloat64Array()
var recording := false
var director: AiDirector
var steps := PackedFloat64Array()
var _body: CharacterBody3D
var _query := PhysicsRayQueryParameters3D.new()


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
	_query.exclude = [_body.get_rid()]


func _physics_process(_delta: float) -> void:
	if not recording:
		return
	if director != null:
		steps.append(director.last_step_usec)
	physics_ms.append(_physics_once())
	script_ms.append(_script_once())


func _physics_once() -> float:
	var space := get_world_3d().direct_space_state
	var origin := global_position + SPOT
	var start := Time.get_ticks_usec()
	for index in ROUNDS:
		var angle := TAU * index / 40.0
		_body.velocity = Vector3(cos(angle), -1.0, sin(angle)) * 4.0
		_body.move_and_slide()
		_query.from = _body.global_position + Vector3(0.0, 1.5, 0.0)
		_query.to = origin + Vector3(3.0, 1.0 + (index % 3) * 0.3, (index % 5) * 0.2 - 0.4)
		space.intersect_ray(_query)
	var spent := (Time.get_ticks_usec() - start) / 1000.0
	_body.global_position = origin
	_body.velocity = Vector3.ZERO
	return spent


func _script_once() -> float:
	var start := Time.get_ticks_usec()
	var total := Vector3.ZERO
	var list: Array[Vector3] = []
	var table := {}
	for index in 300:
		var point := Vector3(index * 0.1, sin(index * 0.3), index % 7)
		list.append(point)
		table[index % 37] = point
		total += point.normalized() * point.length_squared()
	for key: int in table:
		total -= table[key]
	list.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)
	return (Time.get_ticks_usec() - start + int(total.x) * 0) / 1000.0

class_name CorpseNudge
extends Node
## Nudges the dead bodies a character walks through out of its legs (kit #1339). The capsule never
## meets a ragdoll bone (`PhysicsLayers.CHARACTER_MASK` leaves out `RAGDOLL`), so the body walks,
## sprints and slides through a pile at full speed, with no step-up, vault or push on it; without
## this, the corpse's limbs stayed inside the legs and the hips.
##
## Each physics tick, after the body moved, a capsule round its lower body looks for limp bones
## (`RAGDOLL` only), and each bone it finds is given an impulse out of the legs: sideways from
## the way the body walks (a corpse in the way is brushed aside, never carried ahead) and straight
## out when it stands still. The speed a bone is given is capped (a share of the body's own, all
## of it sideways), so a sprint moves a pile and never throws it.
##
## Cosmetic: it runs on each machine from where the body is drawn, outside `Character.step`, so
## nothing of it is predicted, replayed or sent (ragdolls are each machine's own already).

## The character whose legs push (the parent when empty).
@export var body: Character
## Off: the legs pass through corpses as the capsule does.
@export var enabled := true
## How far round the capsule the legs reach, beyond its radius, in metres.
@export_range(0.0, 0.5, 0.01, "suffix:m") var reach := 0.25
## How high the legs reach from the feet, in metres (the hips; the arms do not push).
@export_range(0.2, 2.0, 0.05, "suffix:m") var height := 1.0
## The speed a bone deepest in the legs is pushed out at while the body stands or walks slowly, in
## metres a second; one at the edge of `reach` gets nothing.
@export_range(0.0, 5.0, 0.05, "suffix:m/s") var push_speed := 1.6
## The share of the body's own speed a bone in its way is pushed aside at, when that is more than
## `push_speed` (a sprint passes a body in a few ticks, so it must clear the legs that fast).
@export_range(0.0, 1.0, 0.05) var speed_share := 0.4
## How far ahead the legs look, in seconds of the body's walk: a bone is pushed before the legs
## reach it, not once they are in it.
@export_range(0.0, 0.5, 0.01, "suffix:s") var lead := 0.15
## The most bones one tick pushes (one query's results).
@export_range(1, 32, 1) var most_bones := 12

var _shape := CapsuleShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()


func _ready() -> void:
	if body == null:
		body = get_parent() as Character
	# After the body's own step (`Character._physics_process`, priority 0) and the player's input.
	process_physics_priority = 20
	_query.shape = _shape
	_query.collision_mask = PhysicsLayers.RAGDOLL
	_query.collide_with_areas = false


func _physics_process(_delta: float) -> void:
	if not enabled or body == null or not body.is_inside_tree():
		return
	if body.state == Character.State.DEAD:
		return
	nudge()


## Pushes the limp bones inside the legs out of them now; returns how many it pushed.
func nudge() -> int:
	var radius := body.tuning.radius + reach
	_shape.radius = radius
	_shape.height = maxf(height, radius * 2.0 + 0.01)
	var flat := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var walking := flat.length_squared() > 0.01
	var ahead := flat.normalized() if walking else Vector3.ZERO
	var feet := body.global_position + flat * lead
	_query.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (_shape.height / 2.0))
	var found := body.get_world_3d().direct_space_state.intersect_shape(_query, most_bones)
	var strongest := maxf(push_speed, flat.length() * speed_share)
	var pushed := 0
	for hit: Dictionary in found:
		var bone := hit.get("collider") as PhysicalBone3D
		if bone == null or not bone.is_simulating_physics():
			continue
		var out := bone.global_position - feet
		out.y = 0.0
		var depth := clampf(1.0 - out.length() / radius, 0.0, 1.0)
		if depth <= 0.0:
			continue
		var away := out
		if walking:
			# Sideways only: the side of the walk the bone lies on.
			away = out - ahead * out.dot(ahead)
			if away.length_squared() < 0.0001:
				away = ahead.cross(Vector3.UP)
		if away.length_squared() < 0.0001:
			away = Vector3.RIGHT
		away = away.normalized()
		var gain := strongest * depth - bone.linear_velocity.dot(away)
		if gain <= 0.0:
			continue
		bone.apply_central_impulse(away * gain * bone.mass)
		pushed += 1
	return pushed

class_name CharacterPeek
extends RefCounted
## The peek lean of a `Character` around cover (gdstudio #1400): the command's `lean_left` or
## `lean_right` tilts the upper body from the hips so the head and the shoulders go to that side
## while the feet and the pelvis stay, to see and shoot past a wall's edge showing less of the
## body. Not the gait's lean into its turns (`GaitLean`, a pose): this one is gameplay.
##
## It is part of the body's step, so a server steps it and a predicting client predicts it: the
## eye point (the camera's target, where a shot without a crosshair ray leaves from) moves with
## the lean, a shape on the body (`PeekShape`, a capsule along the bent spine from the shoulders
## to above the head) is what a shot meets outside the upright capsule, and the body walks no
## faster than `PeekTuning.move_speed` and turns to the view, as an aim turns it. Before a lean
## grows, the shape is swept out to the whole lean against what the body collides with, and the
## lean stops short of whatever is in the way (`room`), so the head never goes into a wall.
##
## A sprint, a slide, a vault, lying down, the air and death end it. Its step state is `amount`
## (`CharacterState.peek`); a puppet is shown a lean from the network (`show()`). The skeleton's
## bend is the `PeekLayer`'s, which reads `drawn()`.

## How far the body leans now, -1 (all the way left) to 1 (all the way right); 0 upright. A share
## of the whole lean's angle (`full_angle()`).
var amount := 0.0
## The share of a whole lean the room beside the body allows on the side it leans, 0 to 1 (1 when
## nothing is in the way). Found on each step that leans.
var room := 1.0

var _before := 0.0
var _probe := CapsuleShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var _shape: CollisionShape3D
var _shape_looked := false
# What the eye and the shape were last placed for (`place()`): a steady lean skips the fit, until
# the tuning it was placed with changes.
var _placed := Vector3(INF, INF, INF)
var _placed_tuning: PeekTuning


## The side `command` asks to lean: -1 left, 1 right, 0 neither (or both).
static func asked_side(command: PlayerCommand) -> int:
	if command.lean_left == command.lean_right:
		return 0
	return 1 if command.lean_right else -1


## True while the body leans (any amount).
func leaning() -> bool:
	return amount != 0.0


## The side the body leans to now: -1, 0 or 1.
func side() -> int:
	return signi(roundi(signf(amount)))


## True when `body` may lean on this tick: alive, on the ground, standing or crouched (when the
## tuning lets it), not sliding, vaulting, lying or asking to sprint on the move.
func allowed(body: Character) -> bool:
	var tuning := body.peek_tuning
	if tuning == null or not tuning.enabled or body.state == Character.State.DEAD:
		return false
	var command := body.last_command
	if command.sprint and not command.move.is_zero_approx():
		return false
	if body.crouching and not tuning.while_crouched:
		return false
	return (
		body._grounded
		and not body._slide.active
		and not body._prone.is_prone()
		and not body.vault_motion.is_active()
	)


## One tick of the lean, after the body moved: toward the side the command asks (or upright when
## it may not lean), held short of a wall, then the eye point and the shape are put where it
## leans. Costs nothing on a tick with no lean and none asked for.
func step(body: Character, delta: float) -> void:
	_before = amount
	if body.state == Character.State.DEAD:
		# A dead body lies in its ragdoll: the lean and its shape go at once.
		if amount != 0.0:
			reset()
			CharacterCapsule.fit(body)
		return
	var wanted := asked_side(body.last_command) if allowed(body) else 0
	if wanted == 0 and amount == 0.0:
		room = 1.0
		return
	var tuning := body.peek_tuning
	amount = move_toward(amount, float(wanted), delta / maxf(tuning.lean_time, 0.001))
	if amount != 0.0:
		room = _room(body, signf(amount))
		amount = signf(amount) * minf(absf(amount), room)
	# A steady lean (the same share, facing, eye height and tuning as last placed) has nothing to
	# move.
	if (
		tuning == _placed_tuning
		and Vector3(amount, body.facing, CharacterCapsule.eye_height(body)) == _placed
	):
		return
	CharacterCapsule.fit(body)


## Stands the lean up at once (a teleport, a death); the body fits its capsule afterwards.
func reset() -> void:
	amount = 0.0
	_before = 0.0
	room = 1.0


## The lean the skeleton shows now: between the last two steps by the physics interpolation, as
## the engine draws the body.
func drawn() -> float:
	return lerpf(_before, amount, clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0))


## Shows `value` (-1 to 1) on a body that is not stepped (a puppet, from the network): the eye
## point, the shape and the bend follow it at once.
func show(body: Character, value: float) -> void:
	value = clampf(value, -1.0, 1.0)
	if value == amount and value == _before:
		return
	amount = value
	_before = value
	CharacterCapsule.fit(body)


## The angle of a whole lean for `body` with its eye `eye` metres up, in radians: the tilt that
## puts the eye `side_offset` to the side, never more than `max_angle`.
func full_angle(body: Character, eye: float) -> float:
	var tuning := body.peek_tuning
	if tuning == null:
		return 0.0
	var bend := _bend(tuning, eye)
	if bend <= 0.001:
		return 0.0
	var reach := asin(clampf(tuning.side_offset / bend, 0.0, 1.0))
	var crouched := smoothstep(0.0, 1.0, body._crouch_amount)
	return minf(reach, deg_to_rad(lerpf(tuning.max_angle, tuning.crouch_max_angle, crouched)))


## How far the upper body is tilted now, in radians, positive to the right: the roll a weapon with
## no muzzle (a server's) gives its shot's start beside the eye (`Weapon`).
func roll(body: Character) -> float:
	if amount == 0.0:
		return 0.0
	return amount * full_angle(body, CharacterCapsule.eye_height(body))


## Where the eye goes from its upright place for a lean of `share` (-1 to 1), in the body's axes
## (the body's node is never turned; its model is): to the body's right and down a little as the
## bend tilts.
func eye_shift(body: Character, eye: float, share: float) -> Vector3:
	if share == 0.0 or body.peek_tuning == null:
		return Vector3.ZERO
	var angle := share * full_angle(body, eye)
	var bend := _bend(body.peek_tuning, eye)
	return right_of(body) * bend * sin(angle) + Vector3.DOWN * bend * (1.0 - cos(angle))


## The way to the right of the way `body` faces (flat, length 1).
static func right_of(body: Character) -> Vector3:
	return Vector3(-cos(body.facing), 0.0, sin(body.facing))


## The way `body` faces (flat, length 1).
static func forward_of(body: Character) -> Vector3:
	return Vector3(sin(body.facing), 0.0, cos(body.facing))


## Puts the eye point (`camera_target`) and the shape where the lean is, for the eye `eye` metres
## up (`CharacterCapsule.fit` calls it after it sizes the capsule).
func place(body: Character, camera_target: Node3D, eye: float) -> void:
	_placed = Vector3(amount, body.facing, eye)
	if _placed_tuning != body.peek_tuning:
		if _placed_tuning != null and _placed_tuning.changed.is_connected(_forget_placed):
			_placed_tuning.changed.disconnect(_forget_placed)
		_placed_tuning = body.peek_tuning
		if _placed_tuning != null:
			_placed_tuning.changed.connect(_forget_placed)
	var target := Vector3.UP * eye + eye_shift(body, eye, amount)
	if camera_target.position != target:
		camera_target.position = target
	var shape := _peek_shape(body)
	if shape == null:
		return
	var on := amount != 0.0 and body.peek_tuning != null
	if shape.disabled == on:
		shape.disabled = not on
	if on:
		# Written only when they change: a shape's setter rebuilds it in the physics server.
		var capsule := shape.shape as CapsuleShape3D
		var made := _capsule(body, eye, 0.0)
		if capsule.radius != made.x:
			capsule.radius = made.x
		if capsule.height != made.y:
			capsule.height = made.y
		var placed := _capsule_transform(body, eye, amount)
		if not shape.transform.is_equal_approx(placed):
			shape.transform = placed


## Saves the step state in `into` (`CharacterState.peek`).
func save_step_state(into: Array) -> void:
	into.resize(1)
	into[0] = amount


## Puts the step state back (the body fits its capsule and places the eye afterwards).
func load_step_state(from: Array) -> void:
	if from.size() >= 1:
		amount = from[0]
		_before = amount


# The bend's length, from the hips' pivot to the eye.
func _bend(tuning: PeekTuning, eye: float) -> float:
	return eye * (1.0 - tuning.pivot_share)


# The shape's radius and height, grown by `grow` metres all round.
func _capsule(body: Character, eye: float, grow: float) -> Vector2:
	var tuning := body.peek_tuning
	var bend := _bend(tuning, eye)
	var length := bend * (1.0 - tuning.shape_start) + tuning.shape_radius
	var radius := tuning.shape_radius + grow
	return Vector2(radius, length + radius * 2.0)


# The shape's place in the body's axes for a lean of `share`: along the bent spine, from
# `shape_start` up the bend to a radius past the eye.
func _capsule_transform(body: Character, eye: float, share: float) -> Transform3D:
	var tuning := body.peek_tuning
	var angle := share * full_angle(body, eye)
	var bend := _bend(tuning, eye)
	var tilt := Basis(forward_of(body), angle)
	var along := tilt * Vector3.UP
	var low := bend * tuning.shape_start
	var high := bend + tuning.shape_radius
	var pivot := Vector3.UP * eye * tuning.pivot_share
	return Transform3D(tilt, pivot + along * (low + high) * 0.5)


# The share of a whole lean to `toward` (-1 or 1) the body has room for: the shape (grown by the
# margin) is tried at the whole lean, and when that meets something the lean is halved toward the
# last free share a few times.
func _room(body: Character, toward: float) -> float:
	if not body.is_inside_tree():
		return 1.0
	var eye := CharacterCapsule.eye_height(body)
	if _free(body, eye, toward):
		return 1.0
	var low := 0.0
	var high := 1.0
	for _pass in 6:
		var middle := (low + high) * 0.5
		if _free(body, eye, toward * middle):
			low = middle
		else:
			high = middle
	return low


# True when the shape leaning `share` (grown by the margin) meets nothing the body collides with.
func _free(body: Character, eye: float, share: float) -> bool:
	var tuning := body.peek_tuning
	var made := _capsule(body, eye, tuning.wall_margin)
	_probe.radius = made.x
	_probe.height = made.y
	_query.shape = _probe
	_query.transform = body.global_transform * _capsule_transform(body, eye, share)
	_query.collision_mask = body.collision_mask
	_query.exclude = [body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_shape(_query, 1).is_empty()


func _forget_placed() -> void:
	_placed = Vector3(INF, INF, INF)


func _peek_shape(body: Character) -> CollisionShape3D:
	if not _shape_looked:
		_shape_looked = true
		_shape = body.get_node_or_null(^"PeekShape") as CollisionShape3D
	return _shape

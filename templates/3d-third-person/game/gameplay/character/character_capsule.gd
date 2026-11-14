class_name CharacterCapsule
extends RefCounted
## The size of a `Character`'s capsule and of its eye point (the camera's target), kept apart from
## the body's moves: how tall the capsule is as it crouches, slides or lies down, the room above it
## to stand up, and fitting the collision shape to all of it. Its functions are static and keep
## nothing: they read the body's tunings and its crouch, slide and prone stances, so the step's
## results are the body's alone. The body calls `fit()` whenever one of those changes.


## The height of `body`'s capsule now, in metres: the standing height, or less while it crouches,
## lies down or slides.
static func height(body: Character) -> float:
	var tuning := body.tuning
	var shrink := smoothstep(0.0, 1.0, body._crouch_amount)
	var crouched := minf(
		lerpf(tuning.height, crouch_height(body), shrink), body._slide.body_height(body)
	)
	if body.prone_tuning == null or not body._prone.is_prone():
		return crouched
	return lerpf(crouched, prone_height(body), body._prone.share())


## Sizes `body`'s capsule and its camera's target for the crouch, the slide, the prone stance and
## the peek lean: the capsule keeps its feet on the ground and loses height from the top.
static func fit(body: Character) -> void:
	var tuning := body.tuning
	var capsule := body._body.shape as CapsuleShape3D
	var tall := height(body)
	var lying := body._prone.share() if body.prone_tuning != null else 0.0
	var radius := lerpf(tuning.radius, prone_radius(body), lying) if lying > 0.0 else tuning.radius
	# A shape's setter rebuilds it in the physics server even for the same value, and a shape
	# node's place moves it there: written only when they change (a leaning body fits every tick).
	if capsule.radius != radius:
		capsule.radius = radius
	if capsule.height != tall:
		capsule.height = tall
	if body._body.position.y != tall / 2.0:
		body._body.position.y = tall / 2.0
	# The eye goes with a peek lean (`CharacterPeek`), and the lean's shape with it.
	body.peek_motion.place(body, body._camera_target, eye_height(body))


## The eye point's height above the feet now (the camera's target), upright: lower crouched,
## sliding and lying down.
static func eye_height(body: Character) -> float:
	var tuning := body.tuning
	var shrink := smoothstep(0.0, 1.0, body._crouch_amount)
	var eye := minf(
		lerpf(tuning.camera_height, tuning.crouch_camera_height, shrink),
		body._slide.camera_height(body)
	)
	var lying := body._prone.share() if body.prone_tuning != null else 0.0
	if lying > 0.0:
		eye = lerpf(eye, body.prone_tuning.camera_height, lying)
	return eye


## The shortest the crouched capsule can be: a capsule is at least two radii tall.
static func crouch_height(body: Character) -> float:
	var tuning := body.tuning
	return clampf(tuning.crouch_height, tuning.radius * 2.0 + 0.01, tuning.height)


## The lying capsule's radius (never wider than standing).
static func prone_radius(body: Character) -> float:
	return minf(body.prone_tuning.radius, body.tuning.radius)


## The lying capsule's height: at least two radii tall, never above the crouch.
static func prone_height(body: Character) -> float:
	return clampf(body.prone_tuning.height, prone_radius(body) * 2.0 + 0.01, crouch_height(body))


## True when nothing is above `body` that would stop it from standing up. `probe` is a shape the
## body keeps for the query.
static func has_room_to_stand(body: Character, probe: CapsuleShape3D) -> bool:
	var tuning := body.tuning
	# Geometry, not feel: a probe a little thinner and shorter than the standing capsule, lifted
	# off the floor, so touching a wall or the ground is not a ceiling.
	probe.radius = maxf(tuning.radius - 0.02, 0.05)
	probe.height = tuning.height - 0.12
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	var middle := body.global_position + Vector3.UP * (tuning.height / 2.0 + 0.06)
	query.transform = Transform3D(Basis.IDENTITY, middle)
	query.collision_mask = body.collision_mask
	query.exclude = [body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

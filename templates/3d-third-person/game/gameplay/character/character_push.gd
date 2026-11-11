class_name CharacterPush
extends RefCounted
## How a `Character` pushes the props it walks into (a `RigidBody3D`, a `PhysicsProp` with a
## `push_speed`), kept apart from the body's other moves. Its one function is static and keeps
## nothing: the push's step state (the slow push's speed cap and how long it still holds) stays on
## the body, in `CharacterState.FIELDS`, so the step's results are the body's alone.


## Pushes the props `body` slid into this tick, `before` being its velocity before the move. True
## when it is pushing one it walks at. A prop's share of the body's speed is what its mass allows
## (the tuning's `push_strength`, `push_mass`, `push_least_share`, `push_boost`), as an impulse
## along the contact. A prop with a `push_speed` is pushed at that speed and the body walks a
## little faster than it (`push_contact`), and it keeps counting as pushed for `push_hold` after
## the last touch.
static func push_props(body: Character, before: Vector3, delta: float) -> bool:
	var tuning := body.tuning
	var pushing := false
	var slow_push := false
	var flat := Vector3(before.x, 0.0, before.z)
	var cap := 0.0
	if flat.length() >= tuning.stand_speed:
		for index in body.get_slide_collision_count():
			var collision := body.get_slide_collision(index)
			var prop := collision.get_collider() as RigidBody3D
			if prop == null:
				continue
			var along := -collision.get_normal()
			along.y = 0.0
			if along.length_squared() < 0.0001:
				continue
			along = along.normalized()
			# A prop more than 60 degrees off the way the body walks is brushed past, not pushed.
			if along.dot(flat.normalized()) < 0.5:
				continue
			var share := (
				tuning.push_strength
				* clampf(tuning.push_mass / prop.mass, tuning.push_least_share, 1.0)
				* tuning.push_boost
			)
			var want := flat.length() * clampf(share, 0.0, 1.0)
			var physics_prop := prop as PhysicsProp
			var slow := physics_prop.push_speed if physics_prop != null else 0.0
			if slow > 0.0:
				want = slow
				var contact := slow * tuning.push_contact
				cap = contact if cap == 0.0 else minf(cap, contact)
				slow_push = true
			var gain := want - prop.linear_velocity.dot(along)
			# A frozen prop is an online client's copy: only the server's body moves the prop.
			if gain > 0.0 and not prop.freeze:
				prop.apply_central_impulse(along * gain * prop.mass)
			pushing = true
	if slow_push:
		body._push_hold = tuning.push_hold
		body._push_cap = cap
	else:
		body._push_hold = maxf(body._push_hold - delta, 0.0)
		if body._push_hold <= 0.0:
			body._push_cap = 0.0
	return pushing or body._push_hold > 0.0

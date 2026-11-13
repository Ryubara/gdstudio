class_name CharacterDeath
extends RefCounted
## How a `Character` dies and gets up again, kept apart from the body's moves: what dying lets go
## of (the stances, the timers, the aim), the limp ragdoll or the death clip, the tick of a dead
## body and getting up where it lies. Its functions are static and keep nothing: death is an event
## (`Character.die()`, `revive()`), not step state. The body's `die()` and `revive()` call them,
## and say the body's signals (`died`, `revived`, `prone_changed`, `aim_changed`).


## Kills `body` (`Character.die()`): it goes limp into its ragdoll, which keeps its momentum, or
## plays its death clip when the ragdoll declines; `shot` is the hit that killed, or null.
static func die(body: Character, shot: HitRecord) -> void:
	if body.state == Character.State.DEAD:
		return
	var momentum := body.velocity
	var viewer := body.controller.viewer_position() if body.controller != null else Vector3.INF
	var ragdoll_body := body.ragdoll_body
	body.died_by_clip = ragdoll_body != null and not ragdoll_body.can_start(viewer)
	body._wants_crouch = false
	if body._prone.is_prone():
		body._prone.reset()
		body.prone_changed.emit(false)
	body._fire_buffer = 0.0
	if body.weapon != null:
		body.weapon.cancel_reload()
		body.weapon.bursting = false
	body._action_lock = 0.0
	body._land_timer = 0.0
	body._jump_buffer = 0.0
	body._jump_held = false
	body._sprinting = false
	body._slide.reset()
	body.aim_held = false
	body.fire_held = false
	body.aim_amount = 0.0
	if body.aiming:
		body.aiming = false
		body.aim_changed.emit(false)
	body.velocity = Vector3.ZERO
	body._body.disabled = true
	body.state = Character.State.DEAD
	if Health.of(body) != null:
		Health.of(body).kill()
	body.ragdoll = true
	if ragdoll_body != null and not body.died_by_clip:
		ragdoll_body.start(momentum, viewer)
	body.died.emit()
	if shot != null:
		shot.killed = true
		body.hit_received.emit(shot)


## Gets `body` up where its ragdoll lies, facing the way its chest faces (`Character.revive()`).
static func revive(body: Character) -> void:
	if body.state != Character.State.DEAD:
		return
	var ragdoll_body := body.ragdoll_body
	if ragdoll_body != null and ragdoll_body.is_limp():
		var heading := ragdoll_body.facing()
		body.global_position = ground_below(body, ragdoll_body.hips())
		body.facing = atan2(heading.x, heading.z)
		body._present_facing()
		body.reset_physics_interpolation()
		ragdoll_body.stop()
	come_alive(body)


## Gets `body` up at `spot` (`Character.revive_at()`): it stands there at once, facing the way its
## ragdoll's chest faces, and the ragdoll's hold fades out from where the bones lie, so the pose
## blends toward the spot. A body that is not dead is put there too.
static func revive_at(body: Character, spot: Vector3) -> void:
	var ragdoll_body := body.ragdoll_body
	if body.state == Character.State.DEAD and ragdoll_body != null and ragdoll_body.is_limp():
		var heading := ragdoll_body.facing()
		body.facing = atan2(heading.x, heading.z)
		body._present_facing()
		ragdoll_body.stop()
	body.global_position = spot
	body.velocity = Vector3.ZERO
	body._fallen = false
	body.reset_physics_interpolation()
	if body.state == Character.State.DEAD:
		come_alive(body)


## One tick of a dead `body`: it stays where it died with its capsule off, the camera's target
## follows the hips, and a ragdoll that falls out of the map says `fell`.
static func dead_tick(body: Character) -> void:
	var ragdoll_body := body.ragdoll_body
	if ragdoll_body == null or not ragdoll_body.is_limp():
		return
	var hips := ragdoll_body.hips()
	if hips.y < body.tuning.fall_limit:
		body._fall_out()
		return
	body._camera_target.global_position = hips + Vector3.UP * body.tuning.dead_camera_rise


## Makes `body` alive again where it is: full health, its capsule on, standing still.
static func come_alive(body: Character) -> void:
	body.died_by_clip = false
	if Health.of(body) != null:
		Health.of(body).reset()
	body._body.disabled = false
	body.velocity = Vector3.ZERO
	body._fall_speed = 0.0
	body._was_airborne = false
	body.vault_motion.cancel(body)
	body._camera_target.position = Vector3.ZERO
	body._fit_body()
	body.state = Character.State.IDLE
	body.ragdoll = false
	body.revived.emit()


## The floor under `spot` (a ray down from a little above it), or `spot` itself over nothing.
static func ground_below(body: Character, spot: Vector3) -> Vector3:
	# Geometry: from just above the hips to well under the lowest a body can lie.
	var query := PhysicsRayQueryParameters3D.create(
		spot + Vector3.UP * 0.5, spot + Vector3.DOWN * 3.0, body.collision_mask, [body.get_rid()]
	)
	var found := body.get_world_3d().direct_space_state.intersect_ray(query)
	return found["position"] if not found.is_empty() else spot

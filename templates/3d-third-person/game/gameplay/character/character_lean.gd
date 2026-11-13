class_name CharacterLean
extends RefCounted
## The lean tick of a `Character`: the same tick as the full one for a body that walks or stands on
## the ground and asks for nothing but a push, a view, the aim and the trigger, with the modules
## that have nothing to do on it left out (the prone stance, the vault's probe, the slide, the
## crouch and the weapon's switch and reload), so the body ends the tick in exactly the state the
## full tick leaves it in (`test_character_lean.gd` steps both side by side and compares their
## snapshots).
##
## An AI's body takes it (`CharacterController.lean_step`, on in `AiController`): an AI walks far
## more ticks than it does anything else, and its body's step is what a crowd costs (gdstudio
## #1059), and a fighting AI aims and fires on it too (#1104). Any other body, a player's, a
## predicting client's or one a server steps for a player, never does. On any tick where one of
## those modules has something to do (a jump, reload, switch or use press, the aim going up or
## coming down this tick, crouch, prone or jump held, a slide or a vault running, a timer still
## counting, the body in the air) the body takes the full tick instead, so the lean tick decides
## nothing of its own.
##
## Its functions are static and keep nothing, like the body's other modules.


## True when the full tick would do nothing in the modules the lean tick leaves out, for `body`
## with its command of this tick already in `last_command`.
static func can_take(body: Character) -> bool:
	var command := body.last_command
	if (
		command.crouch
		or command.prone
		or command.jump
		or command.jump_pressed
		or command.interact_pressed
		or command.reload_pressed
		or command.next_weapon_pressed
		or command.previous_weapon_pressed
		or command.unarmed_pressed
		or command.melee_pressed
	):
		return false
	# A melee blow (gdstudio #1254), and the fire press of a melee weapon that throws one, take the
	# full tick for as long as the blow runs.
	var held := body.weapon
	if (
		held != null
		and (
			held.meleeing
			or (
				command.fire_pressed
				and held.definition != null
				and held.definition.kind == WeaponDef.Kind.MELEE
			)
		)
	):
		return false
	if (
		not body._grounded
		or body._action_lock > 0.0
		or body._jump_buffer > 0.0
		or body.crouching
		or body._crouch_amount > 0.0
	):
		return false
	if (
		(
			(command.aim or command.fire or command.fire_pressed or body._fire_buffer > 0.0)
			or (body.aiming or body.aim_amount > 0.0 or body.aim_held or body.fire_held)
		)
		and not _can_aim(body, command)
	):
		return false
	if body._prone.down or body._prone.amount > 0.0:
		return false
	if body._slide.active or body._slide.amount > 0.0:
		return false
	# A move made again (after a wall, see `move`) would ride a moving floor twice.
	if body.get_platform_velocity() != Vector3.ZERO:
		return false
	if not body.turn_motion.lets_lean(body, body._wish_direction()):
		return false
	var settings := body.vault_settings
	if settings != null:
		if body.vault_motion.is_active():
			return false
		# The automatic trigger probes on every sprinting tick.
		if command.sprint and settings.trigger != VaultSettings.Trigger.PRESS_JUMP:
			return false
	return true


# A fight on its feet (gdstudio #1104): the aim held or let go and the trigger pulled, with the aim
# already as the command wants it (no `aim_changed` on this tick) and a weapon in the hands, so the
# full tick's aim only moves `aim_amount` and copies the two held buttons, and its trigger only
# counts the fire buffer and pulls.
static func _can_aim(body: Character, command: PlayerCommand) -> bool:
	return body.weapon != null and body.aiming == (command.aim or command.fire)


## One lean tick of `body` (only when `can_take(body)`): what `Character._move()` does on such a
## tick, in its order, without the modules that would find nothing to do, and the walk's steering
## and state with the branches for crouch, prone, a hit and the air left out.
static func move(body: Character, delta: float) -> void:
	var tuning := body.tuning
	# The timers: nothing locks the body and no jump is buffered (both at 0), and it is on the
	# ground, so its grace after leaving it is full.
	body._action_lock = 0.0
	body._land_timer = maxf(body._land_timer - delta, 0.0)
	body._jump_buffer = 0.0
	body._coyote = tuning.coyote_time
	# The prone stance on the ground, up: only its air time moves (to 0).
	body._prone._air = 0.0
	if body.vault_settings != null:
		body.vault_motion.tick_cooldown(delta)
	# The slide, not running and not starting (no crouch): its timers count and its landing clears.
	var slide := body._slide
	slide.cooldown = maxf(slide.cooldown - delta, 0.0)
	slide.boost_cooldown = maxf(slide.boost_cooldown - delta, 0.0)
	slide.landed = false
	# The crouch: let go of, with nothing to stand up from; the aim: held as the command holds it
	# (it neither goes up nor comes down this tick) and the arm on its way to it.
	body._wants_crouch = false
	if body.weapon != null:
		body.fire_held = body.last_command.fire
		body.aim_held = body.last_command.aim
	body.aim_amount = move_toward(
		body.aim_amount, 1.0 if body.aiming else 0.0, delta / maxf(tuning.aim_pose_time, 0.001)
	)
	var wish := body._wish_direction()
	_steer(body, wish, delta)
	_vertical(body)
	var before := body.velocity
	var ticks := roundf(delta / body.get_physics_process_delta_time())
	# The step climber lifts the body only over a steep face in its way, which the move meets as a
	# wall: so the move goes first, and only when it met a wall is it taken back and made again
	# after the climber, as the full tick makes it (on open ground the climber's test, a fifth of
	# the walk's cost, finds nothing every tick).
	var start := body.global_transform
	body.velocity *= ticks
	body.move_and_slide()
	body.velocity /= ticks
	if body.is_on_wall():
		body.global_transform = start
		body.velocity = before
		body._climb(delta)
		body.velocity *= ticks
		body.move_and_slide()
		body.velocity /= ticks
	body._grounded = body.is_on_floor()
	body._pushing = CharacterPush.push_props(body, before, delta)
	if body._grounded and body._was_airborne:
		body._after_move(wish, delta)
	else:
		_after_move(body, wish)
	_trigger(body, delta)


# `Character._steer()` and `_target_speed()` on the ground, up, unlocked, not crouched:
# the same numbers in the same order.
static func _steer(body: Character, wish: Vector3, delta: float) -> void:
	var tuning := body.tuning
	var flat := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var strength := wish.length()
	var goal := Vector3.ZERO
	var rate := tuning.deceleration
	if strength > 0.0:
		var command := body.last_command
		var speed := tuning.run_speed * strength
		if command.sprint and not body.aiming:
			speed = tuning.sprint_speed
		elif command.walk or strength < tuning.walk_below_push:
			speed = tuning.walk_speed * maxf(strength, tuning.least_walk_share)
		if body.aiming:
			speed = minf(speed, tuning.walk_speed * tuning.aim_walk_cap) * tuning.aim_move_scale
		if body._push_cap > 0.0:
			speed = minf(speed, body._push_cap)
		goal = wish.normalized() * speed
		rate = tuning.acceleration
	flat = flat.move_toward(goal, rate * delta)
	body.velocity.x = flat.x
	body.velocity.z = flat.z
	if body.aiming:
		# Aiming turns the body to the view's heading, however it walks.
		body.facing = lerp_angle(
			body.facing, body.view_yaw + PI, clampf(tuning.aim_turn_speed * delta, 0.0, 1.0)
		)
		body._present_facing()
	elif strength > 0.0:
		body.facing = lerp_angle(
			body.facing, atan2(wish.x, wish.z), clampf(tuning.turn_speed * delta, 0.0, 1.0)
		)
		body._present_facing()


# `Character._vertical()` on the ground with no jump asked for or held: no gravity, no take-off.
static func _vertical(body: Character) -> void:
	if body.velocity.y < 0.0:
		body.velocity.y = 0.0
	if body._jump_held and body.velocity.y > 0.0:
		var tuning := body.tuning
		body.velocity.y = minf(body.velocity.y, tuning.jump_speed() * tuning.short_jump_scale)
		body._jump_held = false
	if body.velocity.y <= 0.0:
		body._jump_held = false
	body.floor_snap_length = body.tuning.snap_length if body.velocity.y <= 0.0 else 0.0


# `Character._after_move()` and `_pick_state()` for a body that did not just land, with nothing
# locking it, up, not crouched or sliding.
static func _after_move(body: Character, wish: Vector3) -> void:
	var tuning := body.tuning
	var grounded := body._grounded
	body._was_airborne = not grounded
	var speed := body.ground_speed()
	body._sprinting = (
		grounded and not body.aiming and body.last_command.sprint and speed > tuning.run_speed
	)
	var picked := Character.State.IDLE
	if not grounded:
		picked = Character.State.JUMP if body.velocity.y > 0.0 else Character.State.FALL
	elif body._land_timer > 0.0:
		picked = Character.State.LAND
	elif body._pushing and not wish.is_zero_approx():
		picked = Character.State.PUSH
	elif speed >= tuning.stand_speed:
		picked = (
			Character.State.WALK
			if speed <= tuning.walk_speed + tuning.run_above_walk
			else Character.State.RUN
		)
	body.state = picked


# `Character._use_weapon()` with no switch and no reload asked for and the body up: the fire buffer
# counts, a press fills it, and the shot leaves once the aim is up; the trigger held on an automatic
# weapon pulls on the ticks it is held (`Character._trigger_held`), and a burst under way pulls
# until it ends.
static func _trigger(body: Character, delta: float) -> void:
	body._fire_buffer = maxf(body._fire_buffer - delta, 0.0)
	var weapon := body.weapon
	if weapon == null:
		return
	var command := body.last_command
	weapon.spread_share = 1.0
	if body.fire_press(command):
		body._fire_buffer = body.tuning.fire_buffer_time
	var burst := weapon.bursting
	var wanted := body._fire_buffer > 0.0 or body._trigger_held(command) or burst
	if wanted and body.aiming and body.aim_amount >= body.tuning.shot_aim_amount:
		if weapon.pull(body._aim_origin(), body._aim_direction()) != Weapon.Pull.BUSY and not burst:
			body._fire_buffer = 0.0
	elif burst:
		weapon.bursting = false

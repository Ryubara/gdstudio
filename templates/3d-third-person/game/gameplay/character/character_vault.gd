class_name CharacterVault
extends RefCounted
## The vault and the mantle of a `Character`, inside its step: when the command asks for one (a
## jump press, or a sprint into the obstacle, as `VaultSettings.trigger` says) it asks a
## `VaultProbe` for a plan, and while a plan runs it moves the body along it, tick by tick, by the
## plan's numbers alone (the engine's sliding is off for the crossing; the probe found room for the
## whole path first). Only an obstacle with a `Vaultable` is ever crossed.
##
## The capsule goes up over the top, so it is never inside the obstacle. A vault timed by a
## `VaultClip` (`VaultSettings.low_clip`, `high_clip`) shows something else: the clip carries the
## body's rise and fall itself, so the model and the camera's target are held where the clip's
## root belongs (`VaultPlan.root_at()`: level, forward through the clip's contact places, lifted
## by the difference to the clip's reference height), `model_offset()` away from the capsule:
## the camera's target here, in the step, and the model by `VaultAnimation` on each drawn frame.
## The two meet at the start and at the landing.
##
## Everything the next tick reads is in `save_step_state()`, so a body put back with
## `Character.restore()` crosses on the same path. The clip is the animation's business: it reads
## `plan`, `clip()` and the obstacle's clip overrides from here.

## A vault or a mantle began: the body follows `plan` until it ends, in the state `VAULT` or
## `MANTLE` (the animation plays its clip from this).
signal started(plan: VaultPlan)

## The plan being followed (or the last one, once it ended). Its kind is `NONE` while there is none.
var plan := VaultPlan.new()
## Seconds into the plan.
var elapsed := 0.0
## Seconds until the automatic trigger may start the next crossing.
var cooldown := 0.0
## The last refusal of a probe, for a test or a debug overlay (not step state).
var last_refusal: StringName = &""

# How far the camera's target is held from its own place now.
var _camera_offset := Vector3.ZERO


## True while a crossing moves the body.
func is_active() -> bool:
	return plan.is_valid() and elapsed < plan.duration


## The share (0 to 1) of the crossing done.
func progress() -> float:
	return clampf(elapsed / plan.duration, 0.0, 1.0) if plan.duration > 0.0 else 1.0


## Seconds the running crossing takes.
func duration() -> float:
	return plan.duration


## What the running vault's clip was keyed on (of `settings`), or null: a mantle, a vault timed
## by the settings' shares, or none.
func clip(settings: VaultSettings) -> VaultClip:
	if settings == null or not plan.has_clip_timing():
		return null
	return settings.clip_for(plan.high)


## Where the model's root is from the capsule's feet `share` (0 to 1) of the way through the
## crossing (world axes): zero outside a vault timed by a clip, and at its start and landing.
func model_offset(settings: VaultSettings, share: float) -> Vector3:
	var timing := clip(settings)
	if timing == null or not is_active():
		return Vector3.ZERO
	return plan.root_at(timing, share) - plan.position_at(share)


## One tick of `body`'s vault, called at the top of its living step: starts a crossing when its
## command asks and the probe finds one, and moves the body along the running one. True while a
## crossing moves the body (the rest of the body's tick is skipped). Reads and writes the body's
## step members as one of its parts.
func drive(body: Character, delta: float) -> bool:
	var settings := body.vault_settings
	if settings == null:
		return false
	tick_cooldown(delta)
	# Something else took the body (it died and got up, a hit threw it): the crossing is over.
	if is_active() and body.state != Character.State.VAULT and body.state != Character.State.MANTLE:
		cancel(body)
	if not is_active():
		if not body._grounded or body._action_lock > 0.0:
			return false
		if body._prone.is_prone() or body._slide.active:
			return false
		var direction := body._wish_direction()
		if direction.is_zero_approx():
			direction = Vector3.BACK.rotated(Vector3.UP, body.facing)
		var tuning := body.tuning
		var asked := body._jump_buffer > 0.0
		if not try_start(
			body, settings, body.last_command, asked, direction, tuning.radius, tuning.height
		):
			return false
		_begin(body, settings)
	tick(body, settings, delta)
	_lift_camera(body, model_offset(settings, progress()))
	body.aim_amount = move_toward(
		body.aim_amount, 0.0, delta / maxf(body.tuning.aim_pose_time, 0.001)
	)
	return true


## Starts a crossing when `command` asks for one and the probe finds one. `wants_jump` is the
## body's buffered jump press; `direction` is where it is going (or facing, standing still).
## True when a crossing started.
func try_start(
	body: CharacterBody3D,
	settings: VaultSettings,
	command: PlayerCommand,
	wants_jump: bool,
	direction: Vector3,
	radius: float,
	height: float
) -> bool:
	if settings == null or is_active():
		return false
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	if not _asked(settings, command, wants_jump, speed):
		return false
	var found := VaultProbe.measure(
		body, body.global_position, direction, radius, height, speed, settings
	)
	last_refusal = found.refusal
	if not found.is_valid():
		return false
	plan = found
	elapsed = 0.0
	return true


## Moves the body one tick along the plan. At the end it leaves the body on the landing (or the
## top) with the vault's exit speed, and starts the cooldown.
func tick(body: CharacterBody3D, settings: VaultSettings, delta: float) -> void:
	elapsed = minf(elapsed + delta, plan.duration)
	body.global_position = plan.position_at(progress())
	body.velocity = Vector3.ZERO
	if elapsed >= plan.duration:
		_finish(body, settings)


## Counts the cooldown down; called every tick of a living body.
func tick_cooldown(delta: float) -> void:
	cooldown = maxf(cooldown - delta, 0.0)


## Ends a crossing at once (the body was put somewhere else, got up again); with `body`, its
## model and camera target go back onto the capsule.
func cancel(body: Character = null) -> void:
	plan = VaultPlan.new()
	elapsed = 0.0
	if body != null:
		_lift_camera(body, Vector3.ZERO)
		VaultAnimation.release(body.model)


## What the next tick reads, as plain values (`CharacterState.vault`).
func save_step_state(into: Array) -> void:
	into.clear()
	into.append(elapsed)
	into.append(cooldown)
	into.append(plan.to_array())


## Puts back what `save_step_state()` kept; an empty array is no crossing.
func load_step_state(kept: Array) -> void:
	if kept.size() < 3:
		cancel()
		cooldown = 0.0
		return
	elapsed = kept[0]
	cooldown = kept[1]
	plan = VaultPlan.new().from_array(kept[2])


# The body turns square to the face, lets go of the jump and (with `drop_aim`) of the aim, and
# says the crossing began.
func _begin(body: Character, settings: VaultSettings) -> void:
	body._jump_buffer = 0.0
	body._coyote = 0.0
	body.facing = atan2(plan.forward.x, plan.forward.z)
	body._present_facing()
	if settings.drop_aim:
		body._fire_buffer = 0.0
		body.aim_held = false
		body.fire_held = false
		if body.aiming:
			body.aiming = false
			body.aim_changed.emit(false)
	var vaulting := plan.kind == VaultPlan.Kind.VAULT
	body.state = Character.State.VAULT if vaulting else Character.State.MANTLE
	started.emit(plan)


# Holds the camera's target `offset` from its own place over the capsule, so the view follows the
# body that is drawn (level, where the clip's root is) and not the capsule's way over the top.
# The model itself is held there by the animation, on every drawn frame (`VaultAnimation`).
func _lift_camera(body: Character, offset: Vector3) -> void:
	if offset == _camera_offset:
		return
	_camera_offset = offset
	CharacterCapsule.fit(body)
	var target := body._camera_target
	target.position = Vector3(offset.x, target.position.y + offset.y, offset.z)


func _asked(
	settings: VaultSettings, command: PlayerCommand, wants_jump: bool, speed: float
) -> bool:
	var by_jump := wants_jump and settings.trigger != VaultSettings.Trigger.AUTO_ON_SPRINT
	# The cooldown holds only the automatic trigger: a press is meant, and one right after a landing
	# chains the next wall.
	var by_sprint := (
		settings.trigger != VaultSettings.Trigger.PRESS_JUMP
		and cooldown <= 0.0
		and command.sprint
		and not command.move.is_zero_approx()
		and speed >= settings.auto_min_speed
	)
	return by_jump or by_sprint


func _finish(body: CharacterBody3D, settings: VaultSettings) -> void:
	if plan.kind == VaultPlan.Kind.VAULT:
		var points := plan.points
		var last := points[points.size() - 1] - points[points.size() - 2]
		var flat := Vector3(last.x, 0.0, last.z)
		var pace := _crossing_pace()
		body.velocity = flat.normalized() * pace * settings.exit_speed_share
	cooldown = settings.cooldown


# The crossing's average speed across, m/s.
func _crossing_pace() -> float:
	var total := 0.0
	for index in range(1, plan.points.size()):
		var step := plan.points[index] - plan.points[index - 1]
		total += Vector2(step.x, step.z).length()
	return total / plan.duration if plan.duration > 0.0 else 0.0

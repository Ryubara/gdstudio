class_name CharacterVault
extends RefCounted
## The vault and the mantle of a `Character`, inside its step: when the command asks for one (a
## jump press, or a sprint into the obstacle, as `VaultSettings.trigger` says) it asks a
## `VaultProbe` for a plan, and while a plan runs it moves the body along it, tick by tick, by the
## plan's numbers alone (the engine's sliding is off for the crossing; the probe found room for the
## whole path first). Only an obstacle with a `Vaultable` is ever crossed.
##
## Everything the next tick reads is in `save_step_state()`, so a body put back with
## `Character.restore()` crosses on the same path. The clip is the animation's business: it reads
## `plan`, `duration()` and the obstacle's clip overrides from here.

## The plan being followed (or the last one, once it ended). Its kind is `NONE` while there is none.
var plan := VaultPlan.new()
## Seconds into the plan.
var elapsed := 0.0
## Seconds until the next crossing may start.
var cooldown := 0.0
## The last refusal of a probe, for a test or a debug overlay (not step state).
var last_refusal: StringName = &""


## True while a crossing moves the body.
func is_active() -> bool:
	return plan.is_valid() and elapsed < plan.duration


## The share (0 to 1) of the crossing done.
func progress() -> float:
	return clampf(elapsed / plan.duration, 0.0, 1.0) if plan.duration > 0.0 else 1.0


## Seconds the running crossing takes.
func duration() -> float:
	return plan.duration


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
	if settings == null or cooldown > 0.0 or is_active():
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


## Ends a crossing at once (the body died, was put somewhere else).
func cancel() -> void:
	plan = VaultPlan.new()
	elapsed = 0.0


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


func _asked(
	settings: VaultSettings, command: PlayerCommand, wants_jump: bool, speed: float
) -> bool:
	var by_jump := wants_jump and settings.trigger != VaultSettings.Trigger.AUTO_ON_SPRINT
	var by_sprint := (
		settings.trigger != VaultSettings.Trigger.PRESS_JUMP
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

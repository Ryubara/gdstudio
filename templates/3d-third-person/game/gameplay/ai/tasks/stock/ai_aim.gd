class_name AiAim
extends RefCounted
## The aim model of an AI with a ranged weapon (Deadnight's fitted model, the research for #882
## section 1.4), shared by `AiAttack` and `AiTakeCover`'s peeks:
##
## - **Reaction floor.** No shot sooner than `AiProfile.REACTION_FLOOR` (0.2 s) after it starts on
##   a target (or switches to another).
## - **A spring-limited turn.** The aim turns onto the target at most the profile's `aim_speed`.
## - **Tracking noise** off the aim, `noise_degrees * (1 - accuracy)` at first and shrinking while
##   the aim stays on the target (`settle_seconds`); misses come from where the shot goes, not from
##   dice on the hit.
## - **The trigger.** Bursts of the profile's `burst_size` shots `fire_interval` apart, then a rest;
##   only at a target believed and seen now, never through a friend (`friend_in_line_of_fire`)
##   and never at one it may not hurt (`AiFactions.can_hurt`); an empty magazine is reloaded, and
##   an empty gun with nothing to load says `DRY`.
##
## It writes only the action and look channels of the task's controller.

## What one step did.
enum Shot { AIMING, FIRED, HELD, RELOADING, DRY, UNSEEN }

## The aim turned onto the target (where the gun points before the noise).
var aim := Vector3.ZERO
## Seconds the aim has stayed within the fire cone.
var on_target := 0.0
## Seconds since it started on this target.
var on_this := 0.0
## Shots fired (a test reads them), and why the trigger was last held back.
var shots := 0
var held_by := ""

var _target_id := 0
var _gap := 0.0
var _rest := 0.0
var _in_burst := 0
var _rng := RandomNumberGenerator.new()


func _init(seed_value := 0) -> void:
	_rng.seed = seed_value


## Forgets the target (a new one starts at the reaction floor again).
func reset() -> void:
	_target_id = 0
	on_target = 0.0
	on_this = 0.0
	_in_burst = 0
	_rest = 0.0
	_gap = 0.0


## One step of `delta` seconds at `belief` for `task`: turns the aim, adds the noise, pulls the
## trigger when it may. Returns what it did (`Shot`).
func step(
	task: AiStockTask,
	belief: AiBelief,
	delta: float,
	fire_cone_degrees: float,
	noise_degrees: float,
	settle_seconds: float
) -> Shot:
	var controller := task.controller
	var body := task.body()
	var profile := task.run_profile()
	if controller == null or body == null or profile == null:
		return Shot.HELD
	controller.fire = false
	controller.reload = false
	if belief == null or not belief.can_fire_at():
		controller.aim = false
		return Shot.UNSEEN
	if belief.entity_id != _target_id:
		reset()
		_target_id = belief.entity_id
	on_this += delta
	var eye := body.global_position + Vector3.UP * 1.55
	var point := belief.last_position + Vector3.UP * AiStockTask.CHEST
	var wanted := (point - eye).normalized()
	if aim == Vector3.ZERO:
		aim = Vector3.BACK.rotated(Vector3.UP, body.facing)
	aim = _turn(aim, wanted, deg_to_rad(profile.aim_speed) * delta)
	var error := rad_to_deg(aim.angle_to(wanted))
	on_target = on_target + delta if error <= fire_cone_degrees else 0.0
	var spread := noise_degrees * (1.0 - profile.accuracy)
	spread *= exp(-on_target / maxf(settle_seconds, 0.01))
	controller.look_direction = _jitter(aim, deg_to_rad(spread))
	controller.aim = true
	return _trigger(task, body, belief, point, error, fire_cone_degrees, delta)


# The trigger once the aim is set: a reload, a dry gun, a rest, a held shot or a pull.
func _trigger(
	task: AiStockTask,
	body: AiCharacter,
	belief: AiBelief,
	point: Vector3,
	error: float,
	cone: float,
	delta: float
) -> Shot:
	var controller := task.controller
	var weapon := body.weapon
	if weapon == null or weapon.definition == null:
		return Shot.HELD
	if weapon.is_reloading():
		return Shot.RELOADING
	var magazine: Variant = weapon.magazine_size
	if magazine != null and magazine > 0 and int(weapon.ammo) <= 0:
		controller.reload = weapon.can_reload()
		return Shot.RELOADING if controller.reload else Shot.DRY
	_gap -= delta
	if _rest > 0.0:
		_rest -= delta
		held_by = "rest"
		return Shot.AIMING
	var ready := _gap <= 0.0 and weapon.can_fire()
	if not ready or not _may_fire(task, body, belief, point, error, cone):
		return Shot.AIMING
	var profile := task.run_profile()
	controller.fire = true
	shots += 1
	_in_burst += 1
	_gap = profile.fire_interval
	if _in_burst >= profile.burst_size:
		_in_burst = 0
		_rest = profile.fire_interval * 2.0
	return Shot.FIRED


func _may_fire(
	task: AiStockTask,
	body: AiCharacter,
	belief: AiBelief,
	point: Vector3,
	error: float,
	cone: float
) -> bool:
	if on_this < AiProfile.REACTION_FLOOR:
		held_by = "reaction"
		return false
	if error > cone:
		held_by = "turning"
		return false
	var victim := belief.entity()
	if victim == null or not AiFactions.can_hurt(body, victim):
		held_by = "may not hurt"
		return false
	var senses := body.senses as AiSenses
	if senses != null and senses.friend_in_line_of_fire(point) != null:
		held_by = "friend in the way"
		return false
	held_by = ""
	return task != null


# Turns `from` toward `to` by at most `limit` radians.
static func _turn(from: Vector3, to: Vector3, limit: float) -> Vector3:
	var angle := from.angle_to(to)
	if angle <= limit or angle < 0.0001:
		return to
	var axis := from.cross(to)
	if axis.length_squared() < 0.000001:
		axis = Vector3.UP
	return from.rotated(axis.normalized(), limit).normalized()


func _jitter(direction: Vector3, spread: float) -> Vector3:
	if spread <= 0.0:
		return direction
	var side := direction.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(direction).normalized()
	var angle := spread * sqrt(_rng.randf())
	var around := _rng.randf() * TAU
	return direction.rotated(side, sin(around) * angle).rotated(up, cos(around) * angle)

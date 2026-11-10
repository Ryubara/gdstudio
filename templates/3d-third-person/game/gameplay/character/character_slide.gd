class_name CharacterSlide
extends RefCounted
## The slide of a `Character`: running fast (a sprint) and pressing crouch drops the body low, it
## keeps its momentum and slows by friction, speeds up down a slope and slows up one, steers a
## little, and stands (or crouches, or stays low under a ceiling) when it ends. A jump out of a
## slide keeps the speed in the air. Every number is in the Slide group of `CharacterTuning`.
##
## It is part of the command-driven step: the character calls it from `step()` and it reads only
## the command (the crouch bit, the push, sprint and jump), the body and the tuning, so a server,
## a bot or a test slides a body by sending crouch at speed. Its step state is `FIELDS`, saved in
## `CharacterState.slide` by `save_step_state()` and put back by `load_step_state()`.

## The members a snapshot copies by name, in this order.
const FIELDS: Array[StringName] = [
	&"active",
	&"time",
	&"amount",
	&"cooldown",
	&"boost_cooldown",
	&"carry",
	&"landed",
]

## True while the body slides.
var active := false
## Seconds since the slide started.
var time := 0.0
## How far the body is down into the slide pose, 0 (standing) to 1 (at `slide_height`).
var amount := 0.0
## Seconds until another slide may start.
var cooldown := 0.0
## Seconds until a slide gets its entry boost again.
var boost_cooldown := 0.0
## The ground speed a jump out of the slide (or a slide off an edge) carries in the air, m/s; 0
## when there is none. It fades by `slide_jump_air_drag` and ends on landing.
var carry := 0.0
## The body touched the ground on the last tick (a slide may start on landing).
var landed := false
var _probe := CapsuleShape3D.new()


## Copies the step state into `into` (cleared first).
func save_step_state(into: Array) -> void:
	into.resize(FIELDS.size())
	for index in FIELDS.size():
		into[index] = get(FIELDS[index])


## Puts the step state back from `from` (a `save_step_state()`); an empty array leaves no slide.
func load_step_state(from: Array) -> void:
	if from.size() != FIELDS.size():
		reset()
		return
	for index in FIELDS.size():
		set(FIELDS[index], from[index])


## No slide, no cooldown, no carried speed: a body that died, came alive or was put somewhere.
func reset() -> void:
	active = false
	time = 0.0
	amount = 0.0
	cooldown = 0.0
	boost_cooldown = 0.0
	carry = 0.0
	landed = false


## The first part of a tick, before the crouch: counts the timers, ends a slide that should end
## and starts one when the crouch was just pressed (or is held on landing) at speed. `crouch_was`
## is the crouch bit of the tick before; `coyote_left` the seconds of grace the body has left
## after leaving the ground (a slide off an edge ends when they run out); `locked` is true while
## something holds the body still (a hit, using a door), which ends a slide and starts none.
func begin_tick(
	body: Character, crouch_was: bool, coyote_left: float, locked: bool, delta: float
) -> void:
	var tuning := body.tuning
	cooldown = maxf(cooldown - delta, 0.0)
	boost_cooldown = maxf(boost_cooldown - delta, 0.0)
	var command := body.last_command
	if active:
		time += delta
		var flew := not body.is_on_floor() and coyote_left <= 0.0
		if locked or flew or _should_end(body, command):
			end(body)
	elif tuning.slide_enabled and not locked and _may_start(body, command, crouch_was):
		_start(body)
	landed = false
	var drop := delta / maxf(tuning.slide_drop_time, 0.001)
	amount = move_toward(amount, 1.0 if active else 0.0, drop)


## Steers the sliding body for one tick in place of the walk: friction, the slope's pull, a
## little steering toward the push, and the facing along the slide (or to the view while it
## aims). The character shows the facing on its model.
func steer(body: Character, wish: Vector3, delta: float) -> void:
	var tuning := body.tuning
	var flat := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var speed := flat.length()
	var heading := flat / speed if speed > 0.0001 else _facing_forward(body)
	if body.is_on_floor():
		var pull := _slope_pull(body)
		var friction := tuning.slide_friction + tuning.slide_drag * speed
		if pull.dot(heading) > 0.0:
			friction *= tuning.slide_downhill_friction
		flat = heading * speed + pull * delta
		speed = flat.length()
		heading = flat / speed if speed > 0.0001 else heading
		speed = maxf(speed - friction * delta, 0.0)
	if not wish.is_zero_approx():
		var turn := heading.signed_angle_to(wish.normalized(), Vector3.UP)
		var most := tuning.slide_turn_rate * delta
		heading = heading.rotated(Vector3.UP, clampf(turn, -most, most))
	speed = minf(speed, tuning.slide_max_speed)
	# Under a gap too low to crouch in, the slide keeps going until there is room.
	if speed < tuning.slide_exit_speed and not has_room_for(body, crouch_height(body.tuning)):
		speed = tuning.slide_exit_speed + 0.01
	body.velocity.x = heading.x * speed
	body.velocity.z = heading.z * speed
	var look := body.view_yaw + PI if body.aiming else atan2(heading.x, heading.z)
	var rate := tuning.aim_turn_speed if body.aiming else tuning.turn_speed
	body.facing = lerp_angle(body.facing, look, clampf(rate * delta, 0.0, 1.0))


## After the body moved: a slide that hit something and slowed under the exit speed ends.
func after_move(body: Character, touched_down: bool) -> void:
	landed = touched_down
	if touched_down and not active:
		carry = 0.0
	if active and body.ground_speed() < body.tuning.slide_exit_speed - 0.001:
		if has_room_for(body, crouch_height(body.tuning)):
			end(body)


## The body jumps out of the slide: the slide ends, the speed is kept (up to
## `slide_jump_max_speed`) and carried through the air. Returns the jump's take-off speed.
func jump(body: Character) -> float:
	var tuning := body.tuning
	var flat := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var speed := minf(flat.length() + tuning.slide_jump_boost, tuning.slide_jump_max_speed)
	if flat.length() > 0.0001:
		flat = flat.normalized() * speed
		body.velocity.x = flat.x
		body.velocity.z = flat.z
	end(body)
	carry = speed
	return tuning.jump_speed() * sqrt(tuning.slide_jump_height_scale)


## The goal of the air steering while a slide's speed is carried: the push's direction (or the way
## the body flies) at the carried speed when that is more than `goal`'s. The carried speed fades.
func air_goal(body: Character, wish: Vector3, goal: Vector3, delta: float) -> Vector3:
	if carry <= 0.0:
		return goal
	carry = maxf(carry - body.tuning.slide_jump_air_drag * delta, 0.0)
	if carry <= goal.length():
		return goal
	var flat := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var way := wish.normalized() if not wish.is_zero_approx() else flat.normalized()
	return way * carry


## Ends the slide now: the cooldown starts. A ceiling over the body is the crouch's business (the
## character stays crouched while it has no room to stand).
func end(body: Character) -> void:
	if not active:
		return
	active = false
	cooldown = body.tuning.slide_cooldown
	if not body.is_on_floor():
		carry = maxf(carry, body.ground_speed())


## The capsule's height now for the slide: the standing height going down to `slide_height` as
## the body drops into the slide.
func body_height(tuning: CharacterTuning) -> float:
	var low := clampf(tuning.slide_height, tuning.radius * 2.0 + 0.01, tuning.height)
	return lerpf(tuning.height, low, smoothstep(0.0, 1.0, amount))


## The capsule's height fully crouched, as the character sizes it (at least two radii).
static func crouch_height(tuning: CharacterTuning) -> float:
	return clampf(tuning.crouch_height, tuning.radius * 2.0 + 0.01, tuning.height)


## The camera's target height for the slide, the same way.
func camera_height(tuning: CharacterTuning) -> float:
	return lerpf(tuning.camera_height, tuning.slide_camera_height, smoothstep(0.0, 1.0, amount))


## True when a capsule `height` tall (a little thinner, lifted off the floor) fits where the body
## stands: the room a slide needs to end in a crouch.
func has_room_for(body: Character, height: float) -> bool:
	var tuning := body.tuning
	# Geometry, as `Character.has_room_to_stand()`: a probe that does not touch the walls or floor.
	_probe.radius = maxf(tuning.radius - 0.02, 0.05)
	_probe.height = maxf(height - 0.12, _probe.radius * 2.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe
	var middle := body.global_position + Vector3.UP * (height / 2.0 + 0.06)
	query.transform = Transform3D(Basis.IDENTITY, middle)
	query.collision_mask = body.collision_mask
	query.exclude = [body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _may_start(body: Character, command: PlayerCommand, crouch_was: bool) -> bool:
	var tuning := body.tuning
	if not command.crouch or cooldown > 0.0 or body.is_dead():
		return false
	if not body.is_on_floor():
		return false
	var pressed := not crouch_was or (landed and tuning.slide_on_landing)
	if not pressed or body.crouching:
		return false
	if tuning.slide_needs_sprint and not command.sprint:
		return false
	if body.aiming and not tuning.slide_while_aiming:
		return false
	return body.ground_speed() >= tuning.slide_min_speed


func _start(body: Character) -> void:
	var tuning := body.tuning
	active = true
	time = 0.0
	carry = 0.0
	if boost_cooldown <= 0.0 and tuning.slide_boost > 0.0:
		var flat := Vector3(body.velocity.x, 0.0, body.velocity.z)
		var speed := flat.length()
		var boosted := maxf(speed, minf(speed + tuning.slide_boost, tuning.slide_boost_cap))
		flat = flat.normalized() * boosted
		body.velocity.x = flat.x
		body.velocity.z = flat.z
		boost_cooldown = tuning.slide_boost_cooldown


func _should_end(body: Character, command: PlayerCommand) -> bool:
	var tuning := body.tuning
	if body.is_dead():
		return true
	var ends := tuning.slide_hold_to_continue and not command.crouch
	if not ends and tuning.slide_max_time > 0.0 and time >= tuning.slide_max_time:
		ends = not (tuning.slide_downhill_unlimited and _downhill(body))
	# Under a gap too low to crouch in, the slide goes on until there is room (the shape query
	# only when the slide would end).
	return ends and has_room_for(body, crouch_height(tuning))


# The pull of gravity along the floor (m/s²), pointing down the slope on the ground's plane: its
# size is `slide_gravity` times the sine of the slope. Down a slope it speeds the slide up, up one
# it slows it. Flatter than `slide_flat_angle` pulls nothing.
func _slope_pull(body: Character) -> Vector3:
	var tuning := body.tuning
	var normal := body.get_floor_normal()
	var slope := normal.angle_to(Vector3.UP)
	if slope < deg_to_rad(tuning.slide_flat_angle):
		return Vector3.ZERO
	var downhill := Vector3(normal.x, 0.0, normal.z).normalized()
	return downhill * tuning.slide_gravity * sin(slope)


# True while the slide goes down a slope steeper than `slide_flat_angle`.
func _downhill(body: Character) -> bool:
	var pull := _slope_pull(body)
	var flat := Vector3(body.velocity.x, 0.0, body.velocity.z)
	return pull.length_squared() > 0.0 and pull.dot(flat) > 0.0


func _facing_forward(body: Character) -> Vector3:
	return Vector3.BACK.rotated(Vector3.UP, body.facing)

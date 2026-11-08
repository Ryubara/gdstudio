class_name Player
extends CharacterBody3D
## The third-person character: walks, runs and sprints toward where the camera looks, jumps
## (with coyote time and a jump buffer), steers in the air, climbs low steps, rides a
## `MovingPlatform`, pushes a `PhysicsProp`, opens a `Door` and collects a `Pickup`. Everything
## a developer tunes is in the `PlayerTuning` resource. Other nodes connect to the signals;
## `PlayerAnimation` follows `state`.
##
## It reads these input actions (all devices): `move_left`, `move_right`, `move_forward`,
## `move_back`, `jump`, `sprint`, `walk` (slows to a walk) and `interact`.

## The body left the ground by jumping.
signal jumped
## The body touched the ground; `impact_speed` is how fast it was falling, in m/s.
signal landed(impact_speed: float)
## Something hurt the character (`hit()`).
signal took_hit(amount: float, source: Node3D)
## The character used `target` (a door, a lever): the target's `interact()` was called.
signal interacted(target: Node3D)
## The character took `amount` of `item_id` from a `Pickup`; `total` is how many it holds now.
signal item_collected(item_id: StringName, amount: int, total: int)
## The body's state changed.
signal state_changed(state: State)
## The body was put somewhere else (`teleport()`, `respawn()`): a camera cuts to it instead of
## flying there.
signal teleported

enum State {
	IDLE,
	WALK,
	RUN,
	JUMP,
	FALL,
	LAND,
	PUSH,
	INTERACT,
	HIT,
}

## The group the player joins, so a HUD or a camera finds it.
const GROUP := &"player"
## Below this the player went out of the map and starts again at its spawn point.
const FALL_LIMIT := -25.0
## How long the landing clip holds the state, in seconds.
const LAND_TIME := 0.3
## A body slower than this on the ground is standing.
const STAND_SPEED := 0.15

@export_group("Character")
## The character's numbers: speeds, jump, steps, pushing. A copy of the file gives another feel.
@export var tuning: PlayerTuning
## Starts at a `SpawnPoint` of the group `player` when the scene has one.
@export var start_at_spawn := true

@export_group("Input")
## Turns the keys, pad and touch stick off (a cutscene, a menu).
@export var input_enabled := true

## What the body is doing; `PlayerAnimation` plays the clip for it.
var state := State.IDLE:
	set(value):
		if value != state:
			state = value
			state_changed.emit(value)
## The way the character faces, in radians about the up axis (0 faces +Z, the way the model
## looks).
var facing := 0.0
## The items it holds, by `Pickup.item_id`.
var items: Dictionary[StringName, int] = {}

var _coyote := 0.0
var _jump_buffer := 0.0
var _action_lock := 0.0
var _land_timer := 0.0
var _fall_speed := 0.0
var _was_airborne := false
var _pushing := false
var _jump_held := false
var _spawn_rng := RandomNumberGenerator.new()

@onready var _model: Node3D = $Model
@onready var _interactor: Interactor = $Interactor


func _ready() -> void:
	_spawn_rng.seed = 1
	add_to_group(GROUP)
	if tuning == null:
		tuning = PlayerTuning.new()
	_apply_tuning()
	floor_max_angle = deg_to_rad(tuning.max_slope)
	floor_snap_length = tuning.snap_length
	facing = _model.rotation.y
	if start_at_spawn and not Engine.is_editor_hint():
		respawn()


func _physics_process(delta: float) -> void:
	if global_position.y < FALL_LIMIT:
		respawn()
		return
	_tick_timers(delta)
	var wish := _wish_direction() if input_enabled and _action_lock <= 0.0 else Vector3.ZERO
	_steer(wish, delta)
	_vertical(delta)
	_climb(delta)
	var before := velocity
	move_and_slide()
	_pushing = _push_props(before)
	_after_move(wish, delta)
	_use_input()


## Puts the character at a spawn point of the group `player` (the first free one), or leaves it.
func respawn() -> void:
	var point := SpawnPoint.pick(get_tree(), &"player", _spawn_rng)
	if point == null:
		return
	var spot := point.global_transform
	teleport(spot.origin, atan2(-spot.basis.z.x, -spot.basis.z.z))


## Puts the character at `spot` standing still, facing `heading` (radians about the up axis;
## keeps the current facing when omitted). A camera that follows cuts to it.
func teleport(spot: Vector3, heading: float = NAN) -> void:
	global_position = spot
	velocity = Vector3.ZERO
	if not is_nan(heading):
		facing = heading
		_model.rotation.y = facing
	reset_physics_interpolation()
	teleported.emit()


## Hurts the character: stops it for `hit_stun_time` and throws it away from `source`.
func hit(amount: float = 1.0, source: Node3D = null) -> void:
	took_hit.emit(amount, source)
	_action_lock = tuning.hit_stun_time
	var away := Vector3.ZERO
	if source != null:
		away = global_position - source.global_position
		away.y = 0.0
	if away.length_squared() < 0.0001:
		away = -Vector3.FORWARD.rotated(Vector3.UP, facing)
	velocity = away.normalized() * tuning.knockback_speed
	state = State.HIT


## Uses the nearest usable thing in front. Returns it, or null when there is nothing to use.
func interact() -> Node3D:
	var forward := Vector3.BACK.rotated(Vector3.UP, facing)
	var target := _interactor.find_target(forward, tuning.interact_reach)
	if target == null or _action_lock > 0.0:
		return null
	if target.has_method(&"interact"):
		target.call(&"interact", self)
	_action_lock = tuning.interact_time
	interacted.emit(target)
	state = State.INTERACT
	return target


## Called by a `Pickup` the body touches.
func collect(item_id: StringName, amount: int) -> void:
	items[item_id] = items.get(item_id, 0) + amount
	item_collected.emit(item_id, amount, items[item_id])


## How many of `item_id` the character holds.
func count_of(item_id: StringName) -> int:
	return items.get(item_id, 0)


## The ground speed, in m/s.
func ground_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _apply_tuning() -> void:
	var capsule := ($Body.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	$Body.shape = capsule
	capsule.radius = tuning.radius
	capsule.height = tuning.height
	$Body.position.y = tuning.height / 2.0


func _tick_timers(delta: float) -> void:
	_action_lock = maxf(_action_lock - delta, 0.0)
	_land_timer = maxf(_land_timer - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if is_on_floor():
		_coyote = tuning.coyote_time
	else:
		_coyote = maxf(_coyote - delta, 0.0)
	if input_enabled and Input.is_action_just_pressed(&"jump"):
		_jump_buffer = tuning.jump_buffer_time


## The move direction in world space, as long as the stick is pushed (0 to 1) and relative to
## the camera that draws the scene.
func _wish_direction() -> Vector3:
	var pushed := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if pushed.is_zero_approx():
		return Vector3.ZERO
	var view := _view_basis()
	var direction := view.x * pushed.x + view.z * pushed.y
	direction.y = 0.0
	return direction.normalized() * minf(pushed.length(), 1.0)


func _view_basis() -> Basis:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Basis.IDENTITY
	var forward := -camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Basis.IDENTITY
	forward = forward.normalized()
	return Basis(forward.cross(Vector3.UP), Vector3.UP, -forward)


func _target_speed(strength: float) -> float:
	if Input.is_action_pressed(&"sprint"):
		return tuning.sprint_speed
	if Input.is_action_pressed(&"walk") or strength < 0.45:
		return tuning.walk_speed * maxf(strength, 0.5)
	return tuning.run_speed * strength


func _steer(wish: Vector3, delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var strength := wish.length()
	var goal := wish.normalized() * _target_speed(strength) if strength > 0.0 else Vector3.ZERO
	var rate := tuning.acceleration if strength > 0.0 else tuning.deceleration
	if not is_on_floor():
		rate *= tuning.air_control
	if _action_lock > 0.0 and state == State.HIT:
		rate = 0.0
	flat = flat.move_toward(goal, rate * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	if strength > 0.0 and _action_lock <= 0.0:
		facing = lerp_angle(
			facing, atan2(wish.x, wish.z), clampf(tuning.turn_speed * delta, 0.0, 1.0)
		)
		_model.rotation.y = facing


func _vertical(delta: float) -> void:
	var airborne := not is_on_floor()
	if airborne:
		var scale := tuning.fall_gravity_scale if velocity.y < 0.0 else 1.0
		velocity.y = maxf(velocity.y - tuning.gravity() * scale * delta, -tuning.terminal_speed)
		_fall_speed = maxf(_fall_speed, -velocity.y)
	elif velocity.y < 0.0:
		velocity.y = 0.0
	if _jump_buffer > 0.0 and _coyote > 0.0 and _action_lock <= 0.0:
		velocity.y = tuning.jump_speed()
		_jump_buffer = 0.0
		_coyote = 0.0
		_jump_held = true
		jumped.emit()
	if _jump_held and velocity.y > 0.0 and not Input.is_action_pressed(&"jump"):
		velocity.y = minf(velocity.y, tuning.jump_speed() * tuning.short_jump_scale)
		_jump_held = false
	if velocity.y <= 0.0:
		_jump_held = false
	# Snapping to the floor would pull the body back down in the tick it jumps.
	floor_snap_length = tuning.snap_length if velocity.y <= 0.0 else 0.0


func _climb(delta: float) -> void:
	if not is_on_floor():
		return
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	StepClimber.climb(self, motion, tuning.step_height, tuning.max_slope, tuning.radius + 0.06)


## Pushes the props the body slid into this tick. True when it is pushing one it walks at.
func _push_props(before: Vector3) -> bool:
	var pushing := false
	var flat := Vector3(before.x, 0.0, before.z)
	if flat.length() < STAND_SPEED:
		return false
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var prop := collision.get_collider() as RigidBody3D
		if prop == null:
			continue
		var along := -collision.get_normal()
		along.y = 0.0
		if along.length_squared() < 0.0001:
			continue
		along = along.normalized()
		if along.dot(flat.normalized()) < 0.5:
			continue
		var share := tuning.push_strength * clampf(tuning.push_mass / prop.mass, 0.15, 1.0) * 1.5
		var want := flat.length() * clampf(share, 0.0, 1.0)
		var gain := want - prop.linear_velocity.dot(along)
		if gain > 0.0:
			prop.apply_central_impulse(along * gain * prop.mass)
		pushing = true
	return pushing


func _after_move(wish: Vector3, _delta: float) -> void:
	var grounded := is_on_floor()
	if grounded and _was_airborne:
		landed.emit(_fall_speed)
		if _fall_speed >= tuning.land_clip_speed:
			_land_timer = LAND_TIME
		_fall_speed = 0.0
	_was_airborne = not grounded
	state = _pick_state(grounded, wish)


func _pick_state(grounded: bool, wish: Vector3) -> State:
	if _action_lock > 0.0 and (state == State.HIT or state == State.INTERACT):
		return state
	var picked := State.IDLE
	if not grounded:
		picked = State.JUMP if velocity.y > 0.0 else State.FALL
	elif _land_timer > 0.0:
		picked = State.LAND
	elif _pushing and not wish.is_zero_approx():
		picked = State.PUSH
	elif ground_speed() >= STAND_SPEED:
		picked = State.WALK if ground_speed() <= tuning.walk_speed + 0.35 else State.RUN
	return picked


func _use_input() -> void:
	if input_enabled and Input.is_action_just_pressed(&"interact"):
		interact()

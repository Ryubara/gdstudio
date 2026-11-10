@tool
class_name Player
extends CharacterBody3D
## The third-person character: walks, runs and sprints toward where the camera looks, crouches
## (and stays crouched under a low ceiling), jumps (with coyote time and a jump buffer), steers
## in the air, climbs low steps, rides a `MovingPlatform`, pushes a `PhysicsProp`, opens a `Door`,
## collects a `Pickup`, aims and shoots its `Weapon`, and dies into a ragdoll (`die()`, the
## `ragdoll` checkbox or the `ragdoll` key) and gets up again (`revive()`). Everything a developer
## tunes is in the `PlayerTuning` resource. Other nodes connect to the signals; `PlayerAnimation`
## follows `state`.
##
## It is a `@tool` script so the editor shows the capsule and the camera target follow the tuning
## (radius, height, eye height); only the setup runs there, never the movement.
##
## It reads these input actions (all devices): `move_left`, `move_right`, `move_forward`,
## `move_back`, `jump`, `sprint`, `walk` (slows to a walk), `interact`, `crouch`, `aim`,
## `fire` and `ragdoll` (made at run time, holding `ragdoll_key`).

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
## The character began or stopped aiming (the aim button, or firing): the crosshair follows it.
signal aim_changed(aiming: bool)
## The character crouched or stood up (it stands only when it has room).
signal crouch_changed(crouching: bool)
## The character died: it went limp (into its ragdoll, when it has one) and takes no gameplay
## input until it is revived.
signal died
## The character got up again, where its body lay (or was put somewhere by `teleport()`).
signal revived

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
	CROUCH,  ## Crouched, standing still or walking.
	DEAD,  ## Dead: limp, ignoring every gameplay input; the camera still orbits.
}

## The group the player joins, so a HUD or a camera finds it.
const GROUP := &"player"
## The input action that kills and revives the character (`ragdoll_key` is added to it).
const RAGDOLL_ACTION := &"ragdoll"
## How much faster than a prop's `push_speed` the character walks while it pushes the prop: the
## prop is given the push speed, and the character stays against it and pushes it every tick
## (equal speeds would let a gap open and the friction slow the prop between pushes).
const PUSH_CONTACT := 1.15
## Seconds a slow push goes on counting after the last touch: pushing a heavy prop is a series of
## touches with a small gap between them, and the push clip and the speed limit should not flicker.
const PUSH_HOLD := 0.25

@export_group("Character")
## The character's numbers: speeds, jump, steps, pushing. A copy of the file gives another feel.
## Changing a number while the game runs works at once.
@export var tuning: PlayerTuning:
	set(value):
		if tuning != null and tuning.changed.is_connected(_apply_tuning):
			tuning.changed.disconnect(_apply_tuning)
		tuning = value
		if tuning != null:
			tuning.changed.connect(_apply_tuning)
			_apply_tuning()
## Starts at a `SpawnPoint` of the group `player` when the scene has one.
@export var start_at_spawn := true
## The slot that holds the character's model; it is turned to the heading. It is the slot that is
## referenced (never the model inside it, which a game replaces), so it has no unique name: a
## unique name on the path to the model is what makes the editor's helper player lose the model
## (see `PlayerAnimation`).
@export var model: PlayerModel

@export_group("Weapon")
## What the character shoots with. Empty: it cannot aim or shoot.
@export var weapon: Weapon

@export_group("Ragdoll")
## The ragdoll the character goes limp into when it dies. Empty: it dies standing still.
@export var ragdoll_body: PlayerRagdoll
## Dead (on) or alive (off). Ticking it in the inspector, or in the remote inspector while the
## game runs, kills the character into its ragdoll; unticking it gets it up. Saved on, the
## character starts dead.
@export var ragdoll := false:
	set(value):
		ragdoll = value
		if Engine.is_editor_hint() or not is_node_ready():
			return
		if value and state != State.DEAD:
			die()
		elif not value and state == State.DEAD:
			revive()
## The key that kills and revives the character, added to the input action `ragdoll` while the
## game runs (a game can bind more to that action in the Project Settings). A testing aid: set it
## to None in a game that ships without it.
@export var ragdoll_key: Key = KEY_Y:
	set(value):
		ragdoll_key = value
		_bind_ragdoll_key()

@export_group("Input")
## Turns the keys, pad and touch stick off (a cutscene, a menu).
@export var input_enabled := true

## True while the character is dead and lies in its death clip, not in a ragdoll (the ragdoll
## declined it: the cap on limp ragdolls or the range).
var died_by_clip := false

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
## True while the character is crouched, or kept crouched by a ceiling it cannot stand under.
var crouching := false
## True while it aims: the aim button or the fire button is held, and only then. Walk speed, the
## turn to the camera and the locomotion clips read it, so nothing of aiming outlasts the input.
var aiming := false
## True while the aim button is held (firing alone does not set it). The camera's aim zoom
## comes from this.
var aim_held := false
## True while the fire button is held and the character can shoot.
var fire_held := false
## How far the arm is up, 0 (down) to 1 (aiming); `PlayerAnimation` blends the pose by it.
var aim_amount := 0.0

var _coyote := 0.0
var _jump_buffer := 0.0
var _action_lock := 0.0
var _land_timer := 0.0
var _fall_speed := 0.0
var _was_airborne := false
var _pushing := false
var _push_cap := 0.0
var _push_hold := 0.0
var _jump_held := false
var _sprinting := false
var _wants_crouch := false
var _crouch_amount := 0.0
var _fire_buffer := 0.0
var _ragdoll_event: InputEventKey
var _stand_probe := CapsuleShape3D.new()
var _spawn_rng := RandomNumberGenerator.new()

@onready var _interactor: Interactor = %Interactor
@onready var _body: CollisionShape3D = %Body
@onready var _camera_target: Node3D = %CameraTarget


func _ready() -> void:
	if tuning == null:
		tuning = PlayerTuning.new()
	_apply_tuning()
	if Engine.is_editor_hint():
		return
	add_to_group(GROUP)
	# Fixed for a character, so a test repeats, but not shared, so two characters pick apart.
	_spawn_rng.seed = hash(str(get_path()))
	facing = model.rotation.y
	if ragdoll_body != null:
		ragdoll_body.add_collision_exception(self)
	_bind_ragdoll_key()
	if start_at_spawn:
		respawn()
	if ragdoll:
		# The ragdoll's bones are made in its own `_ready`, after this one.
		die.call_deferred()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if input_enabled and InputMap.has_action(RAGDOLL_ACTION):
		if Input.is_action_just_pressed(RAGDOLL_ACTION):
			ragdoll = not ragdoll
	if state == State.DEAD:
		_dead_tick()
		return
	if global_position.y < tuning.fall_limit:
		respawn()
		return
	_tick_timers(delta)
	_update_crouch(delta)
	_update_aim(delta)
	var wish := _wish_direction() if input_enabled and _action_lock <= 0.0 else Vector3.ZERO
	_steer(wish, delta)
	_vertical(delta)
	_climb(delta)
	var before := velocity
	move_and_slide()
	_pushing = _push_props(before, delta)
	_after_move(wish, delta)
	_use_input(delta)


## Puts the character at a spawn point of the group `player` (the first free one), or leaves it.
func respawn() -> void:
	var point := SpawnPoint.pick(get_tree(), &"player", _spawn_rng)
	if point == null:
		return
	var spot := point.spawn_transform(_spawn_rng)
	teleport(spot.origin, atan2(-spot.basis.z.x, -spot.basis.z.z))


## Puts the character at `spot` standing still, facing `heading` (radians about the up axis;
## keeps the current facing when omitted). A camera that follows cuts to it. A dead character is
## alive again at once.
func teleport(spot: Vector3, heading: float = NAN) -> void:
	if state == State.DEAD:
		if ragdoll_body != null:
			ragdoll_body.stop(false)
		_come_alive()
	global_position = spot
	velocity = Vector3.ZERO
	if not is_nan(heading):
		facing = heading
		model.rotation.y = facing
	reset_physics_interpolation()
	teleported.emit()


## Kills the character: it goes limp into its ragdoll, which keeps the body's momentum, and it
## ignores every gameplay input until `revive()`. The camera's target follows the hips. When the
## ragdoll declines (`PlayerRagdoll.can_start()`: too many limp already, or too far from the
## camera) the character plays its death clip and lies in the clip's last pose (`died_by_clip`).
func die() -> void:
	if state == State.DEAD:
		return
	var momentum := velocity
	died_by_clip = ragdoll_body != null and not ragdoll_body.can_start()
	_wants_crouch = false
	_fire_buffer = 0.0
	_action_lock = 0.0
	_land_timer = 0.0
	_jump_buffer = 0.0
	_jump_held = false
	_sprinting = false
	aim_held = false
	fire_held = false
	aim_amount = 0.0
	if aiming:
		aiming = false
		aim_changed.emit(false)
	velocity = Vector3.ZERO
	_body.disabled = true
	state = State.DEAD
	ragdoll = true
	if ragdoll_body != null and not died_by_clip:
		ragdoll_body.start(momentum)
	died.emit()


## Gets the character up where its body lies, facing the way its chest faces; the pose blends
## from lying to standing over the ragdoll's `get_up_time`.
func revive() -> void:
	if state != State.DEAD:
		return
	if ragdoll_body != null and ragdoll_body.is_limp():
		var heading := ragdoll_body.facing()
		global_position = _ground_below(ragdoll_body.hips())
		facing = atan2(heading.x, heading.z)
		model.rotation.y = facing
		reset_physics_interpolation()
		ragdoll_body.stop()
	_come_alive()


## True while the character is dead.
func is_dead() -> bool:
	return state == State.DEAD


## Hurts the character: stops it for `hit_stun_time` and throws it away from `source`. A dead
## character takes no hit.
func hit(amount: float = 1.0, source: Node3D = null) -> void:
	if state == State.DEAD:
		return
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


## Where the character faces on the map plane, for a minimap's arrow (the body turns inside this
## node).
func get_minimap_heading() -> Vector2:
	return Vector2(sin(facing), cos(facing))


## Uses the nearest usable thing in front. Returns it, or null when there is nothing to use.
func interact() -> Node3D:
	var forward := Vector3.BACK.rotated(Vector3.UP, facing)
	var target := _interactor.find_target(forward, tuning.interact_reach)
	if target == null or _action_lock > 0.0 or state == State.DEAD:
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


## True while the sprint button is held and the character runs faster than a run on the ground
## (the camera zooms and shakes by it).
func is_sprinting() -> bool:
	return _sprinting


## The height of the capsule now, in metres: the standing height, or less while it crouches.
func body_height() -> float:
	var shrink := smoothstep(0.0, 1.0, _crouch_amount)
	return lerpf(tuning.height, _crouch_height(), shrink)


## True when nothing is above the character that would stop it from standing up.
func has_room_to_stand() -> bool:
	_stand_probe.radius = maxf(tuning.radius - 0.02, 0.05)
	_stand_probe.height = tuning.height - 0.12
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _stand_probe
	var middle := global_position + Vector3.UP * (tuning.height / 2.0 + 0.06)
	query.transform = Transform3D(Basis.IDENTITY, middle)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


# Puts `ragdoll_key` on the `ragdoll` action, in place of the key this player put there before.
func _bind_ragdoll_key() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	if not InputMap.has_action(RAGDOLL_ACTION):
		InputMap.add_action(RAGDOLL_ACTION)
	if _ragdoll_event != null:
		InputMap.action_erase_event(RAGDOLL_ACTION, _ragdoll_event)
		_ragdoll_event = null
	if ragdoll_key != KEY_NONE:
		_ragdoll_event = InputEventKey.new()
		_ragdoll_event.physical_keycode = ragdoll_key
		InputMap.action_add_event(RAGDOLL_ACTION, _ragdoll_event)


# Dead: the body stays where it died with its capsule off, the camera's target follows the hips,
# and a ragdoll that falls out of the map starts again at the spawn point.
func _dead_tick() -> void:
	if ragdoll_body == null or not ragdoll_body.is_limp():
		return
	var hips := ragdoll_body.hips()
	if hips.y < tuning.fall_limit:
		respawn()
		return
	_camera_target.global_position = hips + Vector3.UP * 0.25


func _come_alive() -> void:
	died_by_clip = false
	_body.disabled = false
	velocity = Vector3.ZERO
	_fall_speed = 0.0
	_was_airborne = false
	_camera_target.position = Vector3.ZERO
	_fit_body()
	state = State.IDLE
	ragdoll = false
	revived.emit()


# The floor under `spot` (a ray down from a little above it), or `spot` itself over nothing.
func _ground_below(spot: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(
		spot + Vector3.UP * 0.5, spot + Vector3.DOWN * 3.0, collision_mask, [get_rid()]
	)
	var found := get_world_3d().direct_space_state.intersect_ray(query)
	return found["position"] if not found.is_empty() else spot


# Fits the capsule, the camera's target, the steepest floor and the floor snap to the tuning (they
# are copied into the body, so a change to them is applied here, from the tuning's `changed`).
func _apply_tuning() -> void:
	if not is_node_ready() or tuning == null:
		return
	_fit_body()
	if Engine.is_editor_hint():
		return
	floor_max_angle = deg_to_rad(tuning.max_slope)
	floor_snap_length = tuning.snap_length


# Sizes the capsule and the camera's target for the crouch: the capsule keeps its feet on the
# ground and loses height from the top.
func _fit_body() -> void:
	var capsule := _body.shape as CapsuleShape3D
	var height := body_height()
	capsule.radius = tuning.radius
	capsule.height = height
	_body.position.y = height / 2.0
	var shrink := smoothstep(0.0, 1.0, _crouch_amount)
	_camera_target.position.y = lerpf(tuning.camera_height, tuning.crouch_camera_height, shrink)


# The shortest the capsule can be: a capsule is at least two radii tall.
func _crouch_height() -> float:
	return clampf(tuning.crouch_height, tuning.radius * 2.0 + 0.01, tuning.height)


func _update_crouch(delta: float) -> void:
	if tuning.crouch_toggle:
		if input_enabled and Input.is_action_just_pressed(&"crouch"):
			_wants_crouch = not _wants_crouch
	else:
		_wants_crouch = input_enabled and Input.is_action_pressed(&"crouch")
	var should := _wants_crouch
	# Letting go under a low ceiling keeps the character crouched until there is room.
	if not should and crouching and not has_room_to_stand():
		should = true
	if should != crouching:
		crouching = should
		crouch_changed.emit(crouching)
	var before := _crouch_amount
	_crouch_amount = move_toward(
		_crouch_amount, 1.0 if crouching else 0.0, delta / maxf(tuning.crouch_time, 0.001)
	)
	if _crouch_amount != before:
		_fit_body()


func _update_aim(delta: float) -> void:
	var wants := false
	if weapon != null and input_enabled and _action_lock <= 0.0:
		fire_held = Input.is_action_pressed(&"fire")
		aim_held = Input.is_action_pressed(&"aim")
		wants = aim_held or fire_held
	else:
		aim_held = false
		fire_held = false
	if wants != aiming:
		aiming = wants
		aim_changed.emit(aiming)
	aim_amount = move_toward(
		aim_amount, 1.0 if aiming else 0.0, delta / maxf(tuning.aim_pose_time, 0.001)
	)


# The camera's heading as a facing angle, or NAN when no camera draws the scene.
func _camera_heading() -> float:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return NAN
	var forward := -camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return NAN
	return atan2(forward.x, forward.z)


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
	var speed := tuning.run_speed * strength
	if crouching:
		speed = tuning.crouch_speed * maxf(strength, 0.5)
	elif Input.is_action_pressed(&"sprint") and not aiming:
		speed = tuning.sprint_speed
	elif Input.is_action_pressed(&"walk") or strength < 0.45:
		speed = tuning.walk_speed * maxf(strength, 0.5)
	if aiming:
		speed = minf(speed, tuning.walk_speed * 1.5) * tuning.aim_move_scale
	if _push_cap > 0.0:
		speed = minf(speed, _push_cap)
	return speed


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
	var heading := _camera_heading()
	if aiming and _action_lock <= 0.0 and not is_nan(heading):
		# Aiming turns the body to the camera's heading, however it walks.
		facing = lerp_angle(facing, heading, clampf(tuning.aim_turn_speed * delta, 0.0, 1.0))
		model.rotation.y = facing
	elif strength > 0.0 and _action_lock <= 0.0:
		facing = lerp_angle(
			facing, atan2(wish.x, wish.z), clampf(tuning.turn_speed * delta, 0.0, 1.0)
		)
		model.rotation.y = facing


func _vertical(delta: float) -> void:
	var airborne := not is_on_floor()
	if airborne:
		var gravity_scale := tuning.fall_gravity_scale if velocity.y < 0.0 else 1.0
		velocity.y = maxf(
			velocity.y - tuning.gravity() * gravity_scale * delta, -tuning.terminal_speed
		)
		_fall_speed = maxf(_fall_speed, -velocity.y)
	elif velocity.y < 0.0:
		velocity.y = 0.0
	if _jump_buffer > 0.0 and _coyote > 0.0 and _action_lock <= 0.0 and not crouching:
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


## Pushes the props the body slid into this tick. True when it is pushing one it walks at. A prop
## with a `push_speed` is pushed at that speed and the character walks a little faster than it
## (`PUSH_CONTACT`), and it keeps counting as pushed for `PUSH_HOLD` after the last touch.
func _push_props(before: Vector3, delta: float) -> bool:
	var pushing := false
	var slow_push := false
	var flat := Vector3(before.x, 0.0, before.z)
	var cap := 0.0
	if flat.length() >= tuning.stand_speed:
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
			var share := (
				tuning.push_strength * clampf(tuning.push_mass / prop.mass, 0.15, 1.0) * 1.5
			)
			var want := flat.length() * clampf(share, 0.0, 1.0)
			var slow: float = prop.get(&"push_speed") if &"push_speed" in prop else 0.0
			if slow > 0.0:
				want = slow
				cap = slow * PUSH_CONTACT if cap == 0.0 else minf(cap, slow * PUSH_CONTACT)
				slow_push = true
			var gain := want - prop.linear_velocity.dot(along)
			if gain > 0.0:
				prop.apply_central_impulse(along * gain * prop.mass)
			pushing = true
	if slow_push:
		_push_hold = PUSH_HOLD
		_push_cap = cap
	else:
		_push_hold = maxf(_push_hold - delta, 0.0)
		if _push_hold <= 0.0:
			_push_cap = 0.0
	return pushing or _push_hold > 0.0


func _after_move(wish: Vector3, _delta: float) -> void:
	var grounded := is_on_floor()
	if grounded and _was_airborne:
		landed.emit(_fall_speed)
		if _fall_speed >= tuning.land_clip_speed:
			_land_timer = tuning.land_time
		_fall_speed = 0.0
	_was_airborne = not grounded
	_sprinting = (
		grounded
		and input_enabled
		and not crouching
		and not aiming
		and Input.is_action_pressed(&"sprint")
		and ground_speed() > tuning.run_speed
	)
	state = _pick_state(grounded, wish)


func _pick_state(grounded: bool, wish: Vector3) -> State:
	if _action_lock > 0.0 and (state == State.HIT or state == State.INTERACT):
		return state
	var picked := State.IDLE
	if not grounded:
		picked = State.JUMP if velocity.y > 0.0 else State.FALL
	elif _land_timer > 0.0:
		picked = State.LAND
	elif crouching:
		picked = State.CROUCH
	elif _pushing and not wish.is_zero_approx():
		picked = State.PUSH
	elif ground_speed() >= tuning.stand_speed:
		picked = State.WALK if ground_speed() <= tuning.walk_speed + 0.35 else State.RUN
	return picked


func _use_input(delta: float) -> void:
	if input_enabled and Input.is_action_just_pressed(&"interact"):
		interact()
	_use_weapon(delta)


# A press of the fire button waits a moment for the arm to come up, then shoots.
func _use_weapon(delta: float) -> void:
	_fire_buffer = maxf(_fire_buffer - delta, 0.0)
	if weapon == null or not input_enabled:
		return
	var pulled := Input.is_action_just_pressed(&"fire")
	if weapon.automatic and Input.is_action_pressed(&"fire"):
		pulled = true
	if pulled:
		_fire_buffer = 0.3
	if _fire_buffer > 0.0 and aiming and aim_amount >= 0.5:
		if weapon.fire() != null:
			_fire_buffer = 0.0

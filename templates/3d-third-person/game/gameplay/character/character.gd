@tool
class_name Character
extends CharacterBody3D
## A third-person character's body, whoever drives it: walks, runs and sprints the way its command
## points, crouches (and stays crouched under a low ceiling), jumps (with coyote time and a jump
## buffer), steers in the air, climbs low steps, rides a `MovingPlatform`, pushes a `PhysicsProp`,
## opens a `Door`, collects a `Pickup`, aims and shoots its `Weapon`, and dies into a ragdoll
## (`die()`, the `ragdoll` checkbox or a command's `ragdoll_pressed`) and gets up again
## (`revive()`). It lies down and crawls (`CharacterProne`, tuned by its `ProneTuning`), slides
## when crouch is pressed at a sprint (`CharacterSlide`, tuned by its `SlideTuning`), and vaults
## over or mantles onto a `Vaultable` (`CharacterVault`, tuned by its `vault_settings`). Everything
## else is tuned in the `CharacterTuning`. Other nodes connect to the signals. The push, the death,
## the capsule and the snapshot are modules beside it too (`CharacterPush`, `CharacterDeath`,
## `CharacterCapsule`, `CharacterState`); a new move goes in a module of its own the same way.
##
## It is a `@tool` script so the editor shows the capsule and the camera target follow the tuning
## (radius, height, eye height); only the setup runs there, never the movement.
##
## The body is moved by `step(command, delta)` and nothing else: one `PlayerCommand` a physics
## tick, from its `controller` (an AI's, a recording's) or from whoever steps it (a server, a
## test). It reads no input and no camera itself. `character.tscn` is the body alone (what a
## server loads), `character_dressed.tscn` adds the model, animation, footsteps and ragdoll, and
## the human's `Player` (`player.tscn`) adds its `PlayerInput`, its group and its spawn point.

## The body left the ground by jumping.
signal jumped
## The body touched the ground; `impact_speed` is how fast it was falling, in m/s.
signal landed(impact_speed: float)
## Something hurt the character (`hit()`, `take_hit()`): `amount` is the damage.
signal took_hit(amount: float, source: Node3D)
## The character's health changed (a hit, getting up).
signal health_changed(health: float)
## A hit reached the character, alive or lying dead: the record a game's networking sends, and
## what the `HitReaction` answers with a flinch, the death's push or a push on the lying body.
signal hit_received(record: HitRecord)
## The character used `target` (a door, a lever): the parent of the `Interactable` it found.
signal interacted(target: Node3D)
## The character took `amount` of `item_id` from a `Pickup`; `total` is how many it holds now.
signal item_collected(item_id: StringName, amount: int, total: int)
## The body's state changed.
signal state_changed(state: State)
## The body was put somewhere else (`teleport()`, the human's `respawn()`): a camera cuts to it
## instead of flying there.
signal teleported
## The character began or stopped aiming (the aim button, or firing): the crosshair follows it.
signal aim_changed(aiming: bool)
## The character crouched or stood up (it stands only when it has room).
signal crouch_changed(crouching: bool)
## The character began to lie down (true) or to get up (false; it gets up only when a crouched
## body has room).
signal prone_changed(prone: bool)
## The character died: it went limp (into its ragdoll, when it has one) and takes no gameplay
## input until it is revived.
signal died
## The character got up again, where its body lay (or was put somewhere by `teleport()`).
signal revived
## The body is below the tuning's `fall_limit` (or, dead, its ragdoll is): it went out of the map.
## Said once; the step does nothing more until the body is put somewhere (`teleport()`). Whoever
## owns the character answers it: `Player` starts again at a spawn point, and a game or a server
## that decides where characters start connects its own answer.
signal fell

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
	PRONE,  ## Lying down, going down or getting up: still or crawling.
	SLIDE,  ## Sliding on its momentum, low (after `PRONE` so the numbers sent before stay).
	VAULT,  ## Vaulting over an obstacle.
	MANTLE,  ## Climbing up onto an obstacle.
}

@export_group("Character")
## The character's numbers: speeds, jump, steps, pushing. A copy of the file gives another feel.
## Changing a number while the game runs works at once.
@export var tuning: CharacterTuning:
	set(value):
		if tuning != null and tuning.changed.is_connected(_apply_tuning):
			tuning.changed.disconnect(_apply_tuning)
		tuning = value
		if tuning != null:
			tuning.changed.connect(_apply_tuning)
			_apply_tuning()
## The slot that holds the character's model; it is turned to the heading. It is the slot that is
## referenced (never the model inside it, which a game replaces), so it has no unique name: a
## unique name on the path to the model is what makes the editor's helper player lose the model
## (see `CharacterAnimation`).
@export var model: CharacterModel
## What decides each physics tick: a `PlayerInput` for a human, an AI's controller for an AI.
## Empty: the body asks for nothing (it still falls and stands), or something else steps it
## (`step()` with physics processing off).
@export var controller: CharacterController
## How it vaults over and mantles onto obstacles that carry a `Vaultable`. Empty: it never does.
@export var vault_settings: VaultSettings

@export_group("Prone")
## The prone stance and the crawl: speeds, times, the lying capsule, the aim. Empty: the
## defaults. Changing a number while the game runs works at once.
@export var prone_tuning: ProneTuning:
	set(value):
		if prone_tuning != null and prone_tuning.changed.is_connected(_apply_tuning):
			prone_tuning.changed.disconnect(_apply_tuning)
		prone_tuning = value
		if prone_tuning != null:
			prone_tuning.changed.connect(_apply_tuning)
			_apply_tuning()

@export_group("Slide")
## The slide: the least speed, the boost, the friction, slopes, the slide jump, the low capsule.
## Empty: the defaults. Changing a number while the game runs works at once.
@export var slide_tuning: SlideTuning:
	set(value):
		if slide_tuning != null and slide_tuning.changed.is_connected(_apply_tuning):
			slide_tuning.changed.disconnect(_apply_tuning)
		slide_tuning = value
		if slide_tuning != null:
			slide_tuning.changed.connect(_apply_tuning)
			_apply_tuning()

@export_group("Weapon")
## What the character shoots with. Empty: it cannot aim or shoot. The character steps it: the
## weapon's own `self_ticking` is turned off and `step` counts its cooldown.
@export var weapon: Weapon:
	set(value):
		weapon = value
		if weapon != null and not Engine.is_editor_hint():
			weapon.self_ticking = false
## The weapons carried and the switch between them (the command's next, previous and empty-hands
## presses). Empty: the character keeps the one weapon it has. The character steps it before the
## weapon.
@export var loadout: WeaponLoadout

@export_group("Ragdoll")
## The ragdoll the character goes limp into when it dies. Empty: it dies standing still.
@export var ragdoll_body: CharacterRagdoll
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
## On: a command's `ragdoll_pressed` kills and revives the character (what the human's
## `ragdoll_key` sends). A testing aid: a server that steps commands from the network turns it off.
@export var ragdoll_by_command := true

## The health left (0 to `max_health`; 0 with no `Health` child): read only, the HUD shows it.
var health: float:
	get:
		return Health.of(self).value if Health.of(self) != null else 0.0
## The `Health` child's `max_value` (read only: tune and set the `Health` node).
var max_health: float:
	get:
		return Health.of(self).max_value if Health.of(self) != null else 0.0

## True while the character is dead and lies in its death clip, not in a ragdoll (the ragdoll
## declined it: the cap on limp ragdolls or the range).
var died_by_clip := false

## What the body is doing; `CharacterAnimation` plays the clip for it.
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
## True while the character lies down, goes down or gets up (its state is `PRONE`). Read only:
## the command's `prone` bit lies it down.
var prone: bool:
	get:
		return _prone.is_prone()
## How far down the character is, 0 (standing or crouched) to 1 (lying); the capsule, the camera's
## target and the animation follow it. Read only.
var prone_amount: float:
	get:
		return _prone.amount
## True while it aims: the aim button or the fire button is held, and only then. Walk speed, the
## turn to the camera and the locomotion clips read it, so nothing of aiming outlasts the input.
var aiming := false
## True while the aim button is held (firing alone does not set it). The camera's aim zoom
## comes from this.
var aim_held := false
## True while the fire button is held and the character can shoot.
var fire_held := false
## How far the arm is up, 0 (down) to 1 (aiming); `CharacterAnimation` blends the pose by it.
var aim_amount := 0.0
## Where the last stepped command looked, radians: the heading (0 looks along -Z) and the look up
## (positive) or down. The aim pose follows `view_pitch`; a body placed from the network sets it.
var view_yaw := 0.0
var view_pitch := 0.0
## The command of the last step, as the body used it (not finite: let go of; a push no longer
## than 1). Written again by every step.
var last_command := PlayerCommand.new()
## True while the character slides (`CharacterSlide`). Read only.
var sliding: bool:
	get:
		return _slide.active
## The vault and the mantle (`CharacterVault`): the running plan; its step state is `vault`.
var vault_motion := CharacterVault.new()

var _coyote := 0.0
var _jump_buffer := 0.0
var _action_lock := 0.0
var _land_timer := 0.0
var _fall_speed := 0.0
var _was_airborne := false
var _grounded := false
var _fallen := false
var _pushing := false
var _push_cap := 0.0
var _push_hold := 0.0
var _jump_held := false
var _sprinting := false
var _wants_crouch := false
var _crouch_amount := 0.0
var _fire_buffer := 0.0
var _stand_probe := CapsuleShape3D.new()
# The prone stance; its step state is `CharacterState.prone`.
var _prone := CharacterProne.new()
var _slide := CharacterSlide.new()

@onready var _interactor: Interactor = %Interactor
@onready var _body: CollisionShape3D = %Body
@onready var _camera_target: Node3D = %CameraTarget


func _ready() -> void:
	if tuning == null:
		tuning = CharacterTuning.new()
	if prone_tuning == null:
		prone_tuning = ProneTuning.new()
	if slide_tuning == null:
		slide_tuning = SlideTuning.new()
	_apply_tuning()
	if Engine.is_editor_hint():
		return
	var part := Health.of(self)
	if part != null:
		part.changed.connect(func(value: float, _max: float) -> void: health_changed.emit(value))
		part.died.connect(die)
	if model != null:
		facing = model.rotation.y
	view_yaw = facing - PI
	last_command.yaw = view_yaw
	if ragdoll_body != null:
		ragdoll_body.add_collision_exception(self)
	if ragdoll:
		# The ragdoll's bones are made in its own `_ready`, after this one.
		die.call_deferred()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	step(controller.sample() if controller != null else _idle_command(), delta)


## Moves the body one physics tick as `command` asks: the only thing that moves it. The
## character's own `_physics_process` calls it with its controller's command; a server or a test
## turns that off (`set_physics_process(false)`) and calls it itself, inside a physics frame.
## `delta` is the physics step, or a whole number of them for a body stepped less often (a far
## AI character every 3rd tick): the timers count it all and the move goes as far (any other
## number would split the body from the engine's own step; a debug build stops on one). A
## command with a number that is not finite is stepped as one that asks for nothing, and a push
## longer than 1 as 1. The weapon's cooldown is counted at the end of every step, alive or dead.
func step(command: PlayerCommand, delta: float) -> void:
	if Engine.is_editor_hint():
		return
	assert(Engine.is_in_physics_frame(), "Character.step() runs inside a physics frame.")
	assert(_is_physics_step(delta), "Character.step() takes whole physics steps.")
	if command.all_finite():
		last_command.copy_from(command)
		last_command.move = command.move.limit_length(1.0)
	else:
		last_command.clear()
	view_yaw = last_command.yaw
	view_pitch = _prone.held_pitch(prone_tuning, last_command.pitch)
	if ragdoll_by_command and last_command.ragdoll_pressed:
		ragdoll = not ragdoll
	if state == State.DEAD:
		CharacterDeath.dead_tick(self)
	elif global_position.y < tuning.fall_limit:
		_fall_out()
	else:
		_move(delta)
	# Last, as the weapon's own tick came after the body's; the switch before the weapon.
	if loadout != null:
		loadout.tick(delta)
	if weapon != null:
		weapon.tick(delta)


# One tick of a living body inside the map. A controller that asks for it (an AI's) gets the lean
# tick when nothing but the walk has anything to do: the same result, fewer modules
# (`CharacterLean`).
func _move(delta: float) -> void:
	if controller != null and controller.lean_step and CharacterLean.can_take(self):
		CharacterLean.move(self, delta)
		return
	_tick_timers(delta)
	_update_prone(delta)
	if vault_motion.drive(self, delta):
		return
	var lowered := _slide.amount
	_slide.begin_tick(self, _wants_crouch, _coyote, _action_lock > 0.0, delta)
	_update_crouch(delta)
	_update_aim(delta)
	if _slide.amount != lowered:
		_fit_body()
	var wish := _wish_direction() if _action_lock <= 0.0 else Vector3.ZERO
	if _slide.active:
		_slide.steer(self, wish, delta)
		_present_facing()
	else:
		_steer(wish, delta)
	_vertical(delta)
	_climb(delta)
	var before := velocity
	var ticks := roundf(delta / get_physics_process_delta_time())
	velocity *= ticks
	move_and_slide()
	velocity /= ticks
	_grounded = is_on_floor()
	_pushing = CharacterPush.push_props(self, before, delta)
	_after_move(wish, delta)
	_use_input(delta)


## True when a shot may leave on the tick `command` is stepped: the fire button was just pressed
## or is still buffered (or held, with an automatic weapon) and the weapon is ready. A controller
## asks it to know whether the command needs the crosshair's ray (`PlayerCommand.has_shot`).
func shot_wanted(command: PlayerCommand) -> bool:
	if weapon == null or state == State.DEAD or not weapon.can_fire():
		return false
	var automatic := weapon.definition != null and weapon.definition.automatic
	return _fire_buffer > 0.0 or command.fire_pressed or (automatic and command.fire)


## The ray the character aims along, from the command of its last step: where it starts and its
## direction (length 1). It is the command's shot block when it has one (for a human, the ray
## under the crosshair), else it goes from the character's eye point (its camera target) along
## the command's view (`view_yaw`, `view_pitch`). The weapon is fired along it.
func aim_ray() -> PackedVector3Array:
	return PackedVector3Array([_aim_origin(), _aim_direction()])


## Everything the next step reads from this one, in `into` (or a new `CharacterState`).
func state_snapshot(into: CharacterState = null) -> CharacterState:
	var kept := into if into != null else CharacterState.new()
	kept.take(self)
	return kept


## Puts the body back as `kept` holds it (a `state_snapshot()` of this character while it was
## alive). The engine's own floor contact is found again by the next step.
func restore(kept: CharacterState) -> void:
	kept.put_back(self)
	_fit_body()
	_present_facing()


## Puts the character at `spot` standing still, facing `heading` (radians about the up axis;
## keeps the current facing when omitted). A camera that follows cuts to it. A dead character is
## alive again at once.
func teleport(spot: Vector3, heading: float = NAN) -> void:
	if state == State.DEAD:
		if ragdoll_body != null:
			ragdoll_body.stop(false)
		CharacterDeath.come_alive(self)
	vault_motion.cancel()
	global_position = spot
	velocity = Vector3.ZERO
	_fallen = false
	_slide.reset()
	_fit_body()
	if not is_nan(heading):
		facing = heading
		_present_facing()
	reset_physics_interpolation()
	teleported.emit()


## Kills the character: it goes limp into its ragdoll, which keeps the body's momentum, and it
## ignores every gameplay input until `revive()`. The camera's target follows the hips. When the
## ragdoll declines (`CharacterRagdoll.can_start()`: too many limp already, or too far from the
## one who watches, whom the `controller` names) the character plays its death clip and lies in
## the clip's last pose (`died_by_clip`). With `shot` (the hit that killed) the hit is said in
## `hit_received` once the body is limp, so the `HitReaction` throws the hit bone along it.
func die(shot: HitRecord = null) -> void:
	CharacterDeath.die(self, shot)


## Gets the character up where its body lies, facing the way its chest faces; the pose blends
## from lying to standing over the ragdoll's `get_up_time`.
func revive() -> void:
	CharacterDeath.revive(self)


## True while the character is dead.
func is_dead() -> bool:
	return state == State.DEAD


## Hurts the character with a blow of `amount` from `source`: takes the health, stops it for
## `hit_stun_time` and throws it away from `source`. A dead character takes no hit.
func hit(amount: float = 1.0, source: Node3D = null) -> void:
	take_hit(HitRecord.blow(amount, source))


## Takes a hit (from `HitZones` or a network): the `Health` child takes it, and at zero it dies.
## A blow (`record.knockback`) also stops and throws the character. A dead character takes no
## damage, but the record is still said (`hit_received`): a shot pushes the lying body.
func take_hit(record: HitRecord) -> void:
	if state == State.DEAD:
		hit_received.emit(record)
		return
	took_hit.emit(record.damage, record.source)
	if Health.of(self) != null:
		Health.of(self).apply(record)
	if state == State.DEAD:
		return
	if record.knockback:
		_stagger(record.source)
	hit_received.emit(record)


func _stagger(source: Node3D) -> void:
	_action_lock = tuning.hit_stun_time
	var away := Vector3.ZERO
	if source != null:
		away = global_position - source.global_position
		away.y = 0.0
	if away.length_squared() < 0.0001:
		away = -Vector3.FORWARD.rotated(Vector3.UP, facing)
	velocity = away.normalized() * tuning.knockback_speed
	state = State.HIT


func _get_configuration_warnings() -> PackedStringArray:
	if Health.of(self) == null:
		return PackedStringArray(["No `Health` child: hits push the body but take nothing."])
	return PackedStringArray()


## Where the character faces on the map plane, for a minimap's arrow (the body turns inside this
## node).
func get_minimap_heading() -> Vector2:
	return Vector2(sin(facing), cos(facing))


## Uses the nearest `Interactable` in front: returns the node it makes usable, or null.
func interact() -> Node3D:
	var forward := Vector3.BACK.rotated(Vector3.UP, facing)
	var target := _interactor.find_target(forward, tuning.interact_reach)
	if target == null or _action_lock > 0.0 or state == State.DEAD:
		return null
	target.interact(self)
	_action_lock = tuning.interact_time
	interacted.emit(target.usable())
	state = State.INTERACT
	return target.usable()


## Adds `amount` of `item_id` to `items` (a `Pickup` the body touches gives it).
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


## The height of the capsule now, in metres: the standing height, or less while it crouches or
## lies down or slides.
func body_height() -> float:
	return CharacterCapsule.height(self)


## True when nothing is above the character that would stop it from standing up.
func has_room_to_stand() -> bool:
	return CharacterCapsule.has_room_to_stand(self, _stand_probe)


# The command of a body nobody controls: it asks for nothing and looks where it looked.
func _idle_command() -> PlayerCommand:
	last_command.clear()
	return last_command


# True when `delta` is a whole number of the steps the engine moves this body by.
func _is_physics_step(delta: float) -> bool:
	var ticks := delta / get_physics_process_delta_time()
	return ticks > 0.5 and is_equal_approx(ticks, roundf(ticks))


func _aim_origin() -> Vector3:
	return last_command.origin if last_command.has_shot else _camera_target.global_position


func _aim_direction() -> Vector3:
	if last_command.has_shot:
		return CommandCodec.direction_from_angles(
			last_command.shot_yaw, _prone.held_pitch(prone_tuning, last_command.shot_pitch)
		)
	return CommandCodec.direction_from_angles(view_yaw, view_pitch)


# The model shows `facing`. Called from the physics tick, so the engine smooths the turn between
# ticks; a body with no model (a server's) only keeps the number.
func _present_facing() -> void:
	if model != null:
		model.rotation.y = facing


# Out of the map: says `fell` once and waits to be put somewhere.
func _fall_out() -> void:
	if _fallen:
		return
	_fallen = true
	fell.emit()


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


# Sizes the capsule and the camera's target for the crouch, the slide and the stance.
func _fit_body() -> void:
	CharacterCapsule.fit(self)


# Lies down or gets up as the command asks (`CharacterProne`), and fits the capsule as it goes.
func _update_prone(delta: float) -> void:
	var before := _prone.amount
	if _prone.step(self, last_command.prone, _grounded, delta):
		prone_changed.emit(_prone.down)
	if _prone.amount != before:
		_fit_body()


func _update_crouch(delta: float) -> void:
	_wants_crouch = last_command.crouch
	# A lying body is crouched underneath: getting up ends crouched, and stands only with room.
	var should := (_wants_crouch and not _slide.active) or _prone.is_prone()
	# Letting go under a low ceiling keeps the character crouched until there is room; a slide
	# that ends under one crouches.
	var low := crouching or (_slide.amount > 0.0 and not _slide.active)
	if not should and low and not has_room_to_stand():
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
	if weapon != null and _action_lock <= 0.0 and _prone_lets_aim():
		fire_held = last_command.fire and _prone_lets_fire()
		aim_held = last_command.aim
		wants = aim_held or fire_held
		if _slide.active and not slide_tuning.can_shoot:
			aim_held = false
			fire_held = false
			wants = false
	else:
		aim_held = false
		fire_held = false
	if wants != aiming:
		aiming = wants
		aim_changed.emit(aiming)
	aim_amount = move_toward(
		aim_amount, 1.0 if aiming else 0.0, delta / maxf(tuning.aim_pose_time, 0.001)
	)


func _tick_timers(delta: float) -> void:
	_action_lock = maxf(_action_lock - delta, 0.0)
	_land_timer = maxf(_land_timer - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if _grounded:
		_coyote = tuning.coyote_time
	else:
		_coyote = maxf(_coyote - delta, 0.0)
	if last_command.jump_pressed:
		_jump_buffer = tuning.jump_buffer_time


## The move direction in world space, as long as the stick is pushed (0 to 1): the command's
## push turned by its view's heading.
func _wish_direction() -> Vector3:
	if last_command.move.is_zero_approx():
		return Vector3.ZERO
	return last_command.world_move()


# Lying down, the character aims only when the prone tuning allows it, and never while it goes
# down or gets up.
func _prone_lets_aim() -> bool:
	if not _prone.is_prone():
		return true
	return prone_tuning.aim_allowed and not _prone.is_changing()


func _prone_lets_fire() -> bool:
	return not _prone.is_prone() or prone_tuning.fire_allowed


func _target_speed(strength: float) -> float:
	if _prone.is_prone():
		var crawl := _prone.crawl_speed(
			prone_tuning, maxf(strength, tuning.least_walk_share), _wish_direction(), facing, aiming
		)
		return minf(crawl, _push_cap) if _push_cap > 0.0 else crawl
	var speed := tuning.run_speed * strength
	if crouching:
		speed = tuning.crouch_speed * maxf(strength, tuning.least_walk_share)
	elif last_command.sprint and not aiming:
		speed = tuning.sprint_speed
	elif last_command.walk or strength < tuning.walk_below_push:
		speed = tuning.walk_speed * maxf(strength, tuning.least_walk_share)
	if aiming:
		speed = minf(speed, tuning.walk_speed * tuning.aim_walk_cap) * tuning.aim_move_scale
	if _push_cap > 0.0:
		speed = minf(speed, _push_cap)
	return speed


func _steer(wish: Vector3, delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var strength := wish.length()
	var goal := wish.normalized() * _target_speed(strength) if strength > 0.0 else Vector3.ZERO
	var rate := tuning.acceleration if strength > 0.0 else tuning.deceleration
	if _prone.is_prone():
		rate = prone_tuning.acceleration if strength > 0.0 else prone_tuning.deceleration
	if not _grounded:
		rate *= tuning.air_control
		goal = _slide.air_goal(self, wish, goal, delta)
	if _action_lock > 0.0 and state == State.HIT:
		rate = 0.0
	flat = flat.move_toward(goal, rate * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	if aiming and _action_lock <= 0.0:
		# Aiming turns the body to the view's heading, however it walks.
		var aim_turn := prone_tuning.aim_turn_speed if _prone.is_prone() else tuning.aim_turn_speed
		facing = lerp_angle(facing, view_yaw + PI, clampf(aim_turn * delta, 0.0, 1.0))
		_present_facing()
	elif strength > 0.0 and _action_lock <= 0.0:
		var turn := prone_tuning.turn_speed if _prone.is_prone() else tuning.turn_speed
		facing = lerp_angle(facing, atan2(wish.x, wish.z), clampf(turn * delta, 0.0, 1.0))
		_present_facing()


func _vertical(delta: float) -> void:
	var airborne := not _grounded
	if airborne:
		var gravity_scale := tuning.fall_gravity_scale if velocity.y < 0.0 else 1.0
		velocity.y = maxf(
			velocity.y - tuning.gravity() * gravity_scale * delta, -tuning.terminal_speed
		)
		_fall_speed = maxf(_fall_speed, -velocity.y)
	elif velocity.y < 0.0:
		velocity.y = 0.0
	if (
		_jump_buffer > 0.0
		and _coyote > 0.0
		and _action_lock <= 0.0
		and not crouching
		and (slide_tuning.jump or not _slide.active)
	):
		velocity.y = _slide.jump(self) if _slide.active else tuning.jump_speed()
		_jump_buffer = 0.0
		_coyote = 0.0
		_jump_held = true
		jumped.emit()
	if _jump_held and velocity.y > 0.0 and not last_command.jump:
		velocity.y = minf(velocity.y, tuning.jump_speed() * tuning.short_jump_scale)
		_jump_held = false
	if velocity.y <= 0.0:
		_jump_held = false
	# Snapping to the floor would pull the body back down in the tick it jumps.
	floor_snap_length = tuning.snap_length if velocity.y <= 0.0 else 0.0


func _climb(delta: float) -> void:
	if not _grounded:
		return
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	StepClimber.climb(
		self, motion, tuning.step_height, tuning.max_slope, tuning.radius + tuning.step_probe_margin
	)


func _after_move(wish: Vector3, _delta: float) -> void:
	var grounded := _grounded
	_slide.after_move(self, grounded and _was_airborne)
	if grounded and _was_airborne:
		landed.emit(_fall_speed)
		if _fall_speed >= tuning.land_clip_speed:
			_land_timer = tuning.land_time
		_fall_speed = 0.0
	_was_airborne = not grounded
	_sprinting = (
		grounded
		and not crouching
		and not aiming
		and not _slide.active
		and last_command.sprint
		and ground_speed() > tuning.run_speed
	)
	state = _pick_state(grounded, wish)


func _pick_state(grounded: bool, wish: Vector3) -> State:
	if _action_lock > 0.0 and (state == State.HIT or state == State.INTERACT):
		return state
	var picked := State.IDLE
	if not grounded:
		picked = State.JUMP if velocity.y > 0.0 else State.FALL
	elif _slide.active:
		picked = State.SLIDE
	elif _land_timer > 0.0:
		picked = State.LAND
	elif _prone.is_prone():
		picked = State.PRONE
	elif crouching:
		picked = State.CROUCH
	elif _pushing and not wish.is_zero_approx():
		picked = State.PUSH
	elif ground_speed() >= tuning.stand_speed:
		picked = (
			State.WALK if ground_speed() <= tuning.walk_speed + tuning.run_above_walk else State.RUN
		)
	return picked


func _use_input(delta: float) -> void:
	if last_command.interact_pressed:
		interact()
	_use_weapon(delta)


# The weapon presses (switch, reload), then the trigger: a press of the fire button waits a moment
# for the arm to come up, then shoots (or clicks on an empty magazine).
func _use_weapon(delta: float) -> void:
	_fire_buffer = maxf(_fire_buffer - delta, 0.0)
	if loadout != null:
		if last_command.unarmed_pressed:
			loadout.toggle_unarmed()
		elif last_command.next_weapon_pressed:
			loadout.next()
		elif last_command.previous_weapon_pressed:
			loadout.previous()
	if weapon == null:
		return
	if last_command.reload_pressed:
		weapon.reload()
	var pulled := last_command.fire_pressed
	if weapon.definition != null and weapon.definition.automatic and last_command.fire:
		pulled = true
	if not _prone_lets_fire():
		pulled = false
	weapon.spread_share = prone_tuning.spread_share if _prone.is_prone() else 1.0
	if pulled:
		_fire_buffer = tuning.fire_buffer_time
	if _fire_buffer > 0.0 and aiming and aim_amount >= tuning.shot_aim_amount:
		if weapon.pull(_aim_origin(), _aim_direction()) != Weapon.Pull.BUSY:
			_fire_buffer = 0.0

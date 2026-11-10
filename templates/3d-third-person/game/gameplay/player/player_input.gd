class_name PlayerInput
extends CharacterController
## The human's controller: once a physics tick it reads the input actions (keys, pad, touch) and
## the camera that draws the view, and writes them as a `PlayerCommand` for its `Player`. It is
## the only part of the character that reads `Input` or a camera; the body moves by the command
## alone, so the same body is driven by a server, a recording or an AI with another controller.
##
## It reads these actions (all devices): `move_left`, `move_right`, `move_forward`, `move_back`,
## `jump`, `sprint`, `walk`, `interact`, `crouch`, `aim`, `fire`, the weapon presses `reload`,
## `next_weapon`, `previous_weapon` and `toggle_unarmed`, and `ragdoll` (made at run time, holding
## the player's `ragdoll_key`). `Player.input_enabled` off gives a command that asks for
## nothing; the view, a crouch that was toggled on and a held jump stay.
##
## The view in the command is the camera that draws this node's viewport, so a `CameraZone` that
## takes the picture also takes the directions. Camera shake is taken out again (`camera_rig`):
## a shake is for the eye and never moves the character or its shot.

## The input action that kills and revives the character (the player's `ragdoll_key` is on it).
const RAGDOLL_ACTION := &"ragdoll"
## The weapon presses, in the order of the command's fields.
const WEAPON_ACTIONS: Array[StringName] = [
	&"reload", &"next_weapon", &"previous_weapon", &"toggle_unarmed"
]

# How many `PlayerInput` nodes hold each key on the `ragdoll` action.
static var _key_holders: Dictionary[Key, int] = {}

@export_group("Nodes")
## The character this node makes commands for: its `input_enabled`, `ragdoll_key`, crouch mode
## and weapon are read here. Empty reads the parent.
@export var player: Player

## The rig whose shake is taken out of the view. `PlayerCamera` sets it for its own player;
## empty leaves the view as the camera has it.
var camera_rig: PlayerCamera

var _crouch_latch := false
# A weapon press seen as an event since the last command (a mouse wheel's press and release
# arrive in one frame, which `is_action_just_pressed` may not see from a physics tick).
var _weapon_latches: Array[bool] = [false, false, false, false]
# Each weapon action was down at the last command.
var _weapon_down: Array[bool] = [false, false, false, false]
var _bound_key: Key = KEY_NONE


func _ready() -> void:
	if player == null:
		player = get_parent() as Player
	if player != null:
		player.died.connect(_on_died)
	bind_ragdoll_key()


func _exit_tree() -> void:
	_release_key()


func _unhandled_input(event: InputEvent) -> void:
	for index in WEAPON_ACTIONS.size():
		var action := WEAPON_ACTIONS[index]
		if InputMap.has_action(action) and event.is_action_pressed(action):
			_weapon_latches[index] = true


## Puts the player's `ragdoll_key` on the `ragdoll` action, in place of the key this node put
## there before. The player calls it when the key changes. The action is the project's, shared
## by every `PlayerInput`: a key stays on it as long as one of them holds it.
func bind_ragdoll_key() -> void:
	if not is_inside_tree():
		return
	if not InputMap.has_action(RAGDOLL_ACTION):
		InputMap.add_action(RAGDOLL_ACTION)
	_release_key()
	_bound_key = player.ragdoll_key if player != null else KEY_NONE
	if _bound_key == KEY_NONE:
		return
	var holders: int = _key_holders.get(_bound_key, 0)
	if holders == 0:
		InputMap.action_add_event(RAGDOLL_ACTION, _key_event(_bound_key))
	_key_holders[_bound_key] = holders + 1


# Lets go of the key this node holds on the action; the last holder takes it off.
func _release_key() -> void:
	if _bound_key == KEY_NONE:
		return
	var holders: int = _key_holders.get(_bound_key, 0) - 1
	if holders <= 0:
		_key_holders.erase(_bound_key)
		if InputMap.has_action(RAGDOLL_ACTION):
			# The action drops the event equal to this one.
			InputMap.action_erase_event(RAGDOLL_ACTION, _key_event(_bound_key))
	else:
		_key_holders[_bound_key] = holders
	_bound_key = KEY_NONE


func _key_event(key: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	return event


func sample() -> PlayerCommand:
	var command := _command
	command.clear()
	var enabled := player == null or player.input_enabled
	var camera := get_viewport().get_camera_3d()
	var stick := Vector2.ZERO
	if enabled:
		stick = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	_write_view(command, camera, stick)
	_step_crouch(enabled)
	command.crouch = _crouch_latch
	# As before the command: a jump held when the input is turned off still rises its full height.
	command.jump = Input.is_action_pressed(&"jump")
	if not enabled:
		# Read and dropped: a button held while the input was off is no press when it comes back.
		_weapon_presses()
		return command
	command.sprint = Input.is_action_pressed(&"sprint")
	command.walk = Input.is_action_pressed(&"walk")
	command.aim = Input.is_action_pressed(&"aim")
	command.fire = Input.is_action_pressed(&"fire")
	command.jump_pressed = Input.is_action_just_pressed(&"jump")
	command.fire_pressed = Input.is_action_just_pressed(&"fire")
	command.interact_pressed = Input.is_action_just_pressed(&"interact")
	# The action exists: `_ready` made it.
	command.ragdoll_pressed = Input.is_action_just_pressed(RAGDOLL_ACTION)
	var presses := _weapon_presses()
	command.reload_pressed = presses[0]
	command.next_weapon_pressed = presses[1]
	command.previous_weapon_pressed = presses[2]
	command.unarmed_pressed = presses[3]
	if camera != null and player != null and player.shot_wanted(command):
		_write_shot(command, camera)
	return command


## The camera that draws this node's viewport, where it is; `Vector3.INF` with none.
func viewer_position() -> Vector3:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	return camera.global_position if camera != null else Vector3.INF


# Each weapon action pressed since the last command, and the latches emptied. A press is the
# action going down between two commands (a key, a pad button, a touch button's
# `Input.action_press`), or a press seen as an event while the action is up again (a wheel notch,
# down and up in one frame): never both for one press, whichever arrives first.
func _weapon_presses() -> Array[bool]:
	var presses: Array[bool] = []
	for index in WEAPON_ACTIONS.size():
		var action := WEAPON_ACTIONS[index]
		var down := InputMap.has_action(action) and Input.is_action_pressed(action)
		var went_down := down and not _weapon_down[index]
		presses.append(went_down or (_weapon_latches[index] and not down))
		_weapon_down[index] = down
	_weapon_latches.fill(false)
	return presses


# The view and the push. With a camera the view is the camera's and the stick is already in its
# axes. With none the view is the way the body faces and the stick is in the world's axes (right
# is +X, forward is -Z), as a character with no camera has always moved.
func _write_view(command: PlayerCommand, camera: Camera3D, stick: Vector2) -> void:
	if camera != null:
		var forward := -camera.global_basis.z
		if Vector2(forward.x, forward.z).length_squared() >= 0.0001:
			var shake := _shake(camera)
			command.yaw = atan2(-forward.x, -forward.z) - shake.y
			command.pitch = asin(clampf(forward.normalized().y, -1.0, 1.0)) - shake.x
			command.move = Vector2(stick.x, -stick.y)
			return
	command.yaw = player.facing - PI if player != null else 0.0
	command.pitch = 0.0
	var turn := command.yaw
	command.move = Vector2(
		stick.x * cos(turn) - stick.y * sin(turn), -stick.x * sin(turn) - stick.y * cos(turn)
	)


# The crosshair's ray: from the camera through the middle of the screen (an over-the-shoulder
# view shifts the lens, so this is not the camera's own axis).
func _write_shot(command: PlayerCommand, camera: Camera3D) -> void:
	var centre := get_viewport().get_visible_rect().size / 2.0
	var angles := CommandCodec.direction_angles(camera.project_ray_normal(centre))
	var shake := _shake(camera)
	command.has_shot = true
	command.origin = camera.project_ray_origin(centre)
	command.shot_yaw = angles.x - shake.y
	command.shot_pitch = angles.y - shake.x
	command.view_tick = 0


# The shake of the player's own rig as turns in radians (x up, y about the up axis), when it is
# the rig's camera that draws; zero otherwise.
func _shake(drawn: Camera3D) -> Vector2:
	if camera_rig == null or not is_instance_valid(camera_rig) or camera_rig.camera != drawn:
		return Vector2.ZERO
	var degrees := camera_rig.current_shake()
	return Vector2(deg_to_rad(degrees.x), deg_to_rad(degrees.y))


# The crouch button as a held bit: in toggle mode a press switches it, in hold mode it is the
# button. With the input off a toggled crouch stays and a held one lets go.
func _step_crouch(enabled: bool) -> void:
	var toggle := player != null and player.tuning != null and player.tuning.crouch_toggle
	if toggle:
		if enabled and Input.is_action_just_pressed(&"crouch"):
			_crouch_latch = not _crouch_latch
	else:
		_crouch_latch = enabled and Input.is_action_pressed(&"crouch")


func _on_died() -> void:
	_crouch_latch = false

class_name PlayerInput
extends CharacterController
## The human's controller: once a physics tick it reads the input actions (keys, pad, touch) and
## the camera that draws the view, and writes them as a `PlayerCommand` for its `Player`. It is
## the only part of the character that reads `Input` or a camera; the body moves by the command
## alone, so the same body is driven by a server, a recording or an AI with another controller.
##
## It reads these actions (all devices): `move_left`, `move_right`, `move_forward`, `move_back`,
## `jump`, `sprint`, `walk`, `interact`, `crouch`, `prone`, `aim`, `fire`, the weapon presses
## `reload`, `next_weapon`, `previous_weapon` and `toggle_unarmed`, the melee button `melee`, and
## `ragdoll` (made at run time,
## holding the player's `ragdoll_key`). A weapon chosen on a screen (`request_weapon`) is sent as
## those same weapon presses, one a tick, so a screen adds nothing to the command. The number keys
## of the HUD's places (`QuickKeys`: `weapon_1`, `weapon_2`, `hotbar_1`...) request the place's
## weapon the same way and use a hotbar place: the command's `use_place`, which the player's
## `ItemUse` reads after the step (a player with none uses its `Hotbar` at once).
## `Player.input_enabled` off gives a command that asks for nothing; the view, a crouch or prone
## that was toggled on and a held jump stay. How prone is asked for (a toggle, a hold, a long hold
## of crouch) is the player's `ProneTuning.input_mode`.
##
## The view in the command is the camera that draws this node's viewport, so a `CameraZone` that
## takes the picture also takes the directions. Camera shake is taken out again (`camera_rig`):
## a shake is for the eye and never moves the character or its shot.

## The input action that kills and revives the character (the player's `ragdoll_key` is on it).
const RAGDOLL_ACTION := &"ragdoll"
## The weapon presses, in the order of the command's fields (the melee button last, gdstudio
## #1254).
const WEAPON_ACTIONS: Array[StringName] = [
	&"reload", &"next_weapon", &"previous_weapon", &"toggle_unarmed", &"melee"
]

## No weapon asked for by `request_weapon` (-1 is the empty hands).
const NO_REQUEST := -2
## The most ticks a weapon request presses for before it gives up (a slot that cannot be reached).
const REQUEST_TICKS := 32

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
var _weapon_latches: Array[bool] = [false, false, false, false, false]
# Each weapon action was down at the last command.
var _weapon_down: Array[bool] = [false, false, false, false, false]
var _prone_latch := false
# Seconds crouch has been held (for `HOLD_CROUCH`), and whether this press was used already.
var _crouch_held := 0.0
var _crouch_press_used := false
var _bound_key: Key = KEY_NONE
# The slot a screen asked for, and how many ticks the request has pressed.
var _wanted_slot := NO_REQUEST
var _request_ticks := 0
var _quick_keys := QuickKeys.new()


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
	_quick_keys.latch(event)


## Switches to the loadout's `slot` (`WeaponLoadout.UNARMED` for the empty hands) by the weapon
## presses a player would make, one a tick from the next command on (`WeaponChooser`). It works
## with the input turned off (a screen is up) and while the tree is paused it waits for the game.
func request_weapon(slot: int) -> void:
	_wanted_slot = slot
	_request_ticks = 0


## The slot a request is still pressing toward, or `NO_REQUEST`.
func weapon_request() -> int:
	return _wanted_slot


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
	RagdollKeyHolders.hold(RAGDOLL_ACTION, _bound_key)


# Lets go of the key this node holds on the action; the last holder takes it off
# (`RagdollKeyHolders`, shared by every `PlayerInput`; no static variable here).
func _release_key() -> void:
	if _bound_key == KEY_NONE:
		return
	RagdollKeyHolders.release(RAGDOLL_ACTION, _bound_key)
	_bound_key = KEY_NONE


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
	_step_prone(enabled)
	command.prone = _prone_latch
	# As before the command: a jump held when the input is turned off still rises its full height.
	command.jump = Input.is_action_pressed(&"jump")
	if not enabled:
		# Read and dropped: a button held while the input was off is no press when it comes back.
		_weapon_presses()
		_quick_keys.pressed(QuickKeys.WEAPON_ACTION)
		_quick_keys.pressed(QuickKeys.HOTBAR_ACTION)
		_press_requested(command)
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
	command.melee_pressed = presses[4]
	_press_places(command)
	_press_requested(command)
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


# The HUD's places pressed since the last command: a weapon place requests its weapon, a hotbar
# place is the command's `use_place` (the player's `ItemUse` reads it after the step, as a server
# does: an item that takes time is one use a press, and a press during a use does nothing).
func _press_places(command: PlayerCommand) -> void:
	for place in _quick_keys.pressed(QuickKeys.WEAPON_ACTION):
		var slot := QuickKeys.weapon_slot_at(player.loadout if player != null else null, place)
		if slot != QuickKeys.NO_SLOT:
			request_weapon(slot)
	var hotbar := Hotbar.of(player)
	var user := ItemUse.of(player)
	for place in _quick_keys.pressed(QuickKeys.HOTBAR_ACTION):
		if user != null:
			if command.use_place < 0:
				command.use_place = place
		elif hotbar != null:
			hotbar.use(place)


# Adds the press a weapon request needs this tick, and ends the request once the loadout is heading
# for the slot (or after `REQUEST_TICKS`).
func _press_requested(command: PlayerCommand) -> void:
	if _wanted_slot == NO_REQUEST:
		return
	var press := WeaponChooser.NONE
	if player != null and player.loadout != null:
		press = WeaponChooser.press_toward(player.loadout, _wanted_slot)
	_request_ticks += 1
	if press == WeaponChooser.NONE or _request_ticks > REQUEST_TICKS:
		_wanted_slot = NO_REQUEST
	match press:
		WeaponChooser.NEXT:
			command.next_weapon_pressed = true
		WeaponChooser.PREVIOUS:
			command.previous_weapon_pressed = true
		WeaponChooser.UNARMED:
			command.unarmed_pressed = true


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


# The prone button as a held bit, in the player's `ProneTuning.input_mode`: a press switches it,
# or it is the button, or (`HOLD_CROUCH`) crouch held `crouch_hold_time` lies down and a press of
# crouch while down gets up. A jump or a sprint press gets up when the tuning says so. With the
# input off a toggled prone stays and a held one lets go.
func _step_prone(enabled: bool) -> void:
	var tuning := player.prone_tuning if player != null else null
	if tuning == null:
		_prone_latch = false
		return
	var mode := tuning.input_mode
	if not enabled:
		_crouch_held = 0.0
		if mode == ProneTuning.InputMode.HOLD:
			_prone_latch = false
		return
	if mode == ProneTuning.InputMode.HOLD:
		_prone_latch = Input.is_action_pressed(&"prone")
	elif Input.is_action_just_pressed(&"prone"):
		_prone_latch = not _prone_latch
	if mode == ProneTuning.InputMode.HOLD_CROUCH:
		_step_crouch_hold(tuning)
	var up := tuning.jump_gets_up and Input.is_action_just_pressed(&"jump")
	up = up or tuning.sprint_gets_up and Input.is_action_just_pressed(&"sprint")
	if up:
		_prone_latch = false


# A long hold of crouch lies down; a press of crouch while down gets up (and does not lie down
# again while it is held).
func _step_crouch_hold(tuning: ProneTuning) -> void:
	if Input.is_action_just_pressed(&"crouch"):
		_crouch_held = 0.0
		_crouch_press_used = _prone_latch
		_prone_latch = false
	if not Input.is_action_pressed(&"crouch"):
		_crouch_held = 0.0
		return
	if _crouch_press_used:
		return
	_crouch_held += get_physics_process_delta_time()
	if _crouch_held >= tuning.crouch_hold_time:
		_prone_latch = true
		_crouch_press_used = true


func _on_died() -> void:
	_crouch_latch = false
	_prone_latch = false

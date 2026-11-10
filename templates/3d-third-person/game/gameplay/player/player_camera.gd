@tool
class_name PlayerCamera
extends Node3D
## The third-person camera: a thin wrapper that sets the high-level tuning on a Phantom Camera
## (`FollowCamera`, a `PhantomCamera3D` in Third Person follow mode) and turns it to the
## player's orbit input. Phantom Camera does the work: it follows `target`, keeps the lens out
## of walls with its spring arm, damps the follow and blends to another camera when one has a
## higher `priority`.
##
## The over-the-shoulder view is the `shoulder` setting (left, center or right, `shoulder_offset`
## to the side and `vertical_offset` up): it writes the Camera node's own H Offset and V Offset,
## which shift the view without moving the camera or its wall cast, and nothing else writes
## them. Sprinting zooms the view out a little and can shake it; aiming and firing bring the
## camera in to a narrower field of view, and a shot can kick it. All of them blend smoothly in and
## out and sit on top of the framing below, so `distance`, `offset` and `field_of_view` stay the
## resting view. The shakes are the game's `CameraShake` (`shaker`): this rig holds the sprint
## shake on it, kicks it on each shot and applies its turn; anything else in the game shakes the
## same view with `CameraShake.shake(preset, at)`.
##
## Orbit comes from the mouse (while it is captured), the right stick (`look_*` actions) and
## touch (`TouchControls.look_turned`, connected in the scene to `orbit()`). The character turns
## to its move direction on its own (`Player`), so the camera never drags it.
##
## It is a `@tool` script, so the framing, follow and wall settings move the Phantom Camera in the
## editor too (open `ui/player_rig/player_rig.tscn` and change `distance` or
## `field_of_view`). Only that setup runs there, never the orbit or the input.

## The orbit angles changed; `yaw` and `pitch` are in degrees.
signal orbited(yaw: float, pitch: float)

## Which side of the character the view sits on.
enum Shoulder { LEFT, CENTER, RIGHT }

## The Phantom Camera properties this wrapper sets from its own exports. This node is the one
## place to tune the camera: nobody needs to open the Phantom Camera node for these.
const _FORWARDED: Array[StringName] = [
	&"spring_length",
	&"collision_mask",
	&"margin",
	&"follow_offset",
	&"priority",
	&"shape",
	&"follow_damping",
	&"follow_damping_value",
]

@export_group("Nodes")
## What the camera follows and looks at: the player's `CameraTarget` (a point at head height).
@export var target: Node3D:
	set(value):
		target = value
		if is_instance_valid(_pcam):
			_pcam.follow_target = target
		update_configuration_warnings()
## The Phantom Camera that does the work: a `PhantomCamera3D` in Third Person follow mode, the
## wrapper's child. The addon moves it under its own spring arm at run time; this keeps the
## reference.
@export var follow_camera: PhantomCamera3D:
	set(value):
		follow_camera = value
		update_configuration_warnings()
## The `Camera3D` that draws the scene (the Phantom Camera host's camera). Its H Offset and V
## Offset are the over-the-shoulder view this wrapper sets from the Shoulder group.
@export var camera: Camera3D:
	set(value):
		camera = value
		update_configuration_warnings()

## The shake component that works out the shake: the sprint shake and the shot kick are held on it
## and the turn it gives is put on the view. Anything may call `CameraShake.shake()` to shake it
## too. Empty makes one at run time.
@export var shaker: CameraShake

## The character whose sprint and aim the camera follows. Empty looks at the parent of `target`.
@export var player: Player

@export_group("Framing")
## How far behind the target the lens sits.
@export_range(1.0, 12.0, 0.05, "suffix:m") var distance := 1.7:
	set(value):
		distance = value
		_forward()
## Where the camera's arm starts, from the target's point, in world axes (x east, y up, z south).
## It moves the arm and its wall cast, so keep it near zero sideways: the over-the-shoulder view
## is the Shoulder group's, which does not move the cast.
@export_custom(PROPERTY_HINT_RANGE, "-3,3,0.01,suffix:m") var offset := Vector3(0.0, 0.1, 0.0):
	set(value):
		offset = value
		_forward()
## The lens's field of view.
@export_range(30.0, 110.0, 0.5, "suffix:deg") var field_of_view := 62.0:
	set(value):
		field_of_view = value
		_forward()
## The nearest distance the lens draws.
@export_range(0.01, 5.0, 0.01, "suffix:m") var near_clip := 0.05:
	set(value):
		near_clip = value
		_forward()
## The farthest distance the lens draws.
@export_range(10.0, 4000.0, 1.0, "or_greater", "suffix:m") var far_clip := 4000.0:
	set(value):
		far_clip = value
		_forward()
## The angle looking down at the start: positive looks down at the character.
@export_range(-80.0, 80.0, 0.5, "suffix:deg") var start_pitch := 14.0

@export_group("Shoulder")
## The side of the character the view sits on. It sets the Camera node's H Offset to
## `-shoulder_offset` (left), 0 (center) or `shoulder_offset` (right).
@export var shoulder := Shoulder.RIGHT:
	set(value):
		shoulder = value
		if Engine.is_editor_hint():
			_shoulder_pos = _shoulder_side()
		_forward_view()
## How far to the side the view sits on the left and right shoulder (the Camera node's H Offset).
@export_range(0.0, 2.0, 0.01, "suffix:m") var shoulder_offset := 0.5:
	set(value):
		shoulder_offset = value
		_forward_view()
## How far up the view sits (the Camera node's V Offset).
@export_range(-1.0, 1.0, 0.01, "suffix:m") var vertical_offset := 0.0:
	set(value):
		vertical_offset = value
		_forward_view()
## Seconds the view takes to cross from one shoulder to the other.
@export_range(0.0, 3.0, 0.05, "suffix:s") var shoulder_time := 0.3

@export_group("Sprint")
## How much wider the field of view gets at a full sprint.
@export_range(-20.0, 30.0, 0.5, "suffix:deg") var sprint_fov_change := 6.0:
	set(value):
		sprint_fov_change = value
		_forward_blend()
## How much farther behind the target the lens sits at a full sprint.
@export_range(-3.0, 3.0, 0.05, "suffix:m") var sprint_distance_change := 0.4:
	set(value):
		sprint_distance_change = value
		_forward_blend()
## How fast the view zooms in and out of the sprint view (1 is a second, 4 a quarter of one).
@export_range(0.5, 20.0, 0.1, "suffix:/s") var sprint_zoom_speed := 3.0

@export_subgroup("Sprint shake")
## How far the sprint rocks the view up and down, in degrees (the sideways turn and roll are
## smaller shares of it). Zero is off; 0.3 is subtle.
@export_range(0.0, 2.0, 0.01, "suffix:deg") var sprint_shake_amplitude := 0.0
## Steps a second of the shake: one bob for each foot that lands (the sprint clip lands three).
@export_range(0.5, 8.0, 0.05, "suffix:Hz") var sprint_shake_frequency := 3.0
## How fast the shake builds up and dies down (1 is a second).
@export_range(0.5, 20.0, 0.1, "suffix:/s") var sprint_shake_blend := 4.0

@export_group("Slide")
## How much wider the field of view gets while the character slides, on top of the sprint view
## (Titanfall 2 widens its view by a tenth over a quarter of a second). The camera's height
## follows the character's target, which the tuning's `slide_camera_height` lowers.
@export_range(-20.0, 30.0, 0.5, "suffix:deg") var slide_fov_change := 5.0:
	set(value):
		slide_fov_change = value
		_forward_blend()
## How fast the view widens into the slide and back (4 is a quarter of a second).
@export_range(0.5, 20.0, 0.1, "suffix:/s") var slide_zoom_speed := 4.0

@export_group("Aim")
## How far behind the target the lens sits while aiming.
@export_range(0.5, 8.0, 0.05, "suffix:m") var aim_distance := 1.1:
	set(value):
		aim_distance = value
		_forward_blend()
## Aiming also moves the view to `aim_shoulder`. Off keeps the shoulder view as it is and only
## zooms in and out (distance and field of view).
@export var aim_shifts_shoulder := false:
	set(value):
		aim_shifts_shoulder = value
		_forward_view()
## How far to the side of the character the view sits while aiming (on the chosen shoulder), when
## `aim_shifts_shoulder` is on.
@export_range(0.0, 2.0, 0.01, "suffix:m") var aim_shoulder := 0.7:
	set(value):
		aim_shoulder = value
		_forward_view()
## The field of view while aiming.
@export_range(20.0, 110.0, 0.5, "suffix:deg") var aim_fov := 50.0:
	set(value):
		aim_fov = value
		_forward_blend()
## How fast the view comes in to the aim view (1 is a second, 8 an eighth of one).
@export_range(0.5, 30.0, 0.1, "suffix:/s") var aim_in_speed := 8.0
## How fast the view goes back out.
@export_range(0.5, 30.0, 0.1, "suffix:/s") var aim_out_speed := 6.0

@export_group("Fire")
## Firing without aiming zooms the view in. Off leaves the framing alone while firing.
@export var zoom_when_firing := true
## How far behind the target the lens sits while the fire button is held.
@export_range(0.5, 8.0, 0.05, "suffix:m") var fire_distance := 1.4:
	set(value):
		fire_distance = value
		_forward_blend()
## The field of view while the fire button is held.
@export_range(20.0, 110.0, 0.5, "suffix:deg") var fire_fov := 56.0:
	set(value):
		fire_fov = value
		_forward_blend()
## How fast the view comes in while firing (1 is a second, 8 an eighth of one).
@export_range(0.5, 30.0, 0.1, "suffix:/s") var fire_in_speed := 8.0
## How fast the view goes back out once the fire button is let go.
@export_range(0.5, 30.0, 0.1, "suffix:/s") var fire_out_speed := 6.0

@export_subgroup("Shot kick")
## How far one shot kicks the view, in degrees (the largest turn up and down; a burst adds up to
## twice that, and the sideways turn and roll are smaller shares). Zero is off; 0.3 is subtle.
@export_range(0.0, 2.0, 0.01, "suffix:deg") var shot_kick_amplitude := 0.0
## Seconds a kick takes to die away.
@export_range(0.05, 1.0, 0.01, "suffix:s") var shot_kick_duration := 0.2

@export_group("Follow")
## Smooths the camera's follow of a moving target.
@export var follow_damping := true:
	set(value):
		follow_damping = value
		_forward()
## How heavy that smoothing is: higher lags more.
@export_range(0.0, 1.0, 0.01) var follow_damping_amount := 0.06:
	set(value):
		follow_damping_amount = value
		_forward()

@export_group("Orbit")
## Mouse turn per pixel, in degrees (the mouse must be captured).
@export_range(0.01, 1.0, 0.01, "suffix:deg/px") var mouse_sensitivity := 0.12
## Right stick turn at full push, in degrees a second.
@export_range(10.0, 720.0, 1.0, "suffix:deg/s") var stick_speed := 180.0
## How far down the camera can look.
@export_range(-89.0, 0.0, 0.5, "suffix:deg") var min_pitch := -55.0
## How far up the camera can look.
@export_range(0.0, 89.0, 0.5, "suffix:deg") var max_pitch := 70.0
## Looks the opposite way up and down.
@export var invert_y := false
## Takes the mouse for orbit when the screen is clicked (on a computer; touch screens never
## capture it).
@export var capture_mouse := true
## The mouse orbits only while it is captured. Off lets any mouse motion orbit (a game with its
## own cursor).
@export var require_captured_mouse := true

@export_group("Blending")
## The camera with the highest priority shows. A `CameraZone` raises a second camera above this
## one and lowers it again, so keep this higher than the zone's outside priority.
@export_range(0, 100, 1) var priority := 10:
	set(value):
		priority = value
		_forward()
## Seconds the view takes to blend back to this camera, after a `CameraZone`'s camera had it.
@export_range(0.0, 10.0, 0.05, "suffix:s") var blend_duration := 1.2:
	set(value):
		blend_duration = value
		_forward()
## The curve of that blend.
@export var blend_transition := PhantomCameraTween.TransitionType.SINE:
	set(value):
		blend_transition = value
		_forward()
## Where on the curve the blend is slow.
@export var blend_ease := PhantomCameraTween.EaseType.EASE_IN_OUT:
	set(value):
		blend_ease = value
		_forward()

@export_group("Walls")
## The physics layers that push the lens in (the spring arm's mask): the level and props
## (`PhysicsLayers.CAMERA_MASK`), never a character, a ragdoll bone or a hit zone.
@export_flags_3d_physics var wall_mask := PhysicsLayers.CAMERA_MASK:
	set(value):
		wall_mask = value
		_forward()
## The shape the spring arm sweeps to find a wall. Empty sweeps a ray: a sphere keeps the lens
## from slipping through a gap.
@export var wall_shape: Shape3D:
	set(value):
		wall_shape = value
		_forward()
## How far the lens stays from a wall it was pushed in by.
@export_range(0.0, 1.0, 0.01, "suffix:m") var wall_margin := 0.25:
	set(value):
		wall_margin = value
		_forward()

## The horizontal orbit angle in degrees (0 looks along -Z).
var yaw := 0.0
## The vertical orbit angle in degrees; positive looks down at the target.
var pitch := 0.0

## The player's own mouse setting (the settings screen, through `LookSettings`): a factor on
## `mouse_sensitivity`, 1 being the value set above. The mouse only; the stick and touch keep
## theirs.
var player_sensitivity := 1.0
## The player's own invert setting: flips the vertical look on top of `invert_y`.
var player_invert_y := false
var _arm_waited := 0
var _sprint_blend := 0.0
var _slide_blend := 0.0
var _aim_blend := 0.0
var _fire_blend := 0.0
var _shoulder_pos := 1.0
var _arm_ready := false
var _sprint_shake := ShakePreset.new()
var _shot_kick := ShakePreset.new()

var _pcam: PhantomCamera3D
var _player: Player


func _enter_tree() -> void:
	# Before the Phantom Camera is ready: it builds its spring arm from these values.
	var pcam := follow_camera
	if pcam == null:
		return
	_pcam = pcam
	pcam.follow_mode = PhantomCamera3D.FollowMode.THIRD_PERSON
	pcam.follow_target = target
	if pcam.camera_3d_resource == null:
		pcam.camera_3d_resource = Camera3DResource.new()
	_forward()


func _notification(what: int) -> void:
	if not Engine.is_editor_hint() or not is_instance_valid(_pcam):
		return
	# The settings below are the wrapper's: the scene file must not keep a copy on the Phantom
	# Camera (nor the view the editor moves it to), so they come off while the scene is written
	# and go back on after.
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		for property in _FORWARDED:
			_pcam.set(property, _pcam.get_script().get_property_default_value(property))
		_pcam.transform = Transform3D.IDENTITY
		var plain := PhantomCameraTween.new()
		_pcam.tween_duration = plain.duration
		_pcam.tween_transition = plain.transition
		_pcam.tween_ease = plain.ease
		_pcam.camera_3d_resource = null
		# The Camera node's offsets are set from the Shoulder group: the scene keeps the defaults.
		if camera != null:
			camera.h_offset = 0.0
			camera.v_offset = 0.0
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_pcam.camera_3d_resource = Camera3DResource.new()
		_forward()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	pitch = start_pitch
	_shoulder_pos = _shoulder_side()
	_player = player
	_start_shake()
	if target != null:
		var heading := target.get_parent() as Node3D
		if heading != null:
			yaw = rad_to_deg(heading.global_rotation.y)
		if heading is Player:
			(heading as Player).teleported.connect(_pcam.teleport_position)
			if _player == null:
				_player = heading as Player
	if is_instance_valid(_player) and is_instance_valid(_player.weapon):
		_player.weapon.fired.connect(_on_shot)
	# The player's input takes this rig's shake out of the view it sends: a shake is for the eye.
	var input := (_player.controller as PlayerInput) if is_instance_valid(_player) else null
	if input != null:
		input.camera_rig = self


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# The spring arm exists a frame or two after the Phantom Camera is ready.
	if _arm_waited < 3:
		_arm_waited += 1
		return
	if not _arm_ready:
		_exclude_player()
	var stick := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if not stick.is_zero_approx():
		orbit(stick * stick_speed * delta)
	advance(delta)


## Turns the camera by `degrees` (x about the up axis, y up and down). The mouse, the stick and
## the touch layer all come through here.
func orbit(degrees: Vector2) -> void:
	yaw = wrapf(yaw - degrees.x, -180.0, 180.0)
	var vertical := -degrees.y if invert_y != player_invert_y else degrees.y
	pitch = clampf(pitch + vertical, min_pitch, max_pitch)
	orbited.emit(yaw, pitch)


## Moves the sprint and aim blends `delta` seconds toward where the player is (sprinting,
## aiming), puts the blended view on the Phantom Camera and turns it. `_process` calls it every
## frame; a test calls it with the time it wants.
func advance(delta: float) -> void:
	var sliding := is_instance_valid(_player) and _player.is_sliding()
	# A slide keeps the sprint view: the speed is still there.
	var sprinting := is_instance_valid(_player) and (_player.is_sprinting() or sliding)
	# The zoom follows the buttons, not the arm: the character keeps its aim pose for a moment
	# after a shot, and the camera must not wait for that.
	var aiming := is_instance_valid(_player) and _player.aim_held
	var firing := is_instance_valid(_player) and _player.fire_held and zoom_when_firing
	_sprint_blend = move_toward(_sprint_blend, 1.0 if sprinting else 0.0, sprint_zoom_speed * delta)
	_slide_blend = move_toward(_slide_blend, 1.0 if sliding else 0.0, slide_zoom_speed * delta)
	var aim_speed := aim_in_speed if aiming else aim_out_speed
	_aim_blend = move_toward(_aim_blend, 1.0 if aiming else 0.0, aim_speed * delta)
	var fire_speed := fire_in_speed if firing else fire_out_speed
	_fire_blend = move_toward(_fire_blend, 1.0 if firing else 0.0, fire_speed * delta)
	_shoulder_pos = move_toward(
		_shoulder_pos, _shoulder_side(), delta * 2.0 / maxf(shoulder_time, 0.001)
	)
	_step_shake(sprinting and not sliding, delta)
	_forward_blend()
	_apply()


## Turns the view to the other shoulder (the left one from the right, and the right from the left
## or the center). The `shoulder_swap` action calls it.
func swap_shoulder() -> void:
	shoulder = Shoulder.LEFT if shoulder == Shoulder.RIGHT else Shoulder.RIGHT


## The distance behind the target now: `distance`, farther while sprinting, `fire_distance` while
## firing, `aim_distance` while aiming.
func current_distance() -> float:
	var sprint := distance + sprint_distance_change * _eased(_sprint_blend)
	var fire := lerpf(sprint, fire_distance, _eased(_fire_blend))
	return lerpf(fire, aim_distance, _eased(_aim_blend))


## The field of view now: `field_of_view`, wider while sprinting and sliding, `fire_fov` while
## firing, `aim_fov` while aiming.
func current_fov() -> float:
	var sprint := (
		field_of_view
		+ sprint_fov_change * _eased(_sprint_blend)
		+ slide_fov_change * _eased(_slide_blend)
	)
	var fire := lerpf(sprint, fire_fov, _eased(_fire_blend))
	return lerpf(fire, aim_fov, _eased(_aim_blend))


## Where the arm starts now: `offset`. Aiming and firing never move it.
func current_offset() -> Vector3:
	return offset


## The Camera node's H Offset (x) and V Offset (y) now: the shoulder's side times
## `shoulder_offset` (`aim_shoulder` while aiming, when `aim_shifts_shoulder` is on) and
## `vertical_offset`.
func current_view_offset() -> Vector2:
	var width := shoulder_offset
	if aim_shifts_shoulder:
		width = lerpf(shoulder_offset, aim_shoulder, _eased(_aim_blend))
	var side := 2.0 * smoothstep(0.0, 1.0, (_shoulder_pos + 1.0) * 0.5) - 1.0
	var slide := shaker.view_offset() if is_instance_valid(shaker) else Vector2.ZERO
	return Vector2(side * width, vertical_offset) + slide


## The shake right now as turns in degrees (x pitch, y yaw, z roll): the sprint shake and any
## kick or `CameraShake.shake()` call together. Zero when nothing shakes.
func current_shake() -> Vector3:
	return shaker.rotation_degrees() if is_instance_valid(shaker) else Vector3.ZERO


## How far into the slide view the camera is, 0 to 1.
func slide_blend() -> float:
	return _slide_blend


## How far into the sprint view the camera is, 0 to 1.
func sprint_blend() -> float:
	return _sprint_blend


## How far into the aim view the camera is, 0 to 1.
func aim_blend() -> float:
	return _aim_blend


## How far into the fire view the camera is, 0 to 1.
func fire_blend() -> float:
	return _fire_blend


## Kicks the view by one shot (`shot_kick_amplitude`). The player's weapon calls it through its
## `fired` signal; a weapon of your own may call it too.
func kick() -> void:
	if shot_kick_amplitude > 0.0 and is_instance_valid(shaker):
		_set_kick()
		shaker.add(_shot_kick)


## The Phantom Camera that does the work (for a game that wants its other settings).
func phantom_camera() -> PhantomCamera3D:
	return _pcam


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseMotion and _mouse_orbits():
		orbit((event as InputEventMouseMotion).relative * mouse_sensitivity * player_sensitivity)
	elif event is InputEventMouseButton and capture_mouse:
		var click := event as InputEventMouseButton
		if click.pressed and not DisplayServer.is_touchscreen_available():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif InputMap.has_action(&"pause") and event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif InputMap.has_action(&"shoulder_swap") and event.is_action_pressed(&"shoulder_swap"):
		swap_shoulder()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if target == null:
		warnings.append("Set `target`: the node the camera follows (the player's `CameraTarget`).")
	if follow_camera == null:
		warnings.append("Set `follow_camera`: a PhantomCamera3D in Third Person follow mode.")
	if camera == null:
		warnings.append("Set `camera`: the Camera3D that draws the scene (its H and V Offset).")
	return warnings


func _on_shot(_projectile: Projectile) -> void:
	kick()


# The shake component: the one in the scene, or one made now. This rig steps it.
func _start_shake() -> void:
	if not is_instance_valid(shaker):
		shaker = CameraShake.new()
		shaker.name = &"CameraShake"
		add_child(shaker)
	shaker.auto_advance = false
	_sprint_shake.wave = ShakePreset.Wave.SINE
	_sprint_shake.exponent = 1.0
	_shot_kick.trauma = 0.5
	_shot_kick.exponent = 1.0


# Holds the sprint shake at the sprint's level and steps the component. The amplitude, frequency
# and blend are read here, so a change in the inspector works while the game runs.
func _step_shake(sprinting: bool, delta: float) -> void:
	if not is_instance_valid(shaker):
		return
	var amplitude := sprint_shake_amplitude
	# Pitch once a footfall, yaw and roll once for two.
	_sprint_shake.max_rotation = Vector3(amplitude, amplitude * 0.5, amplitude * 0.67)
	_sprint_shake.frequency = sprint_shake_frequency
	_sprint_shake.blend_speed = sprint_shake_blend
	shaker.hold(&"sprint", _sprint_shake, 1.0 if sprinting and amplitude > 0.0 else 0.0)
	shaker.advance(delta)


# One shot's worth of kick: its largest turn is `shot_kick_amplitude` (a trauma of 0.5 and a
# straight curve), with smaller sideways turn and roll.
func _set_kick() -> void:
	var peak := shot_kick_amplitude * 2.0
	_shot_kick.max_rotation = Vector3(peak, peak * 0.5, peak * 0.3)
	_shot_kick.duration = shot_kick_duration
	_shot_kick.frequency = 18.0


func _mouse_orbits() -> bool:
	return not require_captured_mouse or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


# Puts the framing, follow and wall settings on the Phantom Camera. Every one of them comes
# through here from its setter, so a change in the inspector or the remote tree works while the
# game runs, not only when the scene loads.
func _forward() -> void:
	var pcam := _pcam
	if not is_instance_valid(pcam):
		return
	pcam.collision_mask = wall_mask
	pcam.margin = wall_margin
	pcam.priority = priority
	if pcam.tween_resource != null:
		pcam.tween_duration = blend_duration
		pcam.tween_transition = blend_transition
		pcam.tween_ease = blend_ease
	if pcam.shape != wall_shape:
		pcam.shape = wall_shape
	pcam.follow_damping = follow_damping
	pcam.follow_damping_value = Vector3.ONE * follow_damping_amount
	var lens := pcam.camera_3d_resource
	if lens != null:
		# Only a changed value is written: the lens tells the camera host about every write.
		if not is_equal_approx(lens.near, near_clip):
			lens.near = near_clip
		if not is_equal_approx(lens.far, far_clip):
			lens.far = far_clip
	_forward_blend()


# The part of the view that sprinting and aiming move: how far behind, how far to the side and
# how wide.
func _forward_blend() -> void:
	var pcam := _pcam
	if not is_instance_valid(pcam):
		return
	pcam.spring_length = current_distance()
	pcam.follow_offset = current_offset()
	var lens := pcam.camera_3d_resource
	if lens != null and not is_equal_approx(lens.fov, current_fov()):
		lens.fov = current_fov()
	_forward_view()


# Writes the shoulder view to the Camera node's H and V Offset. The Phantom Camera host copies
# its lens resource (with the resource's offsets) onto the Camera node whenever the resource
# changes, so the resource is kept equal to the view and nothing resets it.
func _forward_view() -> void:
	var view := current_view_offset()
	var lens: Camera3DResource = null
	if is_instance_valid(_pcam):
		lens = _pcam.camera_3d_resource
	if lens != null:
		if not is_equal_approx(lens.h_offset, view.x):
			lens.h_offset = view.x
		if not is_equal_approx(lens.v_offset, view.y):
			lens.v_offset = view.y
	if is_instance_valid(camera):
		if not is_equal_approx(camera.h_offset, view.x):
			camera.h_offset = view.x
		if not is_equal_approx(camera.v_offset, view.y):
			camera.v_offset = view.y


# -1 for the left shoulder, 0 for the center, 1 for the right.
func _shoulder_side() -> float:
	match shoulder:
		Shoulder.LEFT:
			return -1.0
		Shoulder.CENTER:
			return 0.0
	return 1.0


# The arm's cast must never hit the character it follows: an arm that starts outside the capsule
# (a sideways `offset`) would otherwise stop at its own body and put the lens in the head.
func _exclude_player() -> void:
	var arm: SpringArm3D = null
	if is_instance_valid(_pcam):
		arm = _pcam.get_parent() as SpringArm3D
	if arm == null:
		return
	_arm_ready = true
	if is_instance_valid(_player):
		arm.add_excluded_object(_player.get_rid())


func _eased(blend: float) -> float:
	return smoothstep(0.0, 1.0, blend)


func _apply() -> void:
	if not is_instance_valid(_pcam):
		return
	var shake := current_shake()
	_pcam.set_third_person_rotation_degrees(Vector3(-pitch + shake.x, yaw + shake.y, shake.z))

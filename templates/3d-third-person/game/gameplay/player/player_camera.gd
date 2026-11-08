@tool
class_name PlayerCamera
extends Node3D
## The third-person camera: a thin wrapper that sets the high-level tuning on a Phantom Camera
## (`FollowCamera`, a `PhantomCamera3D` in Third Person follow mode) and turns it to the
## player's orbit input. Phantom Camera does the work: it follows `target`, keeps the lens out
## of walls with its spring arm, damps the follow and blends to another camera when one has a
## higher `priority`.
##
## Sprinting zooms the view out a little and can shake it; aiming brings the camera in, over the
## shoulder, to a narrower field of view. Both blend smoothly in and out and sit on top of the
## framing below, so `distance`, `offset` and `field_of_view` stay the resting view.
##
## Orbit comes from the mouse (while it is captured), the right stick (`look_*` actions) and
## touch (`TouchControls.look_turned`, connected in the scene to `orbit()`). The character turns
## to its move direction on its own (`Player`), so the camera never drags it.
##
## It is a `@tool` script, so the framing, follow and wall settings move the Phantom Camera in the
## editor too (open `main.tscn` and change `distance` or `field_of_view`). Only that setup runs
## there, never the orbit or the input.

## The orbit angles changed; `yaw` and `pitch` are in degrees.
signal orbited(yaw: float, pitch: float)

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

## The character whose sprint and aim the camera follows. Empty looks at the parent of `target`.
@export var player: Player

@export_group("Framing")
## How far behind the target the lens sits.
@export_range(1.0, 12.0, 0.05, "suffix:m") var distance := 4.4:
	set(value):
		distance = value
		_forward()
## Where the camera aims, from the target's point: x is the shoulder (positive moves the view to
## the right of the character), y the height, z the depth.
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

@export_subgroup("Shake")
## How far the sprint rocks the view up and down, in degrees (the sideways turn and roll are
## smaller shares of it). Zero is off; 0.3 is subtle.
@export_range(0.0, 2.0, 0.01, "suffix:deg") var sprint_shake_amplitude := 0.0
## Steps a second of the shake: one bob for each foot that lands (the sprint clip lands three).
@export_range(0.5, 8.0, 0.05, "suffix:Hz") var sprint_shake_frequency := 3.0
## How fast the shake builds up and dies down (1 is a second).
@export_range(0.5, 20.0, 0.1, "suffix:/s") var sprint_shake_blend := 4.0

@export_group("Aim")
## How far behind the target the lens sits while aiming.
@export_range(0.5, 8.0, 0.05, "suffix:m") var aim_distance := 2.4:
	set(value):
		aim_distance = value
		_forward_blend()
## How far the view moves to the right of the character while aiming, so the crosshair clears the
## body.
@export_range(-2.0, 2.0, 0.01, "suffix:m") var aim_shoulder := 0.55:
	set(value):
		aim_shoulder = value
		_forward_blend()
## The field of view while aiming.
@export_range(20.0, 110.0, 0.5, "suffix:deg") var aim_fov := 50.0:
	set(value):
		aim_fov = value
		_forward_blend()
## How fast the view comes in to the aim view (1 is a second, 8 an eighth of one).
@export_range(0.5, 30.0, 0.1, "suffix:/s") var aim_in_speed := 8.0
## How fast the view goes back out.
@export_range(0.5, 30.0, 0.1, "suffix:/s") var aim_out_speed := 6.0

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
## The physics layers that push the lens in (the spring arm's mask).
@export_flags_3d_physics var wall_mask := 1:
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

var _arm_waited := 0
var _sprint_blend := 0.0
var _aim_blend := 0.0
var _shake_blend := 0.0
var _shake_phase := 0.0

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
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_pcam.camera_3d_resource = Camera3DResource.new()
		_forward()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	pitch = start_pitch
	_player = player
	if target != null:
		var heading := target.get_parent() as Node3D
		if heading != null:
			yaw = rad_to_deg(heading.global_rotation.y)
		if heading is Player:
			(heading as Player).teleported.connect(_pcam.teleport_position)
			if _player == null:
				_player = heading as Player


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# The spring arm exists a frame or two after the Phantom Camera is ready.
	if _arm_waited < 3:
		_arm_waited += 1
		return
	var stick := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if not stick.is_zero_approx():
		orbit(stick * stick_speed * delta)
	advance(delta)


## Turns the camera by `degrees` (x about the up axis, y up and down). The mouse, the stick and
## the touch layer all come through here.
func orbit(degrees: Vector2) -> void:
	yaw = wrapf(yaw - degrees.x, -180.0, 180.0)
	var vertical := -degrees.y if invert_y else degrees.y
	pitch = clampf(pitch + vertical, min_pitch, max_pitch)
	orbited.emit(yaw, pitch)


## Moves the sprint and aim blends `delta` seconds toward where the player is (sprinting,
## aiming), puts the blended view on the Phantom Camera and turns it. `_process` calls it every
## frame; a test calls it with the time it wants.
func advance(delta: float) -> void:
	var sprinting := is_instance_valid(_player) and _player.is_sprinting()
	var aiming := is_instance_valid(_player) and _player.aiming
	_sprint_blend = move_toward(_sprint_blend, 1.0 if sprinting else 0.0, sprint_zoom_speed * delta)
	var aim_speed := aim_in_speed if aiming else aim_out_speed
	_aim_blend = move_toward(_aim_blend, 1.0 if aiming else 0.0, aim_speed * delta)
	_shake_blend = move_toward(_shake_blend, 1.0 if sprinting else 0.0, sprint_shake_blend * delta)
	if _shake_blend > 0.0:
		_shake_phase = fmod(_shake_phase + TAU * sprint_shake_frequency * delta, TAU * 2.0)
	_forward_blend()
	_apply()


## The distance behind the target now: `distance`, farther while sprinting, `aim_distance` while
## aiming.
func current_distance() -> float:
	var sprint := distance + sprint_distance_change * _eased(_sprint_blend)
	return lerpf(sprint, aim_distance, _eased(_aim_blend))


## The field of view now: `field_of_view`, wider while sprinting, `aim_fov` while aiming.
func current_fov() -> float:
	var sprint := field_of_view + sprint_fov_change * _eased(_sprint_blend)
	return lerpf(sprint, aim_fov, _eased(_aim_blend))


## The aim point offset now: `offset`, moved to the right by `aim_shoulder` while aiming.
func current_offset() -> Vector3:
	return offset + Vector3(aim_shoulder * _eased(_aim_blend), 0.0, 0.0)


## The sprint shake right now as turns in degrees (x pitch, y yaw, z roll). Zero when
## `sprint_shake_amplitude` is zero.
func current_shake() -> Vector3:
	var strength := sprint_shake_amplitude * _eased(_shake_blend)
	if strength <= 0.0:
		return Vector3.ZERO
	# One bob for each footfall, the sideways turn and the roll once for every two.
	return Vector3(
		sin(_shake_phase) * strength,
		sin(_shake_phase * 0.5) * strength * 0.5,
		cos(_shake_phase * 0.5) * strength * 0.67
	)


## How far into the sprint view the camera is, 0 to 1.
func sprint_blend() -> float:
	return _sprint_blend


## How far into the aim view the camera is, 0 to 1.
func aim_blend() -> float:
	return _aim_blend


## The Phantom Camera that does the work (for a game that wants its other settings).
func phantom_camera() -> PhantomCamera3D:
	return _pcam


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseMotion and _mouse_orbits():
		orbit((event as InputEventMouseMotion).relative * mouse_sensitivity)
	elif event is InputEventMouseButton and capture_mouse:
		var click := event as InputEventMouseButton
		if click.pressed and not DisplayServer.is_touchscreen_available():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if target == null:
		warnings.append("Set `target`: the node the camera follows (the player's `CameraTarget`).")
	if follow_camera == null:
		warnings.append("Set `follow_camera`: a PhantomCamera3D in Third Person follow mode.")
	return warnings


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


func _eased(blend: float) -> float:
	return smoothstep(0.0, 1.0, blend)


func _apply() -> void:
	if not is_instance_valid(_pcam):
		return
	var shake := current_shake()
	_pcam.set_third_person_rotation_degrees(Vector3(-pitch + shake.x, yaw + shake.y, shake.z))

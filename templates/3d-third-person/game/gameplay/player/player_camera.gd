@tool
class_name PlayerCamera
extends Node3D
## The third-person camera: a thin wrapper that sets the high-level tuning on a Phantom Camera
## (`FollowCamera`, a `PhantomCamera3D` in Third Person follow mode) and turns it to the
## player's orbit input. Phantom Camera does the work: it follows `target`, keeps the lens out
## of walls with its spring arm, damps the follow and blends to another camera when one has a
## higher `priority`.
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

var _pcam: PhantomCamera3D


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
	if target != null:
		var heading := target.get_parent() as Node3D
		if heading != null:
			yaw = rad_to_deg(heading.global_rotation.y)
		if heading is Player:
			(heading as Player).teleported.connect(_pcam.teleport_position)


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
	_apply()


## Turns the camera by `degrees` (x about the up axis, y up and down). The mouse, the stick and
## the touch layer all come through here.
func orbit(degrees: Vector2) -> void:
	yaw = wrapf(yaw - degrees.x, -180.0, 180.0)
	var vertical := -degrees.y if invert_y else degrees.y
	pitch = clampf(pitch + vertical, min_pitch, max_pitch)
	orbited.emit(yaw, pitch)


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
	pcam.spring_length = distance
	pcam.collision_mask = wall_mask
	pcam.margin = wall_margin
	pcam.follow_offset = offset
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
		if not is_equal_approx(lens.fov, field_of_view):
			lens.fov = field_of_view
		lens.near = near_clip
		lens.far = far_clip


func _apply() -> void:
	_pcam.set_third_person_rotation_degrees(Vector3(-pitch, yaw, 0.0))

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

## The orbit angles changed; `yaw` and `pitch` are in degrees.
signal orbited(yaw: float, pitch: float)

@export_group("Framing")
## What the camera follows and looks at: the player's `CameraTarget` (a point at head height).
@export var target: Node3D
## How far behind the target the lens sits.
@export_range(1.0, 12.0, 0.05, "suffix:m") var distance := 4.4:
	set(value):
		distance = value
		_forward()
## How far above the target's point the camera aims.
@export_range(-1.0, 2.0, 0.01, "suffix:m") var height := 0.1:
	set(value):
		height = value
		_forward()
## The lens's field of view.
@export_range(30.0, 110.0, 0.5, "suffix:deg") var field_of_view := 62.0:
	set(value):
		field_of_view = value
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

@export_group("Walls")
## The physics layers that push the lens in (the spring arm's mask).
@export_flags_3d_physics var wall_mask := 1:
	set(value):
		wall_mask = value
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
	# The Phantom Camera moves itself under its spring arm once it is ready, so it is found
	# here, while it is still the rig's child, and kept.
	var pcam := get_node_or_null("FollowCamera") as PhantomCamera3D
	if pcam == null:
		return
	_pcam = pcam
	pcam.follow_mode = PhantomCamera3D.FollowMode.THIRD_PERSON
	pcam.follow_target = target
	pcam.camera_3d_resource = Camera3DResource.new()
	_forward()


func _ready() -> void:
	pitch = start_pitch
	if target != null:
		var heading := target.get_parent() as Node3D
		if heading != null:
			yaw = rad_to_deg(heading.global_rotation.y)
		if heading is Player:
			(heading as Player).teleported.connect(_pcam.teleport_position)


func _process(delta: float) -> void:
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
	if event is InputEventMouseMotion and _mouse_orbits():
		orbit((event as InputEventMouseMotion).relative * mouse_sensitivity)
	elif event is InputEventMouseButton and capture_mouse:
		var click := event as InputEventMouseButton
		if click.pressed and not DisplayServer.is_touchscreen_available():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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
	pcam.follow_offset = Vector3(0.0, height, 0.0)
	pcam.follow_damping = follow_damping
	pcam.follow_damping_value = Vector3.ONE * follow_damping_amount
	var lens := pcam.camera_3d_resource
	if lens != null and not is_equal_approx(lens.fov, field_of_view):
		lens.fov = field_of_view


func _apply() -> void:
	_pcam.set_third_person_rotation_degrees(Vector3(-pitch, yaw, 0.0))

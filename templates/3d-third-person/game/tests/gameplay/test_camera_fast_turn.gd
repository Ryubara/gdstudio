# The lens never sits inside the level while the mouse turns the camera at full speed beside a
# wall, in a corner and on the run: every frame, the point the picture is drawn from (the Camera
# node moved by its H and V Offset, the over-the-shoulder view) stays farther from every wall than
# the corners of the near plane. The cause was the shoulder offset: the spring arm keeps the Camera
# node off a wall, but the offset then moved the view 0.5 m sideways with no cast at all, so a
# turn that swung the camera toward a wall put the view inside it.
extends GdUnitTestSuite

## The room is built high above the sample map, so nothing else is in the way.
const SPOT := Vector3(0.0, 100.0, 0.0)
## A wall's near face this far from the character's middle: a person brushing along it.
const WALL_GAP := 0.55
const WALL_THICKNESS := 0.5
## A flick: 30 degrees a frame at 60 frames a second (1800 degrees a second), and a fast steady
## turn of 12 a frame.
const FLICK := 30.0
const FAST := 12.0
const SETTLE_TICKS := 30
## How much more than the near plane's corner the view keeps from a wall (floating point and the
## character's own sway).
const SLACK := 0.005

var _scene: Node
var _rig: PlayerCamera
var _player: Player
var _camera: Camera3D
var _boxes: Array[AABB] = []
var _degrees_per_pixel := 0.0


func before_test() -> void:
	InputSim.release_all()
	_boxes.clear()
	_scene = scene_runner("res://main.tscn").scene()
	_rig = _scene.get_node("PlayerRig/PlayerCamera")
	_player = _scene.get_node("PlayerRig/Player")
	_camera = _scene.get_node("PlayerRig/Camera")
	_rig.require_captured_mouse = false
	await InputSim.ticks(get_tree(), 8)
	# A mouse motion reaches the camera scaled by the window's stretch (a headless window is
	# small): measure the turn one pixel makes here, so a step is in degrees.
	# The event reaches the camera on a later frame (Input buffers it).
	var start_yaw := _rig.yaw
	_mouse(10.0)
	await InputSim.ticks(get_tree(), 3)
	var turned := absf(angle_difference(deg_to_rad(start_yaw), deg_to_rad(_rig.yaw)))
	_degrees_per_pixel = rad_to_deg(turned) / 10.0


func after_test() -> void:
	Engine.physics_ticks_per_second = 60
	InputSim.release_all()
	AudioDrain.stop_all(_scene)


func _block(centre: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = centre
	_scene.add_child(body)
	_boxes.append(AABB(centre - size * 0.5, size))


func _floor() -> void:
	_block(SPOT + Vector3(0.0, -0.5, 0.0), Vector3(60.0, 1.0, 60.0))


# A long wall along z, its near face `WALL_GAP` from the spot on the side `side` (-1 west, 1 east).
func _side_wall(side: float) -> void:
	var x := side * (WALL_GAP + WALL_THICKNESS * 0.5)
	_block(SPOT + Vector3(x, 2.0, 0.0), Vector3(WALL_THICKNESS, 4.0, 40.0))


# A wall across x, its near face `WALL_GAP` north of the spot (the way the character faces).
func _front_wall() -> void:
	var z := -(WALL_GAP + WALL_THICKNESS * 0.5)
	_block(SPOT + Vector3(0.0, 2.0, z), Vector3(40.0, 4.0, WALL_THICKNESS))


# How far `point` is outside `box` (negative inside).
static func _box_distance(point: Vector3, box: AABB) -> float:
	var q := (point - box.get_center()).abs() - box.size * 0.5
	var outside := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()
	return outside + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)


func _clearance(point: Vector3) -> float:
	var best := INF
	for box in _boxes:
		best = minf(best, _box_distance(point, box))
	return best


# The farthest corner of the near plane from the eye: a wall nearer than this shows through.
func _near_radius() -> float:
	var half_height := _camera.near * tan(deg_to_rad(_camera.fov) * 0.5)
	var size := _camera.get_viewport().get_visible_rect().size
	var half_width := half_height * size.x / maxf(size.y, 1.0)
	return Vector3(half_width, half_height, _camera.near).length()


# Where the picture is drawn from now: the Camera node moved by its H and V Offset along its own
# axes (what `Camera3D.get_camera_transform()` returns once the frame's transforms are flushed).
func _eye() -> Vector3:
	var basis := _camera.global_basis.orthonormalized()
	return _camera.global_position + basis.x * _camera.h_offset + basis.y * _camera.v_offset


func _mouse(pixels: float) -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(pixels, 0.0)
	Input.parse_input_event(motion)


# Turns the camera `degrees` a frame for `frames` frames by mouse motion and returns the frame
# where the view came nearest a wall: its margin (clearance minus the near plane's corner), the
# frame and the yaw.
func _turn(degrees: float, frames: int) -> Dictionary:
	var worst := {"margin": INF, "frame": -1, "yaw": 0.0}
	assert_float(_degrees_per_pixel).is_greater(0.0)
	var pixels := degrees / maxf(_degrees_per_pixel, 0.0001)
	for frame in frames:
		_mouse(pixels)
		await get_tree().process_frame
		var margin := _clearance(_eye()) - _near_radius()
		if margin < worst["margin"]:
			worst = {"margin": margin, "frame": frame, "yaw": _rig.yaw}
	return worst


func _stand(yaw: float) -> void:
	_player.teleport(SPOT)
	_rig.yaw = yaw
	await InputSim.ticks(get_tree(), SETTLE_TICKS)


func _assert_clear(worst: Dictionary, what: String) -> void:
	(
		assert_float(worst["margin"])
		. override_failure_message(
			(
				"%s: the view came %.3f m inside the near plane's reach of a wall (frame %d, yaw %.0f)"
				% [what, -worst["margin"], worst["frame"], worst["yaw"]]
			)
		)
		. is_greater_equal(-SLACK)
	)


func test_the_mouse_turns_the_camera_by_the_degrees_asked() -> void:
	# The scale the other cases rely on: 12 degrees a frame for 15 frames is 180 degrees.
	_floor()
	await _stand(0.0)
	await _turn(FAST, 15)
	await InputSim.ticks(get_tree(), 2)
	assert_float(absf(_rig.yaw)).is_equal_approx(180.0, 1.0)


func test_a_flick_beside_a_wall_on_the_left_keeps_the_view_out_of_it() -> void:
	_floor()
	_side_wall(-1.0)
	for direction in [1.0, -1.0]:
		await _stand(0.0)
		_assert_clear(await _turn(FLICK * direction, 36), "flick %+.0f, wall west" % direction)
		await _stand(0.0)
		_assert_clear(await _turn(FAST * direction, 60), "turn %+.0f, wall west" % direction)


func test_a_flick_beside_a_wall_on_the_right_keeps_the_view_out_of_it() -> void:
	_floor()
	_side_wall(1.0)
	for direction in [1.0, -1.0]:
		await _stand(0.0)
		_assert_clear(await _turn(FLICK * direction, 36), "flick %+.0f, wall east" % direction)
		await _stand(0.0)
		_assert_clear(await _turn(FAST * direction, 60), "turn %+.0f, wall east" % direction)


func test_a_turn_in_a_corner_keeps_the_view_out_of_both_walls() -> void:
	_floor()
	_side_wall(1.0)
	_front_wall()
	for direction in [1.0, -1.0]:
		await _stand(180.0)
		_assert_clear(await _turn(FAST * direction, 60), "corner %+.0f" % direction)
		await _stand(180.0)
		_assert_clear(await _turn(FLICK * direction, 36), "corner flick %+.0f" % direction)


func test_aiming_while_turning_beside_a_wall_keeps_the_view_out_of_it() -> void:
	_floor()
	_side_wall(1.0)
	await _stand(0.0)
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await InputSim.ticks(get_tree(), 20)
	_assert_clear(await _turn(FAST, 60), "aiming, wall east")


func test_running_along_a_wall_while_turning_keeps_the_view_out_of_it() -> void:
	_floor()
	_side_wall(-1.0)
	await _stand(0.0)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 20)
	_assert_clear(await _turn(FAST, 45), "running, wall west")
	_assert_clear(await _turn(-FLICK, 24), "running flick, wall west")


func test_frames_between_physics_ticks_keep_the_view_out_of_the_wall() -> void:
	# At 30 ticks a second every other frame is drawn between ticks: the Camera node moves only in
	# the host's physics step, and the view offset written each frame must stay inside what the
	# last tick found room for.
	Engine.physics_ticks_per_second = 30
	_floor()
	_side_wall(1.0)
	for direction in [1.0, -1.0]:
		await _stand(0.0)
		_assert_clear(await _turn(FAST * direction, 60), "30 ticks, turn %+.0f" % direction)
	Engine.physics_ticks_per_second = 60

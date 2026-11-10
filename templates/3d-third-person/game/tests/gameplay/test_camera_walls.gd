# The wall correction against the character's own actions: with aim, fire or sprint zoom on, the
# lens never drops next to the head (a "first person" view with the pistol filling the screen)
# at any camera yaw, in a room of four walls and in the open. The cause was the arm's cast
# hitting the character's own capsule from an origin the aim shoulder had moved outside it.
extends GdUnitTestSuite

## The room is built high above the sample map, so nothing else is in the way.
const SPOT := Vector3(0.0, 100.0, 0.0)
## Walls this far from the character: the arm is cut by them only to about 1.7 m at the worst yaw
## (sprint), so a lens below `MIN_DISTANCE` is the fault and not a wall.
const WALL := 2.2
const MIN_DISTANCE := 1.0
const SETTLE_TICKS := 14
const LOOK_TICKS := 24

var _scene: Node
var _rig: PlayerCamera
var _player: Player
var _camera: Camera3D
var _head: Node3D


func before_test() -> void:
	InputSim.release_all()
	_scene = scene_runner("res://main.tscn").scene()
	_rig = _scene.get_node("PlayerRig/PlayerCamera")
	_player = _scene.get_node("PlayerRig/Player")
	_camera = _scene.get_node("PlayerRig/Camera")
	_head = _player.get_node("CameraTarget")
	await InputSim.ticks(get_tree(), 8)


func after_test() -> void:
	InputSim.release_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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


func _build_room(walled: bool) -> void:
	_block(SPOT + Vector3(0.0, -0.5, 0.0), Vector3(60.0, 1.0, 60.0))
	if not walled:
		return
	_block(SPOT + Vector3(WALL, 2.0, 0.0), Vector3(0.5, 4.0, 8.0))
	_block(SPOT + Vector3(-WALL, 2.0, 0.0), Vector3(0.5, 4.0, 8.0))
	_block(SPOT + Vector3(0.0, 2.0, WALL), Vector3(8.0, 4.0, 0.5))
	_block(SPOT + Vector3(0.0, 2.0, -WALL), Vector3(8.0, 4.0, 0.5))


func _press(mode: String) -> void:
	match mode:
		"aim":
			InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
		"fire":
			InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
		"sprint":
			InputSim.key(KEY_W, true)
			InputSim.key(KEY_SHIFT, true)


# The closest the lens gets to the arm's start (the head plus `offset`) over a whole turn of the
# camera in `mode`, with the yaw (in degrees) it happened at. Every frame after the yaw is set
# counts, the zoom-in too.
func _sweep(mode: String, step := 30) -> Dictionary:
	var worst := {"distance": 99.0, "yaw": 0.0}
	for yaw in range(-180, 180, step):
		InputSim.release_all()
		_player.teleport(SPOT)
		await InputSim.ticks(get_tree(), SETTLE_TICKS)
		_rig.yaw = float(yaw)
		_press(mode)
		for _tick in LOOK_TICKS:
			await get_tree().physics_frame
			var start := _head.global_position + _rig.offset
			var distance := _camera.global_position.distance_to(start)
			if distance < worst["distance"]:
				worst = {"distance": distance, "yaw": float(yaw)}
	return worst


func _assert_clear(worst: Dictionary) -> void:
	(
		assert_float(worst["distance"])
		. override_failure_message(
			"the lens came to %.2f m of the head at yaw %d" % [worst["distance"], worst["yaw"]]
		)
		. is_greater(MIN_DISTANCE)
	)


func test_aiming_by_walls_never_puts_the_lens_in_the_head_at_any_yaw() -> void:
	_build_room(true)
	_assert_clear(await _sweep("aim"))


func test_firing_by_walls_never_puts_the_lens_in_the_head_at_any_yaw() -> void:
	_build_room(true)
	_assert_clear(await _sweep("fire"))


func test_sprinting_by_walls_never_puts_the_lens_in_the_head_at_any_yaw() -> void:
	_build_room(true)
	_assert_clear(await _sweep("sprint"))


func test_aiming_and_firing_in_the_open_never_put_the_lens_in_the_head() -> void:
	_build_room(false)
	_assert_clear(await _sweep("aim", 45))
	_assert_clear(await _sweep("fire", 45))


func test_a_sideways_arm_offset_does_not_make_the_arm_hit_the_character() -> void:
	# An arm that starts 0.6 m east of the head is outside the capsule: its cast must not stop at
	# the character it follows, whatever way the camera looks (the distance is from the arm's
	# start, which is where the arm measures its length from).
	_build_room(false)
	_rig.offset = Vector3(0.6, 0.1, 0.0)
	_assert_clear(await _sweep("aim", 45))
	_assert_clear(await _sweep("fire", 45))


func test_a_wall_close_behind_still_pulls_the_lens_in() -> void:
	_build_room(false)
	_block(SPOT + Vector3(0.0, 2.0, 1.2), Vector3(8.0, 4.0, 0.5))
	_player.teleport(SPOT)
	_rig.yaw = 0.0
	_rig.pitch = 0.0
	await InputSim.ticks(get_tree(), 40)
	var distance := _camera.global_position.distance_to(_head.global_position)
	assert_float(distance).is_less(_rig.distance - 0.3)
	assert_float(_camera.global_position.z).is_less(SPOT.z + 0.95)

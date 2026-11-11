# The aim pose follows where the character's command looks (`Player.view_pitch`), not a camera:
# a character with no camera in its world raises and lowers its arm with its command, a camera
# that looks elsewhere changes nothing, and between two physics ticks the pose is blended, so on
# a fast display it moves as smoothly as it did while it read the camera on every drawn frame.
extends GdUnitTestSuite

var _arena: PlayArena
var _player: Player
var _animation: CharacterAnimation
var _players: Array[Player] = []


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	CommandDriver.take(_player)
	_players = [_player]
	_animation = _player.get_node("Animation") as CharacterAnimation
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	AudioDrain.stop_all(_arena)


func _look(pitch_degrees: float, count: int) -> void:
	var command := PlayerCommand.new()
	command.pitch = deg_to_rad(pitch_degrees)
	command.aim = true
	await CommandDriver.run(get_tree(), _players, command, count)
	# The tree is driven from `_process`, a drawn frame after the tick.
	await get_tree().process_frame
	await get_tree().process_frame


func test_with_no_camera_the_aim_pose_follows_the_commands_pitch() -> void:
	assert_object(get_viewport().get_camera_3d()).is_null()
	await _look(30.0, 8)
	assert_float(_animation.aim_pitch()).is_equal_approx(30.0, 0.01)
	await _look(-20.0, 8)
	assert_float(_animation.aim_pitch()).is_equal_approx(-20.0, 0.01)
	await _look(80.0, 8)
	assert_float(_animation.aim_pitch()).is_equal_approx(_animation.aim_pitch_range, 0.01)


func test_a_camera_that_looks_elsewhere_does_not_move_the_aim_pose() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 6.0, 3.0)
	_arena.add_child(camera)
	camera.make_current()
	camera.look_at(Vector3.ZERO)
	await _look(15.0, 8)
	assert_float(_animation.aim_pitch()).is_equal_approx(15.0, 0.01)


func test_between_two_ticks_the_pose_is_blended_so_a_fast_display_sees_no_steps() -> void:
	# The view turns up at 90 degrees a second. The body is stepped 60 times a second and the
	# picture is drawn 144 times: read from the camera, the pose moved 90 / 144 degrees a
	# frame. Read from the step alone it would stand still for a frame or two and then jump
	# 90 / 60. Blended between the last two steps it moves 90 / 144 again, a tick behind.
	_animation.set_physics_process(false)
	_animation.set_process(false)
	var speed := 90.0
	var largest := 0.0
	var largest_unblended := 0.0
	var last := 0.0
	var last_unblended := 0.0
	var ticks := 0
	for frame in range(1, 145):
		var time := frame / 144.0
		while ticks < floori(time * 60.0 + 0.000001):
			ticks += 1
			_player.view_pitch = deg_to_rad(speed * ticks / 60.0)
			_animation._physics_process(1.0 / 60.0)
		var fraction := time * 60.0 - ticks
		var shown := _animation._look_up_at(fraction)
		var unblended := _animation._look_up_at(1.0)
		if frame > 4:
			largest = maxf(largest, absf(shown - last))
			largest_unblended = maxf(largest_unblended, absf(unblended - last_unblended))
		last = shown
		last_unblended = unblended
	print("aim pose at 144 fps: %.3f deg a frame blended, %.3f not" % [largest, largest_unblended])
	assert_float(largest).is_less_equal(speed / 144.0 + 0.001)
	assert_float(largest_unblended).is_equal_approx(speed / 60.0, 0.001)
	# It ends a tick behind the view, as the body's own picture does.
	assert_float(last).is_between(speed - speed / 60.0 - 0.01, speed)

# `PlayerInput`, the one part of the character that reads the input actions and the camera: what
# each key, button and view becomes in the `PlayerCommand` it hands the body once a physics tick.
extends GdUnitTestSuite

var _arena: PlayArena
var _player: Player
var _input: PlayerInput
var _camera: Camera3D


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_player.tuning = (load("res://gameplay/player/player_tuning.tres") as PlayerTuning).duplicate()
	_input = _player.controller as PlayerInput
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(_camera)
	_camera.make_current()
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


# The command the body stepped on the last tick.
func _stepped() -> PlayerCommand:
	return _player.last_command


func test_the_player_scene_has_its_input_as_its_controller() -> void:
	assert_object(_input).is_not_null()
	assert_object(_input.player).is_same(_player)
	assert_object(_player.get_node("PlayerInput")).is_same(_input)


func test_nothing_held_is_a_command_that_asks_for_nothing() -> void:
	await InputSim.ticks(get_tree(), 3)
	var command := _stepped()
	assert_vector(command.move).is_equal(Vector2.ZERO)
	for field: StringName in [
		&"sprint",
		&"walk",
		&"crouch",
		&"aim",
		&"fire",
		&"jump",
		&"jump_pressed",
		&"fire_pressed",
		&"interact_pressed",
		&"ragdoll_pressed",
		&"has_shot"
	]:
		assert_bool(command.get(field)).override_failure_message(field).is_false()


func test_the_stick_is_in_the_views_axes_with_forward_up() -> void:
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 3)
	assert_vector(_stepped().move).is_equal(Vector2(0.0, 1.0))
	InputSim.key(KEY_W, false)
	InputSim.key(KEY_D, true)
	await InputSim.ticks(get_tree(), 3)
	assert_vector(_stepped().move).is_equal(Vector2(1.0, 0.0))
	InputSim.key(KEY_D, false)
	InputSim.pad_axis(JOY_AXIS_LEFT_Y, 0.6)
	await InputSim.ticks(get_tree(), 3)
	assert_float(_stepped().move.y).is_between(-0.7, -0.3)
	assert_float(_stepped().move.x).is_equal(0.0)


func test_each_held_button_is_its_bit() -> void:
	var held := {
		&"sprint": KEY_SHIFT,
		&"walk": KEY_X,
		&"crouch": KEY_C,
		&"jump": KEY_SPACE,
	}
	for field: StringName in held:
		InputSim.key(held[field], true)
		await InputSim.ticks(get_tree(), 4)
		assert_bool(_stepped().get(field)).override_failure_message(field).is_true()
		InputSim.key(held[field], false)
		await InputSim.ticks(get_tree(), 3)
		assert_bool(_stepped().get(field)).override_failure_message(field).is_false()
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 4)
	assert_bool(_stepped().aim).is_true()
	assert_bool(_stepped().fire).is_true()


func test_a_press_is_in_exactly_one_command_however_long_it_is_held() -> void:
	var presses := {&"jump_pressed": 0, &"interact_pressed": 0, &"ragdoll_pressed": 0}
	InputSim.key(KEY_SPACE, true)
	InputSim.key(KEY_E, true)
	InputSim.key(KEY_Y, true)
	for tick in 20:
		await get_tree().physics_frame
		for field: StringName in presses:
			if _stepped().get(field):
				presses[field] += 1
	for field: StringName in presses:
		assert_int(presses[field]).override_failure_message(field).is_equal(1)


func test_two_physics_ticks_in_one_frame_still_see_one_press() -> void:
	var before := Engine.physics_ticks_per_second
	# The suites run a frame per 1/60 s: twice the tick rate is two ticks in every frame.
	Engine.physics_ticks_per_second = before * 2
	var jumps: Array[int] = [0]
	var steps: Array[int] = [0]
	_player.jumped.connect(func() -> void: jumps[0] += 1)
	for tick in 8:
		await get_tree().physics_frame
	InputSim.key(KEY_E, true)
	var presses := 0
	var frames := Engine.get_process_frames()
	for tick in 12:
		await get_tree().physics_frame
		steps[0] += 1
		if _stepped().interact_pressed:
			presses += 1
	frames = Engine.get_process_frames() - frames
	Engine.physics_ticks_per_second = before
	InputSim.key(KEY_E, false)
	await InputSim.ticks(get_tree(), 4)
	assert_int(presses).is_equal(1)
	# The run did put more than one tick in a frame, or it proved nothing.
	assert_int(frames).is_less(steps[0])


func test_toggle_mode_turns_the_crouch_press_into_a_held_bit() -> void:
	_player.tuning.crouch_toggle = true
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 3)
	InputSim.key(KEY_C, false)
	await InputSim.ticks(get_tree(), 10)
	assert_bool(_stepped().crouch).is_true()
	assert_bool(_player.crouching).is_true()
	# Dying lets go of it: the character does not get up crouched.
	_player.die()
	_player.revive()
	await InputSim.ticks(get_tree(), 20)
	assert_bool(_stepped().crouch).is_false()
	assert_bool(_player.crouching).is_false()


func test_input_off_asks_for_nothing_and_keeps_the_view_and_a_toggled_crouch() -> void:
	_player.tuning.crouch_toggle = true
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 3)
	InputSim.key(KEY_C, false)
	_camera.rotation.y = deg_to_rad(40.0)
	_player.input_enabled = false
	InputSim.key(KEY_W, true)
	InputSim.key(KEY_SHIFT, true)
	InputSim.key(KEY_E, true)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 6)
	var command := _stepped()
	assert_vector(command.move).is_equal(Vector2.ZERO)
	assert_bool(command.sprint or command.fire or command.fire_pressed).is_false()
	assert_bool(command.interact_pressed or command.has_shot).is_false()
	assert_bool(command.crouch).is_true()
	assert_float(command.yaw).is_equal_approx(deg_to_rad(40.0), 0.0001)
	assert_float(_player.ground_speed()).is_less(0.05)


func test_the_view_is_the_cameras_heading_and_pitch() -> void:
	for step in 12:
		var heading := -PI + step * TAU / 12.0 + 0.1
		var look := deg_to_rad(-50.0 + step * 9.0)
		_camera.rotation = Vector3(look, heading, 0.0)
		await InputSim.ticks(get_tree(), 2)
		var forward := -_camera.global_basis.z
		assert_float(angle_difference(_stepped().yaw, heading)).is_equal_approx(0.0, 0.0001)
		assert_float(_stepped().pitch).is_equal_approx(asin(forward.y), 0.0001)
		assert_float(_player.view_yaw).is_equal(_stepped().yaw)
		assert_float(_player.view_pitch).is_equal(_stepped().pitch)
		# The view's forward, as the body turns it, is the camera's flat forward.
		var flat := Vector3(forward.x, 0.0, forward.z).normalized()
		var command := PlayerCommand.new()
		command.yaw = _stepped().yaw
		command.move = Vector2(0.0, 1.0)
		assert_vector(command.world_move()).is_equal_approx(flat, Vector3.ONE * 0.0001)


func test_the_shot_block_is_the_crosshairs_ray_with_a_shoulder_view() -> void:
	# An over-the-shoulder lens: the ray through the middle of the screen is beside the camera.
	_camera.h_offset = 0.5
	_camera.v_offset = 0.2
	_camera.rotation = Vector3(deg_to_rad(-8.0), deg_to_rad(25.0), 0.0)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	var seen := false
	for tick in 6:
		await get_tree().physics_frame
		if not _stepped().has_shot:
			continue
		seen = true
		var centre := get_viewport().get_visible_rect().size / 2.0
		var start := _camera.project_ray_origin(centre)
		var along := _camera.project_ray_normal(centre)
		assert_vector(_stepped().origin).is_equal_approx(start, Vector3.ONE * 0.0001)
		var ray := CommandCodec.direction_from_angles(_stepped().shot_yaw, _stepped().shot_pitch)
		assert_vector(ray).is_equal_approx(along, Vector3.ONE * 0.0001)
		assert_float(start.distance_to(_camera.global_position)).is_greater(0.4)
		# It is the ray the weapon aims by: its aim point lies on it.
		var aim_at := _player.weapon.aim_point()
		var off := (aim_at - start).cross(along).length()
		assert_float(off).is_less(0.01)
	assert_bool(seen).is_true()


func test_the_shot_block_rides_only_while_a_shot_can_leave() -> void:
	var blocks := 0
	var shots: Array[int] = [0]
	_player.weapon.fired.connect(func(_shot: Projectile) -> void: shots[0] += 1)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	for tick in 120:
		await get_tree().physics_frame
		if _stepped().has_shot:
			blocks += 1
	# Two seconds of holding the fire button of a pistol: one shot, and the block only on the
	# ticks before it left (the arm coming up), not for the two seconds.
	assert_int(shots[0]).is_equal(1)
	assert_int(blocks).is_between(1, 12)


func test_with_no_camera_the_view_is_the_bodys_facing_and_the_stick_is_the_worlds() -> void:
	_camera.queue_free()
	await InputSim.ticks(get_tree(), 3)
	_player.teleport(Vector3.ZERO, deg_to_rad(90.0))
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 2)
	# Forward on the stick is -Z in the world, whichever way the body faces.
	assert_vector(_stepped().world_move()).is_equal_approx(Vector3.FORWARD, Vector3.ONE * 0.0001)
	await InputSim.ticks(get_tree(), 60)
	InputSim.key(KEY_W, false)
	assert_float(_player.global_position.z).is_less(-2.0)
	assert_float(absf(_player.global_position.x)).is_less(0.1)
	# Aiming with no camera holds the way the body faces (there is no view to turn to).
	var facing := _player.facing
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	InputSim.key(KEY_D, true)
	await InputSim.ticks(get_tree(), 40)
	assert_bool(_player.aiming).is_true()
	assert_float(angle_difference(_player.facing, facing)).is_equal_approx(0.0, 0.001)
	assert_float(_player.global_position.x).is_greater(0.3)


func test_the_rigs_shake_is_not_in_the_command() -> void:
	var rig: PlayerCamera = auto_free(PlayerCamera.new())
	rig.camera = _camera
	var shaker := CameraShake.new()
	rig.shaker = shaker
	rig.add_child(shaker)
	_input.camera_rig = rig
	await InputSim.ticks(get_tree(), 2)
	var still := _stepped().clone()
	# A shake of the lens, as the rig applies it: the camera turns by it.
	var preset := ShakePreset.new()
	preset.max_rotation = Vector3(4.0, 6.0, 0.0)
	preset.trauma = 1.0
	preset.duration = 5.0
	shaker.auto_advance = false
	shaker.add(preset)
	var largest := 0.0
	for tick in 30:
		shaker.advance(1.0 / 60.0)
		var shake := rig.current_shake()
		largest = maxf(largest, absf(shake.y))
		_camera.rotation = Vector3(deg_to_rad(shake.x), deg_to_rad(shake.y), 0.0)
		await get_tree().physics_frame
		await get_tree().physics_frame
		assert_float(angle_difference(_stepped().yaw, still.yaw)).is_equal_approx(0.0, 0.002)
		assert_float(_stepped().pitch).is_equal_approx(still.pitch, 0.002)
	assert_float(largest).is_greater(1.0)

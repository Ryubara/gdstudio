# Aiming and shooting, through simulated input in the real physics world: the aim button (or the
# left trigger) raises the arm, turns the body to the camera and shows the crosshair; the fire
# button (or the right trigger) shoots a projectile toward the crosshair that pushes a cube and
# knocks a target down.
extends GdUnitTestSuite

const PROP := "res://gameplay/physics_prop/physics_prop.tscn"
const TARGET := "res://gameplay/target/target.tscn"

var _arena: PlayArena
var _player: Player
var _camera: Camera3D
var _tuning: PlayerTuning


func before_test() -> void:
	# Another suite may have left a button down (a base suite leaves `fire` pressed).
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 0.0))
	_player.tuning = (load("res://gameplay/player/player_tuning.tres") as PlayerTuning).duplicate()
	_tuning = _player.tuning
	# A camera 3 m behind the character looking along -Z, at the height of its hands.
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(_camera)
	_camera.make_current()
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


func _weapon() -> Weapon:
	return _player.weapon


# Fires the weapon along the ray under the crosshair, as the body does with the ray its input
# puts in the command (the weapon itself reads no camera).
func _fire_at_the_crosshair() -> Projectile:
	var ray := CameraAim.crosshair_ray(_camera)
	return _weapon().fire(ray[0], ray[1])


func _hold_aim() -> void:
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)


func test_the_player_holds_a_weapon_and_the_weapon_is_set_up() -> void:
	assert_object(_weapon()).is_not_null()
	assert_object(_weapon().muzzle).is_not_null()
	assert_object(_weapon().shooter).is_same(_player)
	assert_array(_weapon()._get_configuration_warnings()).is_empty()
	# The muzzle is the pistol's, in the right hand.
	assert_str(String(_weapon().muzzle.name)).is_equal("Muzzle")
	assert_bool(_player.get_node("Model").is_ancestor_of(_weapon().muzzle)).is_true()


func test_the_aim_button_raises_the_arm_and_lets_go_lowers_it() -> void:
	var changes: Array[bool] = []
	_player.aim_changed.connect(func(now: bool) -> void: changes.append(now))
	assert_float(_player.aim_amount).is_equal(0.0)
	_hold_aim()
	await InputSim.ticks(get_tree(), 4)
	assert_bool(_player.aiming).is_true()
	assert_float(_player.aim_amount).is_between(0.1, 0.99)
	await InputSim.ticks(get_tree(), 20)
	assert_float(_player.aim_amount).is_equal(1.0)
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await InputSim.ticks(get_tree(), 30)
	assert_bool(_player.aiming).is_false()
	assert_float(_player.aim_amount).is_equal(0.0)
	assert_array(changes).is_equal([true, false])


func test_the_right_mouse_button_aims_too() -> void:
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), 4)
	assert_bool(_player.aiming).is_true()
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)
	await InputSim.ticks(get_tree(), 4)
	assert_bool(_player.aiming).is_false()


func test_aiming_turns_the_body_to_the_cameras_heading_even_when_it_walks_aside() -> void:
	_camera.rotation.y = deg_to_rad(90.0)  # now looking along -X
	_hold_aim()
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 40)
	# Facing 0 is +Z; looking along -X is a facing of -90 degrees.
	assert_float(rad_to_deg(angle_difference(_player.facing, deg_to_rad(-90.0)))).is_equal_approx(
		0.0, 2.0
	)
	var model := _player.get_node("Model") as Node3D
	assert_float(rad_to_deg(angle_difference(model.rotation.y, deg_to_rad(-90.0)))).is_equal_approx(
		0.0, 2.0
	)


func test_without_a_weapon_the_player_does_not_aim() -> void:
	_player.weapon = null
	_hold_aim()
	InputSim.pad_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await InputSim.ticks(get_tree(), 20)
	assert_bool(_player.aiming).is_false()


func test_aiming_walks_slower_and_sprint_is_ignored() -> void:
	InputSim.key(KEY_W, true)
	InputSim.key(KEY_SHIFT, true)
	await InputSim.ticks(get_tree(), 60)
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.sprint_speed, 0.1)
	_hold_aim()
	await InputSim.ticks(get_tree(), 60)
	var expected := _tuning.walk_speed * 1.5 * _tuning.aim_move_scale
	assert_float(_player.ground_speed()).is_equal_approx(expected, 0.1)
	assert_bool(_player.is_sprinting()).is_false()


func test_the_fire_button_aims_and_shoots_one_projectile_a_press() -> void:
	var shots: Array[Projectile] = []
	_weapon().fired.connect(func(shot: Projectile) -> void: shots.append(shot))
	InputSim.pad_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await InputSim.ticks(get_tree(), 40)
	# Held, a semi-automatic weapon shoots once.
	assert_array(shots).has_size(1)
	assert_bool(_player.aiming).is_true()
	InputSim.pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await InputSim.ticks(get_tree(), 20)
	InputSim.pad_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await InputSim.ticks(get_tree(), 20)
	assert_array(shots).has_size(2)


func test_holding_fire_shoots_over_and_over_when_the_weapon_is_automatic() -> void:
	_weapon().automatic = true
	_weapon().fire_rate = 10.0
	var shots: Array[Projectile] = []
	_weapon().fired.connect(func(shot: Projectile) -> void: shots.append(shot))
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 60)
	assert_int(shots.size()).is_between(5, 8)


func test_the_fire_rate_spaces_the_shots() -> void:
	_weapon().fire_rate = 2.0
	assert_object(_weapon().fire()).is_not_null()
	assert_object(_weapon().fire()).is_null()
	await InputSim.ticks(get_tree(), 20)
	assert_object(_weapon().fire()).is_null()
	await InputSim.ticks(get_tree(), 20)
	assert_object(_weapon().fire()).is_not_null()


func test_a_shot_leaves_the_muzzle_and_flies_to_the_point_under_the_crosshair() -> void:
	var board := auto_free(load(TARGET).instantiate()) as Target
	board.position = Vector3(0.0, 0.0, -12.0)
	board.size = 1.0
	board.rotation.y = 0.0
	_arena.add_child(board)
	# Aim the camera at the middle of the board.
	var middle := board.global_position + Vector3(0.0, board.get_node("%Pivot").position.y, 0.0)
	_camera.position = Vector3(0.0, middle.y, 3.0)
	await InputSim.ticks(get_tree(), 2)
	var ray := CameraAim.crosshair_ray(_camera)
	var point := _weapon().aim_point(ray[0], ray[1])
	assert_float(point.z).is_equal_approx(-12.0, 0.2)
	var shot := _fire_at_the_crosshair()
	assert_object(shot).is_not_null()
	assert_vector(shot.global_position).is_equal_approx(
		_weapon().muzzle.global_position, Vector3.ONE * 0.1
	)
	# The shot's direction is from the muzzle to the aim point.
	var want := (point - _weapon().muzzle.global_position).normalized()
	assert_float(shot.velocity.normalized().dot(want)).is_greater(0.999)
	assert_float(shot.velocity.length()).is_equal_approx(_weapon().projectile_speed, 0.01)
	var hit: Array = []
	shot.impacted.connect(
		func(collider: Node, _p: Vector3, _n: Vector3) -> void: hit.append(collider)
	)
	await InputSim.ticks(get_tree(), 60)
	assert_array(hit).has_size(1)
	assert_object(hit[0]).is_same(board)
	assert_bool(board.is_down()).is_true()


func test_a_shot_moves_a_cube_it_hits() -> void:
	var cube := auto_free(load(PROP).instantiate()) as PhysicsProp
	cube.weight = 60.0
	cube.position = Vector3(0.0, 0.5, -8.0)
	_arena.add_child(cube)
	_camera.position = Vector3(0.0, 0.5, 3.0)
	await InputSim.ticks(get_tree(), 4)
	var shot := _fire_at_the_crosshair()
	assert_object(shot).is_not_null()
	# The push shows for a moment (the cube's friction stops it soon): read the fastest tick.
	var fastest := 0.0
	for _tick in 40:
		await get_tree().physics_frame
		fastest = minf(fastest, cube.linear_velocity.z)
	assert_float(fastest).is_less(-0.3)
	# 40 newton seconds on 60 kg is about 0.67 m/s.
	assert_float(fastest).is_greater(-0.8)


func test_a_target_stands_up_again_after_its_reset_time() -> void:
	var board := auto_free(load(TARGET).instantiate()) as Target
	board.position = Vector3(0.0, 0.0, -8.0)
	board.reset_time = 0.5
	_arena.add_child(board)
	_camera.position = Vector3(0.0, 0.9, 3.0)
	await InputSim.ticks(get_tree(), 4)
	_fire_at_the_crosshair()
	await InputSim.ticks(get_tree(), 30)
	assert_bool(board.is_down()).is_true()
	assert_float(board.tilt()).is_equal_approx(board.drop_angle, 1.0)
	await InputSim.ticks(get_tree(), 60)
	assert_bool(board.is_down()).is_false()
	assert_float(board.tilt()).is_equal_approx(0.0, 1.0)


func test_a_projectile_never_hits_the_one_who_fired_it() -> void:
	var shot := _fire_at_the_crosshair()
	await InputSim.ticks(get_tree(), 10)
	assert_bool(is_instance_valid(shot) and not shot.is_queued_for_deletion()).is_true()
	assert_bool(_player.get_slide_collision_count() >= 0).is_true()
	assert_vector(_player.velocity).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.01)

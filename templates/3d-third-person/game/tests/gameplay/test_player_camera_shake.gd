# The camera's shake on the real rig in the main scene: the sprint shake and the shot kick are
# held on the `CameraShake` under it (both off by default), anything in the game can shake the same
# view with one call, and the global strength turns it all off. The rig is stepped by hand.
extends GdUnitTestSuite

const STEP := 1.0 / 60.0
const BLAST := preBLAST

var _scene: Node
var _rig: PlayerCamera
var _player: Player


func before_test() -> void:
	InputSim.release_all()
	CameraShake.strength = 1.0
	_scene = scene_runner("res://main.tscn").scene()
	_rig = _scene.get_node("PlayerCamera")
	_player = _scene.get_node("Player")
	await InputSim.ticks(get_tree(), 8)


func after_test() -> void:
	InputSim.release_all()
	CameraShake.strength = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioDrain.stop_all(_scene)


func _step(seconds: float) -> float:
	# Steps the rig and returns the largest turn of the view seen, in degrees.
	var peak := 0.0
	for _i in roundi(seconds / STEP):
		_rig.advance(STEP)
		peak = maxf(peak, _rig.current_shake().length())
	return peak


func _shoot() -> void:
	_rig.shaker.clear()
	_player.weapon._cooldown = 0.0
	assert_object(_player.weapon.fire()).is_not_null()


func test_the_scene_has_the_shake_component_under_the_rig() -> void:
	assert_object(_rig.shaker).is_not_null()
	assert_object(_rig.shaker).is_same(_rig.get_node("CameraShake"))
	assert_bool(_rig.shaker.auto_advance).is_false()
	assert_bool(_rig.shaker.is_in_group(CameraShake.GROUP)).is_true()


func test_a_rig_without_a_shaker_makes_one() -> void:
	var rig: PlayerCamera = auto_free(PlayerCamera.new())
	add_child(rig)
	assert_object(rig.shaker).is_not_null()
	assert_bool(rig.shaker.auto_advance).is_false()


func test_nothing_shakes_a_resting_view_and_a_shot_kicks_nothing_by_default() -> void:
	assert_float(_rig.shot_kick_amplitude).is_equal(0.0)
	_shoot()
	assert_float(_step(0.5)).is_equal(0.0)
	assert_bool(_rig.shaker.is_shaking()).is_false()


func test_a_shot_kicks_the_view_and_it_dies_away_in_its_time() -> void:
	_rig.shot_kick_amplitude = 0.3
	_rig.shot_kick_duration = 0.2
	_shoot()
	var peak := _step(0.1)
	assert_float(peak).is_greater(0.01)
	# One shot's largest pitch is the amplitude; the sideways turn and roll are smaller shares.
	assert_float(peak).is_less_equal(0.3 * 1.2)
	_step(0.2)
	assert_bool(_rig.shaker.is_shaking()).is_false()
	assert_vector(_rig.current_shake()).is_equal(Vector3.ZERO)


func test_a_burst_of_shots_stacks_up_to_twice_one_kick() -> void:
	_rig.shot_kick_amplitude = 0.3
	_rig.shot_kick_duration = 0.5
	_shoot()
	for _shot in 6:
		_rig.kick()
	var peak := 0.0
	for _i in 30:
		_rig.advance(STEP)
		peak = maxf(peak, absf(_rig.current_shake().x))
	assert_float(peak).is_less_equal(0.3 * 2.0 + 0.0001)
	assert_float(peak).is_greater(0.3)


func test_the_kick_amplitude_is_live() -> void:
	_rig.shot_kick_amplitude = 0.1
	_shoot()
	var small := _step(0.1)
	_rig.shot_kick_amplitude = 0.8
	_shoot()
	var large := _step(0.1)
	assert_float(large).is_greater(small * 4.0)


func test_a_blast_anywhere_in_the_game_shakes_this_view_with_one_call() -> void:
	var blast := BLAST
	CameraShake.shake(blast)
	var peak := _step(0.3)
	assert_float(peak).is_greater(0.2)
	# The Phantom Camera is turned by it, on top of the orbit.
	_rig.shaker.clear()
	_rig.advance(STEP)
	var resting := _rig.phantom_camera().get_third_person_rotation_degrees()
	CameraShake.shake(blast)
	_step(0.1)
	var shaken := _rig.phantom_camera().get_third_person_rotation_degrees()
	assert_float(shaken.distance_to(resting)).is_greater(0.05)


func test_a_blast_far_away_is_not_felt_and_a_near_one_is() -> void:
	var blast := BLAST
	var lens := get_viewport().get_camera_3d()
	CameraShake.shake(blast, lens.global_position + Vector3(blast.radius * 2.0, 0.0, 0.0))
	assert_bool(_rig.shaker.is_shaking()).is_false()
	CameraShake.shake(blast, lens.global_position + Vector3(blast.radius * 0.1, 0.0, 0.0))
	assert_float(_rig.shaker.trauma_of(blast)).is_greater(0.5)


func test_the_global_strength_turns_the_sprint_shake_and_the_kick_off() -> void:
	_rig.sprint_shake_amplitude = 1.0
	_rig.shot_kick_amplitude = 1.0
	CameraShake.strength = 0.0
	_shoot()
	assert_float(_step(0.5)).is_equal(0.0)
	CameraShake.shake(BLAST)
	assert_float(_step(0.5)).is_equal(0.0)


func test_a_shake_leaves_the_framing_alone() -> void:
	_step(1.0)
	var distance := _rig.current_distance()
	var fov := _rig.current_fov()
	CameraShake.shake(BLAST)
	_step(0.2)
	assert_float(_rig.current_distance()).is_equal(distance)
	assert_float(_rig.current_fov()).is_equal(fov)


func test_a_slide_in_a_preset_moves_the_picture_on_top_of_the_shoulder() -> void:
	_step(1.0)
	var shoulder := _rig.current_view_offset()
	var preset := ShakePreset.new()
	preset.trauma = 1.0
	preset.max_rotation = Vector3.ZERO
	preset.max_offset = Vector2(0.1, 0.1)
	CameraShake.shake(preset)
	var moved := 0.0
	for _i in 20:
		_rig.advance(STEP)
		moved = maxf(moved, (_rig.current_view_offset() - shoulder).length())
	assert_float(moved).is_greater(0.005)
	assert_float(moved).is_less_equal(0.1 * sqrt(2.0) + 0.0001)
	_step(1.0)
	assert_vector(_rig.current_view_offset()).is_equal_approx(shoulder, Vector2.ONE * 0.0001)

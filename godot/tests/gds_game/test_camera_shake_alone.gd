# `CameraShake` and `ShakePreset` of `gds_game` on their own: a one-shot dies away in its time,
# one line reaches every shaker, distance and the global strength turn it down, and a held source
# stops when released. Stepped by hand; a game's suites shake its own camera rig (3D Blank's
# `test_camera_shake.gd`, 3D Third Person's `test_player_camera_shake.gd`).
extends GdUnitTestSuite

const STEP := 1.0 / 60.0

var _camera: Node3D
var _shaker: CameraShake


func before_test() -> void:
	CameraShake.strength = 1.0
	_camera = auto_free(Node3D.new())
	add_child(_camera)
	_shaker = _make_shaker()


func after_test() -> void:
	CameraShake.strength = 1.0


func _make_shaker() -> CameraShake:
	var shaker: CameraShake = auto_free(CameraShake.new())
	shaker.auto_advance = false
	shaker.reference = _camera
	add_child(shaker)
	return shaker


func _preset(trauma := 1.0, duration := 0.5, radius := 0.0) -> ShakePreset:
	var preset := ShakePreset.new()
	preset.trauma = trauma
	preset.duration = duration
	preset.radius = radius
	return preset


# Steps `shaker` for `seconds` and returns the largest turn seen, in degrees.
func _peak(shaker: CameraShake, seconds: float) -> float:
	var peak := 0.0
	for _step in roundi(seconds / STEP):
		shaker.advance(STEP)
		peak = maxf(peak, shaker.rotation_degrees().length())
	return peak


func test_a_one_shot_shakes_then_is_gone_in_its_duration() -> void:
	assert_bool(_shaker.is_shaking()).is_false()
	_shaker.add(_preset(1.0, 0.5))
	assert_float(_peak(_shaker, 0.25)).is_greater(0.0)
	_peak(_shaker, 0.3)
	assert_bool(_shaker.is_shaking()).is_false()
	assert_vector(_shaker.rotation_degrees()).is_equal(Vector3.ZERO)


func test_one_line_reaches_every_shaker_in_the_tree() -> void:
	var second := _make_shaker()
	var preset := _preset(0.5)
	CameraShake.shake(preset)
	assert_float(_shaker.trauma_of(preset)).is_equal_approx(0.5, 0.0001)
	assert_float(second.trauma_of(preset)).is_equal_approx(0.5, 0.0001)


func test_a_play_fades_with_distance_and_is_not_felt_past_the_radius() -> void:
	var preset := _preset(1.0, 0.5, 10.0)
	_shaker.add(preset, Vector3(5.0, 0.0, 0.0))
	assert_float(_shaker.trauma_of(preset)).is_equal_approx(0.5, 0.0001)
	_shaker.clear()
	_shaker.add(preset, Vector3(20.0, 0.0, 0.0))
	assert_bool(_shaker.is_shaking()).is_false()


func test_a_global_strength_of_zero_turns_every_shake_off() -> void:
	CameraShake.strength = 0.0
	_shaker.add(_preset())
	assert_bool(_shaker.is_shaking()).is_false()


func test_a_held_source_builds_to_its_level_and_dies_down_when_released() -> void:
	var preset := _preset()
	preset.blend_speed = 4.0
	_shaker.hold(&"engine", preset, 1.0)
	_peak(_shaker, 0.5)
	assert_float(_shaker.level_of(&"engine")).is_equal_approx(1.0, 0.0001)
	_shaker.release(&"engine")
	_peak(_shaker, 0.5)
	assert_bool(_shaker.is_shaking()).is_false()


func test_the_same_steps_give_the_same_shake() -> void:
	var other := _make_shaker()
	var preset := _preset()
	_shaker.add(preset)
	other.add(preset)
	for _step in 10:
		_shaker.advance(STEP)
		other.advance(STEP)
	assert_vector(_shaker.rotation_degrees()).is_equal(other.rotation_degrees())

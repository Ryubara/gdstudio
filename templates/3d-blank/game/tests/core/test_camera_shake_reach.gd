# The universal screen shake, who feels it: a play far from the camera falls off, a strength of
# zero turns every shake off, and one call reaches every camera. Stepped by hand, no real time.
extends GdUnitTestSuite

const STEP := 1.0 / 60.0

var _shaker: CameraShake
var _camera: Node3D


func before_test() -> void:
	CameraShake.strength = 1.0
	_camera = auto_free(Node3D.new())
	add_child(_camera)
	_shaker = auto_free(CameraShake.new())
	_shaker.auto_advance = false
	_shaker.reference = _camera
	add_child(_shaker)


func after_test() -> void:
	CameraShake.strength = 1.0


func _preset(trauma := 1.0, duration := 0.5) -> ShakePreset:
	var preset := ShakePreset.new()
	preset.trauma = trauma
	preset.duration = duration
	return preset


func _run(seconds: float) -> float:
	# Steps for the time and returns the largest turn seen, in degrees.
	var peak := 0.0
	for _step in roundi(seconds / STEP):
		_shaker.advance(STEP)
		peak = maxf(peak, _shaker.rotation_degrees().length())
	return peak


func test_a_play_far_from_the_camera_falls_off_with_the_radius() -> void:
	_camera.global_position = Vector3.ZERO
	var preset := _preset(1.0, 10.0)
	preset.radius = 20.0
	_shaker.add(preset, Vector3.ZERO)
	assert_float(_shaker.trauma_of(preset)).is_equal(1.0)
	_shaker.clear()
	_shaker.add(preset, Vector3(10.0, 0.0, 0.0))
	assert_float(_shaker.trauma_of(preset)).is_equal_approx(0.5, 0.001)
	_shaker.clear()
	_shaker.add(preset, Vector3(15.0, 0.0, 0.0))
	assert_float(_shaker.trauma_of(preset)).is_between(0.0, 0.2)
	_shaker.clear()
	_shaker.add(preset, Vector3(20.0, 0.0, 0.0))
	assert_bool(_shaker.is_shaking()).is_false()
	_shaker.add(preset, Vector3(500.0, 0.0, 0.0))
	assert_bool(_shaker.is_shaking()).is_false()


func test_a_play_without_a_position_or_a_radius_is_felt_in_full() -> void:
	_camera.global_position = Vector3(300.0, 0.0, 0.0)
	var preset := _preset(0.7, 1.0)
	preset.radius = 5.0
	_shaker.add(preset)
	assert_float(_shaker.trauma_of(preset)).is_equal_approx(0.7, 0.0001)
	var near := _preset(0.7, 1.0)
	_shaker.add(near, Vector3.ZERO)
	assert_float(_shaker.trauma_of(near)).is_equal_approx(0.7, 0.0001)


func test_a_held_source_falls_off_with_distance_too() -> void:
	var preset := _preset()
	preset.radius = 10.0
	preset.blend_speed = 20.0
	preset.wave = ShakePreset.Wave.SINE
	_shaker.hold(&"engine", preset, 1.0, Vector3(5.0, 0.0, 0.0))
	_run(1.0)
	assert_float(_shaker.level_of(&"engine")).is_equal_approx(0.5, 0.001)


func test_the_scale_of_a_play_scales_its_trauma() -> void:
	var preset := _preset(0.5, 1.0)
	_shaker.add(preset, null, 0.5)
	assert_float(_shaker.trauma_of(preset)).is_equal_approx(0.25, 0.0001)


func test_a_global_strength_of_zero_turns_every_shake_off() -> void:
	var one_shot := _preset()
	var held := _preset()
	held.wave = ShakePreset.Wave.SINE
	CameraShake.strength = 0.0
	CameraShake.shake(one_shot)
	_shaker.add(one_shot)
	_shaker.hold(&"engine", held, 1.0)
	_run(0.5)
	assert_bool(_shaker.is_shaking()).is_false()
	assert_vector(_shaker.rotation_degrees()).is_equal(Vector3.ZERO)


func test_a_strength_set_while_shaking_scales_the_shake_at_once() -> void:
	var preset := _preset(1.0, 10.0)
	_shaker.add(preset)
	_shaker.advance(STEP)
	var full := _shaker.rotation_degrees()
	CameraShake.strength = 0.5
	_shaker.advance(0.0)
	assert_vector(_shaker.rotation_degrees()).is_equal_approx(full * 0.5, Vector3.ONE * 0.0001)
	CameraShake.strength = 0.0
	_shaker.advance(0.0)
	assert_vector(_shaker.rotation_degrees()).is_equal(Vector3.ZERO)


func test_a_camera_can_turn_its_own_shake_down_or_off() -> void:
	var preset := _preset(1.0, 10.0)
	_shaker.add(preset)
	_shaker.advance(STEP)
	var full := _shaker.rotation_degrees()
	_shaker.camera_strength = 2.0
	_shaker.advance(0.0)
	assert_vector(_shaker.rotation_degrees()).is_equal_approx(full * 2.0, Vector3.ONE * 0.0001)
	_shaker.enabled = false
	assert_bool(_shaker.is_shaking()).is_false()
	_shaker.add(preset)
	assert_bool(_shaker.is_shaking()).is_false()


func test_one_line_from_anywhere_reaches_every_shaker_in_the_tree() -> void:
	var other: CameraShake = auto_free(CameraShake.new())
	add_child(other)
	var loose: CameraShake = auto_free(CameraShake.new())
	var preset := _preset(0.6, 1.0)
	CameraShake.shake(preset)
	assert_float(_shaker.trauma_of(preset)).is_equal_approx(0.6, 0.0001)
	assert_float(other.trauma_of(preset)).is_equal_approx(0.6, 0.0001)
	# A shaker that is not in the tree is not asked.
	assert_float(loose.trauma_of(preset)).is_equal(0.0)
	remove_child(other)
	other.clear()
	CameraShake.shake(preset)
	assert_float(other.trauma_of(preset)).is_equal(0.0)


func test_held_everywhere_reaches_every_shaker() -> void:
	var preset := _preset()
	preset.wave = ShakePreset.Wave.SINE
	preset.blend_speed = 20.0
	CameraShake.hold_everywhere(&"engine", preset, 1.0)
	_run(0.5)
	assert_float(_shaker.level_of(&"engine")).is_equal(1.0)
	CameraShake.hold_everywhere(&"engine", preset, 0.0)
	_run(0.5)
	assert_bool(_shaker.is_shaking()).is_false()


func test_a_slide_moves_the_picture_without_a_turn() -> void:
	var preset := _preset(1.0, 10.0)
	preset.max_rotation = Vector3.ZERO
	preset.max_offset = Vector2(0.05, 0.05)
	_shaker.add(preset)
	var seen := 0.0
	for _step in 30:
		_shaker.advance(STEP)
		assert_vector(_shaker.rotation_degrees()).is_equal(Vector3.ZERO)
		seen = maxf(seen, _shaker.view_offset().length())
		assert_float(absf(_shaker.view_offset().x)).is_less_equal(0.05)
	assert_float(seen).is_greater(0.001)


func test_the_bundled_presets_load_and_stay_subtle_to_hard_in_order() -> void:
	var peaks := {}
	for preset_name in [&"shot", &"landing", &"impact", &"explosion", &"sprint"]:
		var preset := load("res://core/camera_shake/presets/%s.tres" % preset_name) as ShakePreset
		assert_object(preset).is_not_null()
		var strongest := preset.max_rotation.length() * pow(preset.trauma, preset.exponent)
		peaks[preset_name] = strongest
	# A shot is a hair, a blast is felt, and nothing but a blast goes over a degree and a half.
	assert_float(peaks[&"shot"]).is_less(0.5)
	assert_float(peaks[&"impact"]).is_less(peaks[&"explosion"])
	assert_float(peaks[&"shot"]).is_less(peaks[&"explosion"])
	assert_float(peaks[&"sprint"]).is_less(0.5)
	assert_float(peaks[&"explosion"]).is_less(2.5)
	(
		assert_float((load("res://core/camera_shake/presets/explosion.tres") as ShakePreset).radius)
		. is_greater(0.0)
	)

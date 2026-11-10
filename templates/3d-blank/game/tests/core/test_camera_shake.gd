# The universal screen shake, the part that works out a shake: a one-shot adds trauma that dies
# away in its time and a held source stops when released. Everything is stepped by hand, so no
# test needs real time.
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


func test_every_default_of_a_preset_is_pinned() -> void:
	var fresh := ShakePreset.new()
	var pins := {
		&"trauma": 0.5,
		&"duration": 0.4,
		&"wave": ShakePreset.Wave.NOISE,
		&"frequency": 12.0,
		&"max_rotation": Vector3(1.0, 0.8, 0.4),
		&"max_offset": Vector2.ZERO,
		&"exponent": 2.0,
		&"blend_speed": 4.0,
		&"radius": 0.0,
	}
	assert_array(ExportPins.differences(fresh, pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, pins)).is_empty()
	var shaker := CameraShake.new()
	var own := {
		&"enabled": true,
		&"camera_strength": 1.0,
		&"reference": null,
		&"auto_advance": true,
		&"noise_seed": 1958,
	}
	assert_array(ExportPins.differences(shaker, own)).is_empty()
	assert_array(ExportPins.wrong_values(shaker, own)).is_empty()
	shaker.free()


func test_nothing_shakes_until_something_plays() -> void:
	assert_bool(_shaker.is_shaking()).is_false()
	assert_vector(_shaker.rotation_degrees()).is_equal(Vector3.ZERO)
	assert_vector(_shaker.view_offset()).is_equal(Vector2.ZERO)


func test_a_one_shot_shakes_then_decays_to_zero_in_its_time() -> void:
	var preset := _preset(1.0, 0.5)
	_shaker.add(preset)
	_shaker.advance(STEP)
	assert_float(_shaker.rotation_degrees().length()).is_greater(0.0)
	# Half-way through it is still shaking, below its start.
	var peak := _run(0.2)
	assert_float(peak).is_greater(0.0)
	assert_float(_shaker.trauma_of(preset)).is_equal_approx(1.0 - 13.0 * STEP / 0.5, 0.01)
	# After its duration (and a step of slack) nothing is left.
	_run(0.5)
	assert_bool(_shaker.is_shaking()).is_false()
	assert_vector(_shaker.rotation_degrees()).is_equal(Vector3.ZERO)


func test_a_light_hit_takes_less_time_than_a_hard_one() -> void:
	var light := _preset(0.25, 1.0)
	_shaker.add(light)
	_run(0.26)
	assert_bool(_shaker.is_shaking()).is_false()


func test_the_turn_never_goes_past_the_preset_at_full_trauma() -> void:
	var preset := _preset(1.0, 2.0)
	preset.max_rotation = Vector3(1.0, 0.5, 0.25)
	_shaker.add(preset)
	for _step in 60:
		_shaker.advance(STEP)
		var turn := _shaker.rotation_degrees()
		assert_float(absf(turn.x)).is_less_equal(1.0)
		assert_float(absf(turn.y)).is_less_equal(0.5)
		assert_float(absf(turn.z)).is_less_equal(0.25)


func test_a_light_hit_is_a_quarter_of_the_strength_of_the_squared_curve() -> void:
	var half := _preset(0.5, 10.0)
	var full := _preset(1.0, 10.0)
	_shaker.add(half)
	_shaker.advance(STEP)
	var half_turn := _shaker.rotation_degrees()
	_shaker.clear()
	_shaker.add(full)
	_shaker.advance(STEP)
	var full_turn := _shaker.rotation_degrees()
	# Same instant of the same noise: half the trauma, a quarter of the turn (a little less drain).
	assert_float(half_turn.length() / full_turn.length()).is_equal_approx(0.25, 0.02)


func test_plays_of_one_preset_stack_up_to_a_trauma_of_one() -> void:
	var preset := _preset(0.4, 1.0)
	_shaker.add(preset)
	_shaker.add(preset)
	assert_float(_shaker.trauma_of(preset)).is_equal_approx(0.8, 0.0001)
	_shaker.add(preset)
	assert_float(_shaker.trauma_of(preset)).is_equal(1.0)


func test_the_same_steps_give_the_same_shake() -> void:
	var other: CameraShake = auto_free(CameraShake.new())
	other.auto_advance = false
	add_child(other)
	var preset := _preset(0.8, 1.0)
	_shaker.add(preset)
	other.add(preset)
	for _step in 30:
		_shaker.advance(STEP)
		other.advance(STEP)
		assert_vector(other.rotation_degrees()).is_equal(_shaker.rotation_degrees())


func test_a_held_source_builds_to_its_level_and_stops_when_released() -> void:
	var preset := _preset()
	preset.wave = ShakePreset.Wave.SINE
	preset.exponent = 1.0
	preset.blend_speed = 2.0
	_shaker.hold(&"engine", preset, 1.0)
	_run(0.25)
	assert_float(_shaker.level_of(&"engine")).is_equal_approx(0.5, 0.001)
	_run(1.0)
	assert_float(_shaker.level_of(&"engine")).is_equal(1.0)
	# A held source does not run out by itself.
	assert_float(_run(2.0)).is_greater(0.5)
	_shaker.release(&"engine")
	_run(0.25)
	assert_float(_shaker.level_of(&"engine")).is_equal_approx(0.5, 0.001)
	_run(0.5)
	assert_float(_shaker.level_of(&"engine")).is_equal(0.0)
	assert_bool(_shaker.is_shaking()).is_false()
	assert_vector(_shaker.rotation_degrees()).is_equal(Vector3.ZERO)


func test_holding_at_zero_lets_a_source_go_and_never_starts_one() -> void:
	var preset := _preset()
	_shaker.hold(&"sprint", preset, 0.0)
	assert_bool(_shaker.is_shaking()).is_false()
	_shaker.hold(&"sprint", preset, 1.0)
	_run(0.5)
	assert_float(_shaker.level_of(&"sprint")).is_greater(0.0)
	_shaker.hold(&"sprint", preset, 0.0)
	_run(1.0)
	assert_bool(_shaker.is_shaking()).is_false()


func test_a_sine_source_turns_pitch_at_its_frequency_and_yaw_at_half() -> void:
	var preset := _preset()
	preset.wave = ShakePreset.Wave.SINE
	preset.exponent = 1.0
	preset.frequency = 4.0
	preset.blend_speed = 20.0
	preset.max_rotation = Vector3(1.0, 1.0, 1.0)
	_shaker.hold(&"gait", preset, 1.0)
	_run(0.5)
	var pitch_up := 0
	var yaw_up := 0
	var last_pitch := 0.0
	var last_yaw := 0.0
	for _step in 120:
		_shaker.advance(STEP)
		var turn := _shaker.rotation_degrees()
		if last_pitch <= 0.0 and turn.x > 0.0:
			pitch_up += 1
		if last_yaw <= 0.0 and turn.y > 0.0:
			yaw_up += 1
		last_pitch = turn.x
		last_yaw = turn.y
	# Two seconds: eight pitch cycles at 4 Hz, four of yaw (a start or end edge may add one).
	assert_int(pitch_up).is_between(7, 9)
	assert_int(yaw_up).is_between(3, 5)

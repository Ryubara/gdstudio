# The numbers a developer tunes are pinned: a change to a default is a change to how the game
# feels.
extends GdUnitTestSuite


func test_the_scene_holds_the_default_tuning_file() -> void:
	var tuning := load("res://gameplay/player/player_tuning.tres") as PlayerTuning
	assert_object(tuning).is_not_null()
	assert_float(tuning.walk_speed).is_equal(1.7)
	assert_float(tuning.run_speed).is_equal(4.0)
	assert_float(tuning.sprint_speed).is_equal(6.5)
	assert_float(tuning.jump_height).is_equal(1.25)
	assert_float(tuning.jump_rise_time).is_equal(0.4)
	assert_float(tuning.coyote_time).is_equal(0.12)
	assert_float(tuning.jump_buffer_time).is_equal(0.14)
	assert_float(tuning.step_height).is_equal(0.32)
	assert_float(tuning.max_slope).is_equal(48.0)
	var player := auto_free(load("res://gameplay/player/player.tscn").instantiate()) as Player
	assert_object(player.tuning).is_not_null()
	assert_str(player.tuning.resource_path).is_equal("res://gameplay/player/player_tuning.tres")


func test_gravity_and_jump_speed_make_the_jump_reach_its_height() -> void:
	var tuning := PlayerTuning.new()
	var apex := tuning.jump_speed() * tuning.jump_speed() / (2.0 * tuning.gravity())
	assert_float(apex).is_equal_approx(tuning.jump_height, 0.001)
	assert_float(tuning.jump_speed() / tuning.gravity()).is_equal_approx(
		tuning.jump_rise_time, 0.001
	)


func test_the_map_is_built_for_what_the_tuning_can_do() -> void:
	# The jump blocks rise 1 m at a time; the stairs rise less than the step height; the ramp is
	# gentler than the slope limit. A new tuning that breaks one of these breaks the sample map.
	var tuning := PlayerTuning.new()
	assert_float(tuning.jump_height + tuning.step_height).is_greater(1.0 + 0.2)
	assert_float(3.0 / 12.0).is_less(tuning.step_height)
	assert_float(rad_to_deg(atan2(2.0, 8.0))).is_less(tuning.max_slope)

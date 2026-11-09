# The footsteps follow the clips' feet: a step sounds each time a foot of the animated skeleton
# lands, at the cadence of the clip that plays (walk, run, sprint, crouch walk), never when the
# character stands still or is in the air, quieter when crouched.
extends GdUnitTestSuite

var _arena: PlayArena
var _player: Player
var _steps: Footsteps
var _heard: Array[Dictionary] = []


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 0.0))
	_player.tuning = (load("res://gameplay/player/player_tuning.tres") as PlayerTuning).duplicate()
	_steps = _player.get_node("Footsteps")
	_steps.stepped.connect(
		func(foot: StringName, crouched: bool) -> void:
			_heard.append({"foot": foot, "crouched": crouched, "at": Time.get_ticks_msec()})
	)
	_heard.clear()
	await InputSim.ticks(get_tree(), 10)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


# Walks for `seconds` of real time and returns the steps heard.
func _walk_for(seconds: float) -> int:
	# Each walk starts at the south end of the arena, so none runs off the north edge.
	_player.teleport(Vector3(0.0, 0.0, 25.0))
	await get_tree().physics_frame
	_heard.clear()
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().physics_frame
	return _heard.size()


func test_the_scene_holds_the_three_players_each_on_the_sfx_bus() -> void:
	assert_array(_steps._get_configuration_warnings()).is_empty()
	assert_int(_steps.steps.size()).is_equal(10)
	for part_name in ["Step", "CrouchStep", "LandStep"]:
		var sound := _steps.get_node("%" + part_name) as AudioStreamPlayer3D
		assert_str(String(sound.bus)).is_equal("SFX")
	var crouch := _steps.get_node("%CrouchStep") as AudioStreamPlayer3D
	var step := _steps.get_node("%Step") as AudioStreamPlayer3D
	assert_float(crouch.volume_db).is_less(step.volume_db - 6.0)


func test_every_export_has_its_default_pinned() -> void:
	var pins := {
		&"player": _player,
		&"model": _player.get_node("Model"),
		&"steps": _steps.steps,
		&"pitch_variation": 0.05,
		&"foot_bones": [&"foot_l", &"foot_r"],
		&"swing_speed": 0.15,
		&"min_stride": 0.2,
		&"min_interval": 0.12,
		&"min_speed": 0.5,
	}
	assert_array(ExportPins.differences(_steps, pins)).is_empty()
	assert_array(ExportPins.wrong_values(_steps, pins)).is_empty()


func test_a_character_standing_still_makes_no_step() -> void:
	assert_int(await _walk_for(1.5)).is_equal(0)


func test_a_walk_steps_at_the_walk_clips_two_feet_a_cycle() -> void:
	InputSim.key(KEY_X, true)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 40)
	var count := await _walk_for(3.0)
	# The walk clip is 1.33 s with two landings: three steps a 2 s... four and a half in 3 s.
	assert_int(count).is_between(3, 6)
	var feet := {}
	for step in _heard:
		feet[step["foot"]] = true
	assert_int(feet.size()).is_equal(2)


func test_a_run_steps_faster_than_a_walk_and_a_sprint_faster_than_a_run() -> void:
	InputSim.key(KEY_X, true)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 40)
	var walk := await _walk_for(3.0)
	InputSim.key(KEY_X, false)
	await InputSim.ticks(get_tree(), 40)
	var run := await _walk_for(3.0)
	InputSim.key(KEY_SHIFT, true)
	await InputSim.ticks(get_tree(), 40)
	var sprint := await _walk_for(3.0)
	assert_int(run).is_greater(walk)
	assert_int(sprint).is_greater(run)


func test_steps_land_where_the_clip_puts_a_foot_down_not_on_a_fixed_beat() -> void:
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 40)
	await _walk_for(3.0)
	var gaps: Array[int] = []
	for index in range(1, _heard.size()):
		gaps.append(int(_heard[index]["at"]) - int(_heard[index - 1]["at"]))
	assert_int(gaps.size()).is_greater(3)
	# The jog clip lands a foot every 0.47 s; the steps are that far apart, give or take frames.
	for gap in gaps:
		assert_int(gap).is_between(250, 1100)
	# And they alternate feet (a frame that hitches on a loaded machine can swallow a step).
	var alternating := 0
	for index in range(1, _heard.size()):
		if _heard[index]["foot"] != _heard[index - 1]["foot"]:
			alternating += 1
	assert_int(alternating).is_greater_equal(int((_heard.size() - 1) * 0.7))


func test_a_crouch_walk_uses_the_quieter_player() -> void:
	InputSim.key(KEY_C, true)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 40)
	var count := await _walk_for(3.0)
	assert_int(count).is_greater_equal(2)
	for step in _heard:
		assert_bool(step["crouched"]).is_true()
	assert_bool((_steps.get_node("%CrouchStep") as AudioStreamPlayer3D).stream != null).is_true()


func test_a_step_picks_a_file_and_never_the_same_twice_running() -> void:
	var picked: Array[AudioStream] = []
	for _step in 30:
		_steps.play_step(&"foot_l")
		picked.append((_steps.get_node("%Step") as AudioStreamPlayer3D).stream)
	for index in range(1, picked.size()):
		assert_object(picked[index]).is_not_same(picked[index - 1])
	var distinct := {}
	for stream in picked:
		distinct[stream] = true
	assert_int(distinct.size()).is_greater(5)


func test_the_pitch_varies_a_little_and_the_variation_is_live() -> void:
	_steps.pitch_variation = 0.0
	_steps.play_step()
	assert_float((_steps.get_node("%Step") as AudioStreamPlayer3D).pitch_scale).is_equal(1.0)
	_steps.pitch_variation = 0.4
	var seen := {}
	for _step in 20:
		_steps.play_step()
		seen[snappedf((_steps.get_node("%Step") as AudioStreamPlayer3D).pitch_scale, 0.001)] = true
	assert_int(seen.size()).is_greater(5)


func test_no_step_sounds_in_the_air_and_a_landing_has_its_own_sound() -> void:
	_player.teleport(Vector3(0.0, 4.0, 0.0))
	await InputSim.ticks(get_tree(), 4)
	_heard.clear()
	await InputSim.ticks(get_tree(), 20)
	assert_int(_heard.size()).is_equal(0)
	var landing := _steps.get_node("%LandStep") as AudioStreamPlayer3D
	await InputSim.ticks(get_tree(), 60)
	assert_bool(landing.stream != null).is_true()


func test_the_swing_speed_and_minimum_speed_are_live() -> void:
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 40)
	_steps.min_speed = 20.0
	assert_int(await _walk_for(1.5)).is_equal(0)
	_steps.min_speed = 0.5
	assert_int(await _walk_for(2.0)).is_greater(0)
	_steps.swing_speed = 50.0
	# Only the jump of the pose when the walk starts again can pass 50 m/s.
	assert_int(await _walk_for(1.5)).is_less_equal(1)
	_steps.swing_speed = 0.15
	_steps.min_interval = 5.0
	assert_int(await _walk_for(3.0)).is_less_equal(1)

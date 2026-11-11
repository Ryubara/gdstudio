# The play states (Deadnight's, the research for #882 section 1.5): Aggressive, Careful and Safe
# from the health share less the pressure of the hostiles seen; more careful at once, bolder only
# past the line by the hysteresis and after the dwell, so a character on the edge changes state
# once; courage and `flee_below_health` set the lines.
extends GdUnitTestSuite

const STEP := 0.1


# The grunt with the lines at 0.3 and 0.6 (courage 0.5, flee below 0.3).
func _grunt() -> AiProfile:
	var profile := (
		(load("res://gameplay/ai/profiles/grunt.tres") as AiProfile).duplicate() as AiProfile
	)
	profile.courage = 0.5
	profile.flee_below_health = 0.3
	return profile


func test_the_lines_come_from_courage_and_flee_below_health() -> void:
	var profile := _grunt()
	profile.courage = 0.5
	profile.flee_below_health = 0.3
	assert_float(profile.safe_line()).is_equal_approx(0.3, 0.0001)
	assert_float(profile.careful_line()).is_equal_approx(0.6, 0.0001)
	profile.courage = 1.0
	assert_float(profile.safe_line()).is_equal_approx(0.15, 0.0001)
	profile.courage = 0.0
	assert_float(profile.safe_line()).is_equal_approx(0.45, 0.0001)
	profile.flee_below_health = 0.0
	assert_float(profile.safe_line()).is_equal(0.0)


func test_it_turns_careful_then_safe_at_once_as_health_falls() -> void:
	var profile := _grunt()
	var play := AiPlayState.new()
	assert_int(play.current).is_equal(AiPlayState.State.AGGRESSIVE)
	play.feed(0.9, 0, STEP, profile)
	assert_int(play.current).is_equal(AiPlayState.State.AGGRESSIVE)
	assert_bool(play.feed(0.5, 0, STEP, profile)).is_true()
	assert_int(play.current).is_equal(AiPlayState.State.CAREFUL)
	assert_bool(play.feed(0.2, 0, STEP, profile)).is_true()
	assert_int(play.current).is_equal(AiPlayState.State.SAFE)
	# Straight from Aggressive to Safe on one big hit.
	var other := AiPlayState.new()
	other.feed(0.1, 0, STEP, profile)
	assert_int(other.current).is_equal(AiPlayState.State.SAFE)


func test_it_turns_bolder_only_past_the_hysteresis_and_after_the_dwell() -> void:
	var profile := _grunt()
	var play := AiPlayState.new()
	play.feed(0.5, 0, STEP, profile)
	assert_int(play.current).is_equal(AiPlayState.State.CAREFUL)
	# Just over the line, inside the hysteresis: stays Careful however long.
	for _i in 100:
		play.feed(0.62, 0, STEP, profile)
	assert_int(play.current).is_equal(AiPlayState.State.CAREFUL)
	# Past the hysteresis but inside the dwell of a fresh change: waits.
	var fresh := AiPlayState.new()
	fresh.feed(0.5, 0, STEP, profile)
	fresh.feed(0.9, 0, STEP, profile)
	assert_int(fresh.current).is_equal(AiPlayState.State.CAREFUL)
	for _i in int(profile.play_dwell / STEP) + 1:
		fresh.feed(0.9, 0, STEP, profile)
	assert_int(fresh.current).is_equal(AiPlayState.State.AGGRESSIVE)


func test_a_character_on_the_edge_changes_state_once() -> void:
	var profile := _grunt()
	var play := AiPlayState.new()
	var changes := [0]
	play.changed.connect(func(_now: int, _was: int) -> void: changes[0] += 1)
	# Health wobbling across the Careful line by less than the hysteresis, for 20 s.
	for index in 200:
		play.feed(0.6 + (0.03 if index % 2 == 0 else -0.03), 0, STEP, profile)
	assert_int(changes[0]).is_equal(1)
	assert_int(play.current).is_equal(AiPlayState.State.CAREFUL)


func test_pressure_from_hostiles_seen_makes_it_more_careful() -> void:
	var profile := _grunt()
	var calm := AiPlayState.new()
	calm.feed(0.75, 0, STEP, profile)
	assert_int(calm.current).is_equal(AiPlayState.State.AGGRESSIVE)
	var pressed := AiPlayState.new()
	pressed.feed(0.75, 3, STEP, profile)
	assert_int(pressed.current).is_equal(AiPlayState.State.CAREFUL)
	# The pressure has a cap.
	var crowded := AiPlayState.new()
	crowded.feed(0.75, 20, STEP, profile)
	assert_float(crowded.score).is_equal_approx(0.75 - profile.max_pressure, 0.0001)


func test_courage_moves_the_lines_a_brave_one_holds_on_where_a_coward_hides() -> void:
	var brave := _grunt()
	brave.courage = 1.0
	var coward := _grunt()
	coward.courage = 0.0
	var bold := AiPlayState.new()
	var timid := AiPlayState.new()
	bold.feed(0.4, 0, STEP, brave)
	timid.feed(0.4, 0, STEP, coward)
	assert_int(bold.current).is_equal(AiPlayState.State.CAREFUL)
	assert_int(timid.current).is_equal(AiPlayState.State.SAFE)


func test_no_flee_line_never_plays_safe() -> void:
	var profile := _grunt()
	profile.flee_below_health = 0.0
	profile.careful_margin = 0.0
	var play := AiPlayState.new()
	play.feed(0.01, 5, STEP, profile)
	assert_int(play.current).is_not_equal(AiPlayState.State.SAFE)

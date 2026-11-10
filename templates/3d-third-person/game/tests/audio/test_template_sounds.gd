# The sounds the template ships for the gameplay to play: a coin pickup under half a second, at
# least four soft footsteps to cycle and five pistol shots, each short and starting at once.
extends GdUnitTestSuite

const COIN := "res://assets/audio/coin/coin_pickup_%d.ogg"
const STEP := "res://assets/audio/footsteps/footstep_soft_%d.ogg"
const SHOT := "res://assets/audio/pistol/pistol_shot_%d.ogg"


func test_the_coin_pickup_is_three_to_four_tenths_of_a_second() -> void:
	var found := 0
	for n in range(1, 10):
		if not ResourceLoader.exists(COIN % n):
			continue
		found += 1
		var coin: AudioStreamOggVorbis = load(COIN % n)
		assert_float(coin.get_length()).is_between(0.3, 0.4)
	assert_int(found).is_greater_equal(3)


func test_there_are_at_least_four_single_steps_each_under_half_a_second() -> void:
	var found := 0
	for n in range(1, 30):
		if not ResourceLoader.exists(STEP % n):
			continue
		found += 1
		var step: AudioStreamOggVorbis = load(STEP % n)
		assert_float(step.get_length()).is_between(0.08, 0.5)
		assert_bool(step.loop).is_false()
	assert_int(found).is_greater_equal(4)


func test_there_are_five_pistol_shots_each_a_short_report_with_no_tail() -> void:
	var found := 0
	for n in range(1, 10):
		if not ResourceLoader.exists(SHOT % n):
			continue
		found += 1
		var shot: AudioStreamOggVorbis = load(SHOT % n)
		assert_float(shot.get_length()).is_between(0.05, 0.2)
		assert_bool(shot.loop).is_false()
	assert_int(found).is_equal(5)


func test_the_wind_of_the_base_is_still_here() -> void:
	assert_bool(ResourceLoader.exists("res://assets/audio/wind/wind_soft_1.ogg")).is_true()

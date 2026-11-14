# The sounds the template ships for the gameplay to play: a coin pickup under half a second, at
# least four soft footsteps to cycle, five pistol shots and four rifle shots, each starting at once.
extends GdUnitTestSuite

const COIN := "res://assets/audio/coin/coin_pickup_%d.ogg"
const STEP := "res://assets/audio/footsteps/footstep_soft_%d.ogg"
const SHOT := "res://assets/audio/pistol/pistol_shot_%d.ogg"
const RIFLE_SHOT := "res://assets/audio/rifle/rifle_shot_%d.ogg"


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


# A shot is its report and a short open-air tail (gdstudio #1414). The tail stays inside the
# time the weapon's three voices give it: the oldest voice is cut at the fourth shot, so a pistol at
# 4 shots a second keeps 0.75 s and the rifle at 10 keeps 0.3 s; the rifle's shots end by then.
func test_there_are_five_pistol_shots_each_a_report_and_a_short_tail() -> void:
	assert_array(_lengths(SHOT)).has_size(5)
	for length in _lengths(SHOT):
		assert_float(length).is_between(0.25, 0.5)


func test_there_are_four_rifle_shots_each_ending_before_its_voice_is_taken() -> void:
	assert_array(_lengths(RIFLE_SHOT)).has_size(4)
	for length in _lengths(RIFLE_SHOT):
		assert_float(length).is_between(0.18, 0.31)


func test_the_wind_of_the_base_is_still_here() -> void:
	assert_bool(ResourceLoader.exists("res://assets/audio/wind/wind_soft_1.ogg")).is_true()


# The lengths of the numbered files of `pattern`, each a sound that does not loop.
func _lengths(pattern: String) -> Array[float]:
	var lengths: Array[float] = []
	for n in range(1, 10):
		if not ResourceLoader.exists(pattern % n):
			continue
		var sound: AudioStreamOggVorbis = load(pattern % n)
		assert_bool(sound.loop).is_false()
		lengths.append(sound.get_length())
	return lengths

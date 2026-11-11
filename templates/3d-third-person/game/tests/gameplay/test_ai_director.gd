# The `AiDirector` budgets every AI character of a level: each thinks at its profile's rate on a
# phase of its own (never all in one tick), the shared budget refuses the work over its count a
# tick, the tiers follow the distance to the nearest player with a margin and a cap, a profile's
# edit applies while it runs, and a far character stepped every few ticks walks as far.
extends GdUnitTestSuite

var _arena: AiArena
var _think_ticks: Dictionary = {}


func before_test() -> void:
	_think_ticks.clear()
	_arena = auto_free(AiArena.new())
	add_child(_arena)


# Walking characters play footsteps; a voice still playing at exit is reported as a leak.
func after_test() -> void:
	AudioDrain.stop_all(_arena)


# Records the director's tick of each think of `character`.
func _watch(character: AiCharacter) -> void:
	_think_ticks[character] = []
	character.thought.connect(
		func(_seconds: float) -> void: _think_ticks[character].append(_arena.director.tick)
	)


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


# Characters in a row near the viewer (all at the Full tier).
func _row(count: int) -> Array[AiCharacter]:
	var made: Array[AiCharacter] = []
	for index in count:
		made.append(_arena.add_character(Vector3(index * 1.5 - 4.0, 0.0, -3.0)))
	return made


func test_each_character_thinks_at_its_rate_on_a_tick_of_its_own() -> void:
	var characters := _row(6)
	_arena.add_director()
	for character in characters:
		_watch(character)
	await _ticks(120)
	var per_tick := {}
	for character in characters:
		var ticks: Array = _think_ticks[character]
		# 10 Hz at 60 ticks a second: one think every 6 ticks, 20 in 120.
		assert_int(ticks.size()).is_between(19, 21)
		for index in range(1, ticks.size()):
			assert_int(ticks[index] - ticks[index - 1]).is_equal(6)
		for at: int in ticks:
			per_tick[at] = per_tick.get(at, 0) + 1
	for at: int in per_tick:
		assert_int(per_tick[at]).override_failure_message("two thinks on tick %d" % at).is_equal(1)


func test_more_characters_than_ticks_in_an_interval_share_them_evenly() -> void:
	var characters := _row(12)
	_arena.add_director()
	for character in characters:
		_watch(character)
	await _ticks(60)
	var per_tick := {}
	for character in characters:
		for at: int in _think_ticks[character]:
			per_tick[at] = per_tick.get(at, 0) + 1
	for at: int in per_tick:
		assert_int(per_tick[at]).is_less_equal(2)


func test_the_budget_refuses_the_ray_over_its_count_a_tick() -> void:
	var budget := AiBudget.new()
	budget.rays_per_tick = 3
	for _i in 3:
		assert_bool(budget.take_ray()).is_true()
	assert_bool(budget.take_ray()).is_false()
	assert_int(budget.refused).is_equal(1)
	budget.reset()
	assert_bool(budget.take_ray()).is_true()


func test_the_director_shares_the_ray_budget_between_characters_and_resets_it_each_tick() -> void:
	var characters := _row(12)
	var director := _arena.add_director()
	director.rays_per_tick = 3
	var granted := {}
	for character in characters:
		character.thought.connect(
			func(_seconds: float) -> void:
				for _i in 2:
					if character.budget.take_ray():
						granted[director.tick] = granted.get(director.tick, 0) + 1
		)
	await _ticks(60)
	assert_int(granted.size()).is_greater(5)
	for at: int in granted:
		assert_int(granted[at]).is_less_equal(3)
	assert_object(characters[0].budget).is_same(director.budget)


func test_thinks_over_the_count_a_tick_wait_for_the_next_tick() -> void:
	var characters := _row(4)
	var director := _arena.add_director()
	director.thinks_per_tick = 1
	for character in characters:
		character.profile.think_rate = 60.0
		_watch(character)
	await _ticks(40)
	var per_tick := {}
	for character in characters:
		assert_int(_think_ticks[character].size()).is_greater(5)
		for at: int in _think_ticks[character]:
			per_tick[at] = per_tick.get(at, 0) + 1
	for at: int in per_tick:
		assert_int(per_tick[at]).is_equal(1)


func test_a_profile_edit_applies_while_it_runs() -> void:
	var character := _arena.add_character(Vector3(0.0, 0.0, -3.0))
	_arena.add_director()
	_watch(character)
	await _ticks(60)
	assert_int(_think_ticks[character].size()).is_between(9, 11)
	_think_ticks[character].clear()
	character.profile.think_rate = 30.0
	await _ticks(60)
	assert_int(_think_ticks[character].size()).is_between(28, 31)
	_think_ticks[character].clear()
	character.profile.think_rate = 0.0
	await _ticks(30)
	assert_int(_think_ticks[character].size()).is_less_equal(1)


func test_the_tier_follows_the_distance_with_a_margin() -> void:
	var profile := AiProfile.new()
	const FULL := AiDirector.Tier.FULL
	const REDUCED := AiDirector.Tier.REDUCED
	const DORMANT := AiDirector.Tier.DORMANT
	assert_int(AiDirector.tier_for(DORMANT, 10.0, profile)).is_equal(FULL)
	assert_int(AiDirector.tier_for(DORMANT, 40.0, profile)).is_equal(REDUCED)
	assert_int(AiDirector.tier_for(FULL, 90.0, profile)).is_equal(DORMANT)
	# Between full_range (25) and full_range + margin (29): a Full one stays, a Reduced one waits.
	assert_int(AiDirector.tier_for(FULL, 27.0, profile)).is_equal(FULL)
	assert_int(AiDirector.tier_for(REDUCED, 27.0, profile)).is_equal(REDUCED)
	assert_int(AiDirector.tier_for(FULL, 30.0, profile)).is_equal(REDUCED)
	assert_int(AiDirector.tier_for(REDUCED, 72.0, profile)).is_equal(REDUCED)
	assert_int(AiDirector.tier_for(DORMANT, 72.0, profile)).is_equal(DORMANT)


func test_a_character_changes_tier_as_the_player_moves_away_and_back() -> void:
	var character := _arena.add_character(Vector3(0.0, 0.0, -3.0))
	_arena.add_director()
	var seen: Array[int] = []
	character.tier_changed.connect(func(tier: int) -> void: seen.append(tier))
	assert_int(character.tier).is_equal(AiDirector.Tier.FULL)
	_arena.viewer.position = Vector3(0.0, 0.0, 24.0)  # 27 m away: inside the margin
	await _ticks(17)
	assert_int(character.tier).is_equal(AiDirector.Tier.FULL)
	_arena.viewer.position = Vector3(0.0, 0.0, 40.0)
	await _ticks(17)
	assert_int(character.tier).is_equal(AiDirector.Tier.REDUCED)
	_arena.viewer.position = Vector3(0.0, 0.0, 24.0)
	await _ticks(17)
	assert_int(character.tier).is_equal(AiDirector.Tier.REDUCED)
	_arena.viewer.position = Vector3(0.0, 0.0, 120.0)
	await _ticks(17)
	assert_int(character.tier).is_equal(AiDirector.Tier.DORMANT)
	_arena.viewer.position = Vector3.ZERO
	await _ticks(17)
	assert_int(character.tier).is_equal(AiDirector.Tier.FULL)
	assert_array(seen).is_equal([1, 2, 0])


func test_a_reduced_character_thinks_less_often() -> void:
	var character := _arena.add_character(Vector3(0.0, 0.0, -40.0))
	_arena.add_director()
	_watch(character)
	await _ticks(120)
	assert_int(character.tier).is_equal(AiDirector.Tier.REDUCED)
	# 2 Hz for two seconds.
	assert_int(_think_ticks[character].size()).is_between(3, 5)


func test_the_full_tier_is_capped_and_goes_to_the_nearest() -> void:
	var director := _arena.add_director()
	director.desktop_full_cap = 2
	director.web_full_cap = 2
	var characters: Array[AiCharacter] = []
	for index in 4:
		characters.append(_arena.add_character(Vector3(0.0, 0.0, -2.0 - index * 3.0)))
	await _ticks(17)
	assert_int(director.count_at(AiDirector.Tier.FULL)).is_equal(2)
	assert_int(characters[3].tier).is_equal(AiDirector.Tier.REDUCED)
	# The viewer walks to the far end: the two nearest it now take the Full tier.
	_arena.viewer.position = Vector3(0.0, 0.0, -14.0)
	await _ticks(33)
	assert_int(director.count_at(AiDirector.Tier.FULL)).is_equal(2)
	assert_int(characters[3].tier).is_equal(AiDirector.Tier.FULL)
	assert_int(characters[0].tier).is_equal(AiDirector.Tier.REDUCED)


func test_the_population_cap_refuses_one_more() -> void:
	var director := _arena.add_director()
	director.desktop_cap = 2
	director.web_cap = 2
	for index in 3:
		_arena.add_character(Vector3(index * 2.0, 0.0, -3.0))
	assert_int(director.count()).is_equal(2)


func test_the_director_steps_the_bodies_and_lets_one_go_when_it_leaves() -> void:
	var character := _arena.add_character(Vector3(0.0, 0.0, -3.0))
	assert_bool(character.is_physics_processing()).is_true()
	var director := _arena.add_director()
	assert_object(character.director).is_same(director)
	assert_bool(character.is_physics_processing()).is_false()
	character.ai_controller().walk_direction = Vector3.RIGHT
	await _ticks(30)
	assert_float(character.global_position.x).is_greater(0.5)
	_arena.remove_child(character)
	assert_int(director.count()).is_equal(0)
	assert_bool(character.is_physics_processing()).is_true()
	character.free()


# A Reduced body is stepped every 3rd tick with three ticks' time and a Dormant one every 6th,
# so all three walk about as far in the same time.
func test_a_far_character_stepped_less_often_walks_as_far() -> void:
	var near := _arena.add_character(Vector3(-3.0, 0.0, -3.0))
	var mid := _arena.add_character(Vector3(-3.0, 0.0, -40.0))
	var far := _arena.add_character(Vector3(-3.0, 0.0, -100.0))
	var big := _arena.add_block(Vector2(0.0, -50.0), Vector3(60.0, 1.0, 120.0), 0.0)
	assert_object(big).is_not_null()
	var director := _arena.add_director()
	await _ticks(10)
	assert_int(near.tier).is_equal(AiDirector.Tier.FULL)
	assert_int(mid.tier).is_equal(AiDirector.Tier.REDUCED)
	assert_int(far.tier).is_equal(AiDirector.Tier.DORMANT)
	var starts: Array[float] = []
	for character: AiCharacter in [near, mid, far]:
		starts.append(character.global_position.x)
		character.ai_controller().walk_direction = Vector3.RIGHT
		character.ai_controller().walk_strength = 0.5
	await _ticks(90)
	var walked: Array[float] = []
	for index in 3:
		walked.append(([near, mid, far][index] as AiCharacter).global_position.x - starts[index])
	assert_float(walked[0]).is_greater(2.0)
	assert_float(walked[1]).is_equal_approx(walked[0], walked[0] * 0.15)
	assert_float(walked[2]).is_equal_approx(walked[0], walked[0] * 0.25)
	assert_int(director.count()).is_equal(3)

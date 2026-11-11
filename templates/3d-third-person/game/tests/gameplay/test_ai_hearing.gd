# What an AI character hears and is told: a noise inside its radius is heard and one outside is
# not; past the board's occlusion share a wall muffles it; a friend's noise is not heard; the
# character's own `AiNoiseMaker` makes footsteps by how fast it moves (quieter crouched) and a shot
# when its weapon fires; an ally's telling arrives once however many allies pass it on, and is
# believed but never a fire target; the ray budget caps the rays of 200 characters a tick; the
# board's faction index hears in order among friends, and a grudge reads past it.
extends GdUnitTestSuite

var _arena: SensesArena


func before_test() -> void:
	_arena = auto_free(SensesArena.new())
	add_child(_arena)


func after_test() -> void:
	AudioDrain.stop_all(_arena)


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _until(done: Callable, limit: int) -> int:
	for tick in limit:
		if done.call():
			return tick
		await get_tree().physics_frame
	return -1 if not done.call() else limit


func _senses(character: AiCharacter) -> AiSenses:
	return character.senses as AiSenses


func test_a_noise_inside_its_radius_is_heard_and_one_outside_is_not() -> void:
	_arena.add_director()
	var character := _arena.add_watcher("Grunt", Vector3.ZERO, 0.0)
	var near := _arena.add_target("Near", Vector3(0.0, 0.0, -4.0))
	var far := _arena.add_target("Far", Vector3(0.0, 0.0, -20.0))
	var senses := _senses(character)
	var heard: Array[StringName] = []
	senses.heard.connect(
		func(kind: StringName, _at: Vector3, _source: Node3D) -> void: heard.append(kind)
	)
	await _ticks(10)
	assert_float(_arena.board.radius_of(AiNoise.FOOTSTEP)).is_less(20.0)
	AiNoise.emit(_arena, AiNoise.FOOTSTEP, far.position, 1.0, far)
	AiNoise.emit(_arena, AiNoise.FOOTSTEP, near.position, 1.0, near)
	await _ticks(12)
	assert_array(heard).is_equal([AiNoise.FOOTSTEP])
	assert_bool(senses.beliefs.knows(far)).is_false()
	var belief := senses.beliefs.of(near)
	assert_int(belief.source).is_equal(AiBelief.Source.HEARD)
	assert_float(belief.awareness).is_greater_equal(character.profile.suspicious_at)
	assert_bool(belief.can_fire_at()).is_false()
	await _ticks(12)
	assert_int(heard.size()).is_equal(1)


func test_a_wall_muffles_a_noise_past_the_occlusion_share() -> void:
	_arena.add_director()
	var open := _arena.add_watcher("Open", Vector3(-10.0, 0.0, 0.0), 0.0)
	var walled := _arena.add_watcher("Walled", Vector3(10.0, 0.0, 0.0), 0.0)
	_arena.add_wall(8.0, 12.0, -3.0)
	var first := _arena.add_target("First", Vector3(-10.0, 0.0, -7.0))
	var second := _arena.add_target("Second", Vector3(10.0, 0.0, -7.0))
	var radius := _arena.board.radius_of(AiNoise.FOOTSTEP)
	assert_float(7.0).is_between(radius * _arena.board.occlusion, radius)
	await _ticks(10)
	AiNoise.emit(_arena, AiNoise.FOOTSTEP, first.position, 1.0, first)
	AiNoise.emit(_arena, AiNoise.FOOTSTEP, second.position, 1.0, second)
	await _ticks(12)
	assert_bool(_senses(open).beliefs.knows(first)).is_true()
	assert_bool(_senses(walled).beliefs.knows(second)).is_false()


func test_a_friend_noise_is_not_heard() -> void:
	_arena.add_director()
	var character := _arena.add_watcher("Grunt", Vector3.ZERO, 0.0)
	var friend := _arena.add_target("Friend", Vector3(0.0, 0.0, -3.0), &"enemy")
	await _ticks(10)
	AiNoise.emit(_arena, AiNoise.SHOT, friend.position, 1.0, friend)
	await _ticks(12)
	assert_int(_senses(character).beliefs.size()).is_equal(0)


func test_a_close_shot_alerts_and_an_impact_is_something_not_someone() -> void:
	_arena.add_director()
	var character := _arena.add_watcher("Grunt", Vector3.ZERO, 0.0)
	var shooter := _arena.add_target("Shooter", Vector3(0.0, 0.0, -5.0))
	await _ticks(10)
	AiNoise.emit(_arena, AiNoise.IMPACT, Vector3(1.0, 0.0, 1.0))
	await _ticks(12)
	var senses := _senses(character)
	assert_int(senses.beliefs.size()).is_equal(1)
	assert_object(senses.beliefs.by_id[0].entity()).is_null()
	AiNoise.emit(_arena, AiNoise.SHOT, shooter.position, 1.0, shooter)
	AiNoise.emit(_arena, AiNoise.SHOT, shooter.position, 1.0, shooter)
	await _ticks(12)
	assert_bool(senses.beliefs.of(shooter).noticed).is_true()
	assert_int(character.situation.current).is_equal(AiSituation.Situation.ALERT)


func test_footsteps_follow_speed_and_crouch_and_a_shot_is_heard() -> void:
	_arena.add_director()
	var walker := _arena.add_watcher("Walker", Vector3(0.0, 0.0, 0.0), 0.0)
	var maker := walker.get_node("NoiseMaker") as AiNoiseMaker
	assert_object(maker).is_not_null()
	var made: Array[AiNoiseRecord] = []
	var start := _arena.board.newest
	walker.ai_controller().walk_direction = Vector3.BACK
	walker.ai_controller().walk_strength = 1.0
	for _tick in 120:
		await get_tree().physics_frame
		for serial in range(start + 1, _arena.board.newest + 1):
			made.append(_arena.board.noise_at(serial))
		start = _arena.board.newest
	walker.ai_controller().walk_direction = Vector3.ZERO
	var steps := made.filter(
		func(noise: AiNoiseRecord) -> bool: return noise.kind == AiNoise.FOOTSTEP
	)
	assert_int(steps.size()).is_greater(2)
	assert_object(steps[0].source()).is_same(walker)
	walker.crouching = true
	var crouched := maker.footstep_loudness()
	walker.crouching = false
	var standing := maker.footstep_loudness()
	assert_float(crouched).is_less(standing)
	var shots := _arena.board.newest
	walker.weapon.pull(walker.global_position + Vector3.UP * 1.4, Vector3.BACK)
	assert_int(_arena.board.newest).is_greater(shots)
	assert_str(String(_arena.board.noise_at(shots + 1).kind)).is_equal(String(AiNoise.SHOT))


func test_an_ally_share_arrives_once_and_is_not_a_fire_target() -> void:
	_arena.add_director()
	var seer := _arena.add_watcher("Seer", Vector3.ZERO, PI)
	var mates: Array[AiCharacter] = []
	for index in 3:
		mates.append(_arena.add_watcher("Mate%d" % index, Vector3(2.0 + index, 0.0, 2.0), 0.0))
	var ally := load("res://gameplay/ai/profiles/ally.tres") as AiProfile
	var stranger := _arena.add_watcher("Stranger", Vector3(-3.0, 0.0, 2.0), 0.0, ally)
	var target := _arena.add_target("Player", Vector3(0.0, 0.0, -5.0))
	var told := func() -> bool:
		for mate in mates:
			if not _senses(mate).beliefs.believes(target):
				return false
		return true
	assert_int(await _until(told, 240)).is_not_negative()
	await _ticks(180)
	for mate in mates:
		var senses := _senses(mate)
		assert_int(senses.shares_received).is_equal(1)
		assert_int(senses.beliefs.of(target).source).is_equal(AiBelief.Source.TOLD)
		assert_object(senses.beliefs.fire_target(mate.global_position)).is_null()
	assert_int(_senses(seer).shares_received).is_equal(0)
	assert_int(_senses(stranger).shares_received).is_equal(0)


func test_the_ray_budget_caps_the_rays_of_200_characters_a_tick() -> void:
	var director := _arena.add_director()
	director.desktop_cap = 200
	director.thinks_per_tick = 40
	var characters: Array[AiCharacter] = []
	for row in 10:
		for column in 20:
			var spot := Vector3(-11.4 + column * 1.2, 0.0, row * 1.2)
			characters.append(_arena.add_watcher("G%d_%d" % [row, column], spot, PI))
	for x in [-6.0, -2.0, 2.0, 6.0]:
		_arena.add_target("T%d" % x, Vector3(x, 0.0, -6.0))
	var busiest := 0
	var most_a_think := 0
	for tick in 90:
		await get_tree().physics_frame
		assert_int(director.budget.rays).is_less_equal(director.rays_per_tick)
		busiest = maxi(busiest, director.budget.rays)
		for character in characters:
			most_a_think = maxi(most_a_think, _senses(character).last_rays)
	assert_int(busiest).is_equal(director.rays_per_tick)
	assert_int(most_a_think).is_less_equal(characters[0].profile.max_rays_per_think)
	var total := 0
	for character in characters:
		total += _senses(character).rays_cast
	assert_int(total).is_less_equal(90 * director.rays_per_tick)
	assert_int(total).is_greater(60 * director.rays_per_tick)


# A character that made a noise and was freed before a listener's think (a despawn, a test that
# frees a body): the record's faction member went with it, and the listener skips the noise without
# a script error (it was "previously freed" in `_noise_band`, kit #968's tables found it).
func test_a_noise_whose_maker_was_freed_is_skipped() -> void:
	_arena.add_director()
	var character := _arena.add_watcher("Grunt", Vector3.ZERO, 0.0)
	var maker := _arena.add_target("Maker", Vector3(0.0, 0.0, -4.0))
	await _ticks(2)
	AiNoise.emit(_arena, AiNoise.SHOT, maker.position, 1.0, maker)
	maker.free()
	await _ticks(20)
	assert_int(_senses(character).beliefs.size()).is_equal(0)


# The listener walks only the factions it cares about from the board's index (kit #1204): after a
# board's worth of friends' shots it hears nothing, then a noise with no source and an enemy's step
# among more friends' shots, in the order they were made; the friends' list stays bounded.
func test_the_faction_index_hears_in_order_among_friends() -> void:
	_arena.add_director()
	var character := _arena.add_watcher("Grunt", Vector3.ZERO, 0.0)
	var friend := _arena.add_target("Friend", Vector3(0.0, 0.0, -3.0), &"enemy")
	var foe := _arena.add_target("Foe", Vector3(2.0, 0.0, -5.0))
	var senses := _senses(character)
	var heard: Array = []
	senses.heard.connect(
		func(kind: StringName, _at: Vector3, source: Node3D) -> void: heard.append([kind, source])
	)
	await _ticks(10)
	var board := _arena.board
	for _i in board.capacity * 3:
		AiNoise.emit(_arena, AiNoise.SHOT, friend.position, 1.0, friend)
	await _ticks(12)
	assert_array(heard).is_empty()
	assert_int(board.by_faction[&"enemy"].size()).is_less(board.capacity * 2)
	AiNoise.emit(_arena, AiNoise.IMPACT, Vector3(1.0, 0.0, 1.0))
	AiNoise.emit(_arena, AiNoise.SHOT, friend.position, 1.0, friend)
	AiNoise.emit(_arena, AiNoise.FOOTSTEP, foe.position, 1.0, foe)
	AiNoise.emit(_arena, AiNoise.SHOT, friend.position, 1.0, friend)
	await _ticks(12)
	assert_array(heard).is_equal([[AiNoise.IMPACT, null], [AiNoise.FOOTSTEP, foe]])
	assert_int(senses.beliefs.of(foe).source).is_equal(AiBelief.Source.HEARD)


# A character with a grudge reads every noise (a grudge is toward one maker, not a faction): it
# hears the friend it holds the grudge against, and still not another friend.
func test_a_grudge_hears_that_friend_past_the_faction_index() -> void:
	_arena.add_director()
	var character := _arena.add_watcher("Grunt", Vector3.ZERO, 0.0)
	var rival := _arena.add_target("Rival", Vector3(0.0, 0.0, -3.0), &"enemy")
	var other := _arena.add_target("Other", Vector3(2.0, 0.0, -3.0), &"enemy")
	await _ticks(10)
	AiFactionMember.of(character).grudge(rival, -100.0)
	AiNoise.emit(_arena, AiNoise.SHOT, other.position, 1.0, other)
	AiNoise.emit(_arena, AiNoise.SHOT, rival.position, 1.0, rival)
	await _ticks(12)
	var senses := _senses(character)
	assert_bool(senses.beliefs.knows(rival)).is_true()
	assert_bool(senses.beliefs.knows(other)).is_false()

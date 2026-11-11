# What an AI character can know, after Deadnight's perception list (kit
# `docs/gamedev/bots.md#perception`): a target behind a wall with the character facing away is never
# believed; one that steps out of cover is believed no sooner than `time_to_notice` plus the
# reaction delay after the first clear ray; a hit from behind is believed at once and an attacker
# that leaves the view while hitting stays believed; a thing within `near_radius` is noticed
# whichever way the character faces; a memory expires and is never a fire target; a friend is not
# perceived; a Dormant character does not look; a client of a remote server senses nothing; the
# awareness drives the situation; the same start gives the same beliefs.
extends GdUnitTestSuite

const GRUNT := "res://gameplay/ai/profiles/grunt.tres"

var _arena: SensesArena


func before_test() -> void:
	_arena = auto_free(SensesArena.new())
	add_child(_arena)
	_arena.add_director()


func after_test() -> void:
	AudioDrain.stop_all(_arena)
	AiNoise._runs_here = -1


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


# Ticks until `done` returns true; the ticks it took, or -1 after `limit`.
func _until(done: Callable, limit: int) -> int:
	for tick in limit:
		if done.call():
			return tick
		await get_tree().physics_frame
	return -1 if not done.call() else limit


func _senses(character: AiCharacter) -> AiSenses:
	return character.senses as AiSenses


func test_the_character_scene_has_senses_in_its_slot() -> void:
	var character := _arena.add_watcher("Grunt", Vector3.ZERO, 0.0)
	var senses := _senses(character)
	assert_object(senses).is_not_null()
	assert_object(senses.eye).is_equal(character.get_node("CameraTarget"))
	assert_object(senses.view).is_not_null()
	assert_bool(senses.view.visible).is_false()


func test_a_target_behind_a_wall_with_the_character_facing_away_is_never_believed() -> void:
	var character := _arena.add_watcher("Grunt", Vector3.ZERO, 0.0)
	_arena.add_wall(-2.0, 2.0, -2.0)
	var target := _arena.add_target("Player", Vector3(0.0, 0.0, -4.0))
	var senses := _senses(character)
	await _ticks(600)
	assert_int(senses.thinks).is_greater(50)
	assert_bool(senses.beliefs.knows(target)).is_false()
	assert_int(character.situation.current).is_equal(AiSituation.Situation.UNAWARE)


func test_the_same_target_in_the_open_ahead_is_believed() -> void:
	var character := _arena.add_watcher("Grunt", Vector3.ZERO, PI)
	var target := _arena.add_target("Player", Vector3(0.0, 0.0, -4.0))
	var senses := _senses(character)
	(
		assert_int(await _until(func() -> bool: return senses.beliefs.believes(target), 180))
		. is_not_negative()
	)
	assert_int(character.situation.current).is_equal(AiSituation.Situation.ALERT)


func test_a_target_stepping_out_of_cover_is_believed_no_sooner_than_notice_and_reaction() -> void:
	var character := _arena.add_watcher("Grunt", Vector3.ZERO, PI)
	_arena.add_wall(-1.5, 1.5, -3.0)
	var target := _arena.add_target("Player", Vector3(0.0, 0.0, -6.0))
	var senses := _senses(character)
	var noticed_at := [-1.0]
	var believed_at := [-1.0]
	senses.alerted.connect(
		func(_entity: Node3D, _belief: AiBelief) -> void: noticed_at[0] = senses.beliefs.clock
	)
	senses.entity_noticed.connect(
		func(_entity: Node3D, _belief: AiBelief) -> void: believed_at[0] = senses.beliefs.clock
	)
	await _ticks(120)
	assert_bool(senses.beliefs.knows(target)).is_false()
	target.position = Vector3(4.0, 0.0, -6.0)
	(
		assert_int(await _until(func() -> bool: return senses.beliefs.believes(target), 300))
		. is_not_negative()
	)
	var belief := senses.beliefs.of(target)
	var profile := character.profile
	assert_float(belief.first_clear_at).is_greater(0.0)
	var least := profile.time_to_notice + profile.reaction_time
	assert_float(believed_at[0] - belief.first_clear_at).is_greater_equal(least - 0.001)
	# Each part on its own: the noticing takes at least `time_to_notice` of clear sight, the act
	# waits the whole reaction delay after it.
	assert_float(noticed_at[0] - belief.first_clear_at).is_greater_equal(
		profile.time_to_notice - 0.001
	)
	assert_float(believed_at[0] - noticed_at[0]).is_greater_equal(profile.reaction_time - 0.001)


func test_a_hit_from_behind_is_believed_at_once() -> void:
	var character := _arena.add_watcher("Grunt", Vector3.ZERO, 0.0)
	var attacker := _arena.add_target("Player", Vector3(0.0, 0.0, -3.0))
	var senses := _senses(character)
	await _ticks(30)
	assert_bool(senses.beliefs.knows(attacker)).is_false()
	character.hit(1.0, attacker)
	assert_bool(senses.beliefs.believes(attacker)).is_true()
	assert_int(senses.beliefs.of(attacker).source).is_equal(AiBelief.Source.TOUCHED)
	assert_int(character.situation.current).is_equal(AiSituation.Situation.ALERT)


func test_an_attacker_that_leaves_the_view_while_hitting_stays_believed() -> void:
	var character := _arena.add_watcher("Grunt", Vector3.ZERO, PI)
	var attacker := _arena.add_target("Player", Vector3(0.0, 0.0, -5.0))
	var senses := _senses(character)
	(
		assert_int(await _until(func() -> bool: return senses.beliefs.believes(attacker), 180))
		. is_not_negative()
	)
	attacker.position = Vector3(0.0, 0.0, 3.0)
	for blow in 6:
		character.hit(0.5, attacker)
		for _tick in 30:
			await get_tree().physics_frame
			assert_bool(senses.beliefs.believes(attacker)).is_true()
	var belief := senses.beliefs.of(attacker)
	assert_bool(belief.seen_now).is_false()
	assert_float(belief.last_position.z).is_equal_approx(3.0, 0.01)


func test_a_thing_within_the_near_radius_is_noticed_whichever_way_it_faces() -> void:
	var pairs: Array = []
	var index := 0
	for heading in [0.0, PI * 0.5, PI, -PI * 0.5]:
		var spot := Vector3(-15.0 + index * 10.0, 0.0, 0.0)
		var character := _arena.add_watcher("Grunt%d" % index, spot, heading)
		var target := _arena.add_target("Swinger%d" % index, spot + Vector3(0.0, 0.0, -1.5))
		pairs.append([character, target])
		index += 1
	var all_believe := func() -> bool:
		for pair: Array in pairs:
			if not _senses(pair[0]).beliefs.believes(pair[1]):
				return false
		return true
	assert_int(await _until(all_believe, 60)).is_not_negative()


func test_a_memory_expires_and_is_never_a_fire_target() -> void:
	var profile := (load(GRUNT) as AiProfile).duplicate()
	profile.memory_seconds = 2.0
	var character := _arena.add_watcher("Grunt", Vector3.ZERO, PI, profile)
	_arena.add_wall(-1.5, 1.5, -3.0)
	var target := _arena.add_target("Player", Vector3(4.5, 0.0, -6.0))
	var senses := _senses(character)
	var lost := [0]
	senses.entity_lost.connect(func(_id: int, _belief: AiBelief) -> void: lost[0] += 1)
	(
		assert_int(await _until(func() -> bool: return senses.beliefs.believes(target), 180))
		. is_not_negative()
	)
	assert_object(senses.beliefs.fire_target(character.global_position)).is_not_null()
	target.position = Vector3(0.0, 0.0, -6.0)
	await _ticks(30)
	var belief := senses.beliefs.of(target)
	assert_bool(belief.seen_now).is_false()
	assert_bool(belief.believed).is_true()
	assert_object(senses.beliefs.fire_target(character.global_position)).is_null()
	assert_object(senses.beliefs.search_target()).is_same(belief)
	assert_float(belief.last_position.x).is_equal_approx(4.5, 0.01)
	await _ticks(150)
	assert_bool(senses.beliefs.knows(target)).is_false()
	assert_int(lost[0]).is_equal(1)


func test_a_friend_in_plain_view_is_not_perceived() -> void:
	var character := _arena.add_watcher("Grunt", Vector3.ZERO, PI)
	var friend := _arena.add_target("Friend", Vector3(0.0, 0.0, -4.0), &"enemy")
	var senses := _senses(character)
	await _ticks(120)
	assert_bool(senses.beliefs.knows(friend)).is_false()
	assert_int(senses.rays_cast).is_equal(0)


func test_an_unfriendly_thing_is_noticed_slower_than_a_hostile_one() -> void:
	var hostile := _arena.add_watcher("Grunt", Vector3(-10.0, 0.0, 0.0), PI)
	var civil := _arena.add_watcher("Other", Vector3(10.0, 0.0, 0.0), PI)
	var player := _arena.add_target("Player", Vector3(-10.0, 0.0, -8.0))
	var civilian := _arena.add_target("Civilian", Vector3(10.0, 0.0, -8.0), &"civilian")
	var to_player := _senses(hostile).sight_rate(player, 8.0, 0.0, AiRelations.Band.HOSTILE)
	var to_civilian := _senses(civil).sight_rate(civilian, 8.0, 0.0, AiRelations.Band.UNFRIENDLY)
	assert_float(to_civilian).is_equal_approx(to_player * _senses(civil).unfriendly_share, 0.0001)
	(
		assert_int(
			await _until(func() -> bool: return _senses(hostile).beliefs.believes(player), 240)
		)
		. is_not_negative()
	)
	assert_bool(_senses(civil).beliefs.believes(civilian)).is_false()


func test_a_dormant_character_does_not_look() -> void:
	var far := (load(GRUNT) as AiProfile).duplicate()
	far.full_range = 0.0
	far.reduced_range = 0.0
	far.tier_margin = 0.0
	far.dormant_think_rate = 10.0
	_arena.viewer.position = Vector3(0.0, 0.0, 50.0)
	var character := _arena.add_watcher("Grunt", Vector3(0.0, 0.0, 0.0), PI, far)
	var target := _arena.add_target("Player", Vector3(0.0, 0.0, -4.0))
	var senses := _senses(character)
	await _ticks(120)
	assert_int(character.tier).is_equal(AiDirector.Tier.DORMANT)
	assert_int(senses.thinks).is_greater(5)
	assert_int(senses.rays_cast).is_equal(0)
	assert_bool(senses.beliefs.knows(target)).is_false()


func test_a_client_of_a_remote_server_senses_nothing() -> void:
	AiNoise._runs_here = 0
	var character := _arena.add_watcher("Grunt", Vector3.ZERO, PI)
	var target := _arena.add_target("Player", Vector3(0.0, 0.0, -4.0))
	var senses := _senses(character)
	await _ticks(120)
	character.hit(1.0, target)
	assert_int(senses.rays_cast).is_equal(0)
	assert_bool(senses.beliefs.knows(target)).is_false()
	assert_bool(AiNoise.emit(_arena, AiNoise.SHOT, Vector3.ZERO)).is_false()


func test_the_view_draws_when_shown_and_costs_nothing_hidden() -> void:
	var character := _arena.add_watcher("Grunt", Vector3.ZERO, PI)
	var target := _arena.add_target("Player", Vector3(0.0, 0.0, -4.0))
	var senses := _senses(character)
	await _until(func() -> bool: return senses.beliefs.knows(target), 120)
	var mesh := senses.view.mesh as ImmediateMesh
	assert_bool(senses.view.is_processing()).is_false()
	assert_int(mesh.get_surface_count()).is_equal(0)
	senses.show_view = true
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(senses.view.visible).is_true()
	assert_int(mesh.get_surface_count()).is_equal(1)
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_int(vertices.size()).is_greater(100)


func test_the_same_start_gives_the_same_beliefs() -> void:
	var first: PackedStringArray = await _run_scene()
	_arena.free()
	_arena = auto_free(SensesArena.new())
	add_child(_arena)
	_arena.add_director()
	var second: PackedStringArray = await _run_scene()
	assert_int(first.size()).is_greater(1)
	assert_array(Array(second)).is_equal(Array(first))


# Two grunts, a target that walks past a wall and shoots, a noise: the beliefs at the end.
func _run_scene() -> PackedStringArray:
	# Both runs start in the same phase of a frame, so the target moves on the same ticks.
	await get_tree().process_frame
	var watcher := _arena.add_watcher("Watcher", Vector3.ZERO, PI)
	_arena.add_watcher("Mate", Vector3(3.0, 0.0, 1.0), 0.0)
	_arena.add_wall(-1.5, 1.5, -3.0)
	var target := _arena.add_target("Player", Vector3(-4.0, 0.0, -7.0))
	for tick in 240:
		target.position.x = -4.0 + tick * 0.035
		if tick == 100:
			AiNoise.emit(_arena, AiNoise.SHOT, target.position, 1.0, target)
		await get_tree().physics_frame
	var lines := PackedStringArray()
	for character in [watcher, _arena.get_node("Mate")]:
		for line in _senses(character).beliefs.describe():
			lines.append("%s: %s" % [character.name, line])
	return lines

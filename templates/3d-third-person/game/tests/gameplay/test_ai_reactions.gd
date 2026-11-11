# The reactions of the shipped kinds on their real bodies (kit #968, after Deadnight's bot faults,
# `docs/gamedev/bots.md`): notice, chase, lose, search and back to the patrol; an ally helps its
# player; a civilian flees by courage and cowers when hurt; a Careful guard takes cover and peeks;
# a Safe one does not roam; a melee swing lands on a target 1.4 m away; no shot at a memory or
# through a friend; a repeated sighting does not stack tasks; a script's order beats the routine
# but not a reaction. Noises, blocks, barks, the aim's floor, a reload, the overlay and a remote
# client are `test_ai_reaction_rules.gd`; the tables (a dry gun, no idle with a threat)
# `test_ai_reaction_tables.gd`.
extends GdUnitTestSuite

var _arena: BehaviourArena


func before_test() -> void:
	_arena = auto_free(BehaviourArena.new())
	add_child(_arena)
	_arena.add_director()


func after_test() -> void:
	AudioDrain.stop_all(_arena)
	AiNoise._runs_here = -1


func _ready_arena() -> void:
	_arena.build()
	assert_bool(await _arena.settle()).override_failure_message("the map never answered").is_true()


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


func _active_is(character: AiCharacter, wanted: StringName) -> Callable:
	return func() -> bool: return BehaviourArena.active_of(character) == wanted


func _set_health(character: AiCharacter, share: float) -> void:
	var health := Health.of(character)
	health.value = health.max_value * share


func _patrol_markers() -> void:
	_arena.add_marker(AiMarker.Kind.PATROL, Vector3(-8, 0, -8), &"")
	_arena.add_marker(AiMarker.Kind.PATROL, Vector3(8, 0, -8), &"")


func test_a_guard_notices_chases_loses_searches_and_goes_back_to_its_patrol() -> void:
	_patrol_markers()
	await _ready_arena()
	var guard := _arena.add_kind(BehaviourArena.GUARD, Vector3(-8, 0, -8), 0.0)
	var seen: Array[StringName] = []
	BehaviourArena.runner_of(guard).task_started.connect(
		func(task: AiTask) -> void: seen.append(task.id)
	)
	assert_int(await _until(_active_is(guard, &"patrol"), 60)).is_not_negative()
	var player := _arena.add_target("Player", Vector3(0, 0, 40))
	# In plain view ahead of wherever the patrol has turned it.
	var ahead := Vector3.BACK.rotated(Vector3.UP, guard.facing) * 7.0
	player.global_position = guard.global_position + ahead
	assert_int(await _until(_active_is(guard, &"engage"), 240)).is_not_negative()
	assert_int(guard.situation.current).is_equal(AiSituation.Situation.ENGAGED)
	# It slips away out of sight.
	player.global_position = Vector3(0, 0, 60)
	assert_int(await _until(_active_is(guard, &"chase"), 240)).is_not_negative()
	assert_int(await _until(_active_is(guard, &"search"), 900)).is_not_negative()
	assert_int(await _until(_active_is(guard, &"patrol"), 1800)).is_not_negative()
	var order := [&"patrol", &"engage", &"chase", &"search"]
	var at := 0
	for id in seen:
		if at < order.size() and id == order[at]:
			at += 1
	assert_int(at).override_failure_message("tasks started: %s" % [seen]).is_equal(order.size())


func test_an_ally_follows_its_player_and_fights_an_enemy_that_appears() -> void:
	await _ready_arena()
	var player := _arena.add_target("Player", Vector3(0, 0, -6))
	var ally := _arena.add_kind(BehaviourArena.ALLY, Vector3(0, 0, 0), PI)
	BehaviourArena.brain_of(ally).leader = player
	assert_int(await _until(_active_is(ally, &"follow"), 60)).is_not_negative()
	# Off to the side: the player stands between them on the straight line (no shot through it).
	var enemy := _arena.add_target("Enemy", Vector3(5, 0, -11), &"enemy")
	assert_int(await _until(_active_is(ally, &"engage"), 240)).is_not_negative()
	var attack := BehaviourArena.runner_of(ally).active as AiAttack
	assert_object(attack.target).is_equal(enemy)
	assert_int(await _until(func() -> bool: return attack.gun.shots > 0, 240)).is_not_negative()


func test_a_civilian_flees_by_courage_and_one_with_none_cowers() -> void:
	await _ready_arena()
	var runner_civ := _arena.add_kind(
		BehaviourArena.CIVILIAN, Vector3(-6, 0, 0), 0.0, {"courage": 0.1}
	)
	var timid := _arena.add_kind(BehaviourArena.CIVILIAN, Vector3(6, 0, 0), 0.0, {"courage": 0.0})
	var barks: Array[StringName] = []
	BehaviourArena.brain_of(runner_civ).barked.connect(
		func(line: StringName) -> void: barks.append(line)
	)
	# Within arm's reach: noticed whichever way the stroll turned them.
	_arena.add_target("GruntA", Vector3(-6, 0, 1.8), &"enemy")
	_arena.add_target("GruntB", Vector3(6, 0, 1.8), &"enemy")
	assert_int(await _until(_active_is(runner_civ, &"flee"), 300)).is_not_negative()
	assert_int(await _until(_active_is(timid, &"cower"), 300)).is_not_negative()
	assert_int(runner_civ.situation.current).is_equal(AiSituation.Situation.FLEEING)
	await _ticks(120)
	assert_float(runner_civ.global_position.distance_to(Vector3(-6, 0, 1.8))).is_greater(6.0)
	assert_bool(timid.ai_controller().crouch).is_true()
	assert_float(timid.global_position.distance_to(Vector3(6, 0, 0))).is_less(0.5)
	assert_array(barks).contains([&"help"])


func test_a_hurt_civilian_cowers_and_a_brave_one_flees() -> void:
	await _ready_arena()
	var hurt := _arena.add_kind(BehaviourArena.CIVILIAN, Vector3(-6, 0, 0), 0.0, {"courage": 0.9})
	var brave := _arena.add_kind(BehaviourArena.CIVILIAN, Vector3(6, 0, 0), 0.0, {"courage": 0.9})
	_set_health(hurt, 0.2)
	_arena.add_target("GruntA", Vector3(-6, 0, 1.8), &"enemy")
	_arena.add_target("GruntB", Vector3(6, 0, 1.8), &"enemy")
	assert_int(await _until(_active_is(hurt, &"cower"), 300)).is_not_negative()
	assert_int(await _until(_active_is(brave, &"flee"), 300)).is_not_negative()
	assert_int(BehaviourArena.brain_of(hurt).play.current).is_equal(AiPlayState.State.SAFE)


func test_a_careful_guard_takes_cover_and_peeks_to_shoot() -> void:
	await _ready_arena()
	# The spot faces the threat (its -Z toward +Z: turned half round).
	_arena.add_marker(AiMarker.Kind.COVER, Vector3(3, 0, 1), &"", PI)
	var guard := _arena.add_kind(BehaviourArena.GUARD, Vector3(0, 0, 0), 0.0)
	_set_health(guard, 0.45)
	_arena.add_target("Player", Vector3(0, 0, 10))
	assert_int(await _until(_active_is(guard, &"cover"), 300)).is_not_negative()
	assert_int(BehaviourArena.brain_of(guard).play.current).is_equal(AiPlayState.State.CAREFUL)
	var cover := BehaviourArena.runner_of(guard).active as AiTakeCover
	assert_int(await _until(func() -> bool: return cover.in_cover, 300)).is_not_negative()
	assert_float(guard.global_position.distance_to(Vector3(3, 0, 1))).is_less(1.2)
	assert_int(await _until(func() -> bool: return cover.gun.shots > 0, 400)).is_not_negative()
	assert_int(cover.peeks).is_greater_equal(1)
	# Down again between peeks.
	var crouched := await _until(func() -> bool: return guard.ai_controller().crouch, 200)
	assert_int(crouched).is_not_negative()


func test_low_health_goes_safe_and_does_not_roam() -> void:
	_patrol_markers()
	await _ready_arena()
	var guard := _arena.add_kind(BehaviourArena.GUARD, Vector3(0, 0, 0), 0.0)
	_set_health(guard, 0.15)
	await _ticks(300)
	assert_int(BehaviourArena.brain_of(guard).play.current).is_equal(AiPlayState.State.SAFE)
	assert_float(guard.global_position.distance_to(Vector3.ZERO)).is_less(1.0)
	assert_str(String(BehaviourArena.active_of(guard))).is_equal("guard")
	# Healed, it turns bolder after the dwell and walks its patrol again.
	_set_health(guard, 1.0)
	assert_int(await _until(_active_is(guard, &"patrol"), 300)).is_not_negative()


func test_a_target_1_4_m_away_is_hit_by_a_melee_swing() -> void:
	await _ready_arena()
	var guard := _arena.add_kind(BehaviourArena.GUARD, Vector3(0, 0, 0), 0.0)
	guard.loadout.toggle_unarmed()
	await _ticks(30)
	assert_int(guard.weapon.definition.kind).is_equal(WeaponDef.Kind.MELEE)
	var victim := _arena.add_dummy(Vector3(0, 0, 1.4), &"player", PI)
	var full := victim.health
	var hit := await _until(func() -> bool: return victim.health < full, 240)
	assert_int(hit).override_failure_message("no blow landed").is_not_negative()
	var attack := BehaviourArena.runner_of(guard).active as AiAttack
	assert_int(attack.swings).is_greater_equal(1)


func test_no_shot_is_fired_at_a_remembered_entity() -> void:
	_arena.add_wall(Rect2i(-6, 5, 7, 2))
	await _ready_arena()
	var guard := _arena.add_kind(BehaviourArena.GUARD, Vector3(0, 0, 0), 0.0)
	var player := _arena.add_target("Player", Vector3(4, 0, 9))
	assert_int(await _until(_active_is(guard, &"engage"), 240)).is_not_negative()
	var attack := BehaviourArena.runner_of(guard).active as AiAttack
	assert_int(await _until(func() -> bool: return attack.gun.shots > 0, 240)).is_not_negative()
	# Behind the wall now: remembered, believed, never fired at.
	player.global_position = Vector3(-2, 0, 9)
	var senses := guard.senses as AiSenses
	var wrong := 0
	for _tick in 150:
		await get_tree().physics_frame
		var belief := senses.beliefs.of(player)
		if guard.ai_controller().fire and (belief == null or not belief.seen_now):
			wrong += 1
	assert_int(wrong).is_equal(0)
	assert_bool(senses.beliefs.believes(player)).is_true()


func test_no_shot_is_fired_through_a_friend() -> void:
	await _ready_arena()
	var guard := _arena.add_kind(BehaviourArena.GUARD, Vector3(0, 0, 0), 0.0)
	var friend := _arena.add_dummy(Vector3(0, 0, 5), &"enemy", PI)
	_arena.add_target("Player", Vector3(0, 0, 10))
	assert_int(await _until(_active_is(guard, &"engage"), 240)).is_not_negative()
	var attack := BehaviourArena.runner_of(guard).active as AiAttack
	await _ticks(120)
	assert_int(attack.gun.shots).is_equal(0)
	assert_str(attack.gun.held_by).is_equal("friend in the way")
	friend.teleport(Vector3(4, 0, 5), PI)
	assert_int(await _until(func() -> bool: return attack.gun.shots > 0, 180)).is_not_negative()


func test_a_repeated_sighting_does_not_stack_tasks() -> void:
	await _ready_arena()
	var guard := _arena.add_kind(BehaviourArena.GUARD, Vector3(0, 0, 0), 0.0)
	var player := _arena.add_target("Player", Vector3(0, 0, 8))
	assert_int(await _until(_active_is(guard, &"engage"), 240)).is_not_negative()
	var runner := BehaviourArena.runner_of(guard)
	var before_count := runner.count()
	for _i in 50:
		BehaviourArena.brain_of(guard).route(AiBehaviourSet.NOTICED, player, player.global_position)
		await get_tree().physics_frame
	assert_int(runner.count()).is_equal(before_count)
	assert_int(runner.queued(AiTask.Layer.RESPONSE).size()).is_equal(1)


func test_a_script_order_beats_the_routine_but_not_a_reaction() -> void:
	_patrol_markers()
	await _ready_arena()
	var guard := _arena.add_kind(BehaviourArena.GUARD, Vector3(0, 0, 0), 0.0)
	assert_int(await _until(_active_is(guard, &"patrol"), 60)).is_not_negative()
	var order := BehaviourArena.brain_of(guard).order(AiBehaviourSet.ORDER_HOLD, Vector3(4, 0, 4))
	assert_object(order).is_not_null()
	assert_int(await _until(_active_is(guard, &"guard"), 30)).is_not_negative()
	assert_int(BehaviourArena.runner_of(guard).active.layer).is_equal(AiTask.Layer.ORDER)
	var attacker := _arena.add_target("Player", Vector3(0, 0, -6))
	guard.hit(1.0, attacker)
	assert_int(await _until(_active_is(guard, &"engage"), 30)).is_not_negative()
	assert_int(BehaviourArena.runner_of(guard).active.layer).is_equal(AiTask.Layer.RESPONSE)
	# The order waits under it, not dropped.
	assert_int(BehaviourArena.runner_of(guard).queued(AiTask.Layer.ORDER).size()).is_equal(1)


func test_a_hit_from_behind_turns_a_guard_to_fight() -> void:
	await _ready_arena()
	var guard := _arena.add_kind(BehaviourArena.GUARD, Vector3(0, 0, 0), 0.0)
	var attacker := _arena.add_target("Player", Vector3(0, 0, -6))
	await _ticks(20)
	guard.hit(1.0, attacker)
	assert_int(await _until(_active_is(guard, &"engage"), 20)).is_not_negative()
	assert_int(guard.situation.current).is_equal(AiSituation.Situation.ENGAGED)


func test_an_ally_hit_by_its_player_complains_and_never_fights() -> void:
	await _ready_arena()
	var player := _arena.add_target("Player", Vector3(0, 0, -4))
	var ally := _arena.add_kind(BehaviourArena.ALLY, Vector3(0, 0, 0), PI)
	BehaviourArena.brain_of(ally).leader = player
	var barks: Array[StringName] = []
	BehaviourArena.brain_of(ally).barked.connect(func(line: StringName) -> void: barks.append(line))
	var started: Array[StringName] = []
	BehaviourArena.runner_of(ally).task_started.connect(
		func(task: AiTask) -> void: started.append(task.id)
	)
	await _ticks(30)
	ally.hit(1.0, player)
	await _ticks(90)
	assert_array(barks).contains([&"watch_it"])
	assert_array(started).contains([&"look"])
	assert_array(started).not_contains([&"engage"])

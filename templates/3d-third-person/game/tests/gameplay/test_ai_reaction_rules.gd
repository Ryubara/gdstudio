# The rules around the reactions (kit #968): a curious guard goes to a noise and a dull one looks,
# a newer noise moves the investigation, an Engaged guard ignores a noise, barks wait their
# cooldowns, the aim waits the reaction floor and turns no faster than `aim_speed`, a dry magazine
# is reloaded, the overlay shows the play state and the task, a client of a remote server routes
# nothing, and the three scored choices (patrol stop, cover spot, target) keep what they chose.
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


func test_a_curious_guard_goes_to_a_noise_and_an_incurious_one_looks() -> void:
	await _ready_arena()
	# Far enough apart that neither hears the other's noise.
	var curious := _arena.add_kind(
		BehaviourArena.GUARD, Vector3(-12, 0, 0), 0.0, {"curiosity": 1.0}
	)
	var dull := _arena.add_kind(BehaviourArena.GUARD, Vector3(12, 0, 0), 0.0, {"curiosity": 0.0})
	await _ticks(20)
	AiNoise.emit(_arena, &"impact", Vector3(-12, 0, -6))
	AiNoise.emit(_arena, &"impact", Vector3(12, 0, -6))
	assert_int(await _until(_active_is(curious, &"investigate"), 60)).is_not_negative()
	assert_int(await _until(_active_is(dull, &"look_at"), 60)).is_not_negative()
	var near := func() -> bool:
		return curious.global_position.distance_to(Vector3(-12, 0, -6)) < 2.0
	assert_int(await _until(near, 420)).is_not_negative()
	assert_float(dull.global_position.distance_to(Vector3(12, 0, 0))).is_less(0.5)


func test_a_newer_noise_sends_an_investigation_to_the_new_place() -> void:
	await _ready_arena()
	var guard := _arena.add_kind(BehaviourArena.GUARD, Vector3(0, 0, 0), 0.0, {"curiosity": 1.0})
	await _ticks(20)
	AiNoise.emit(_arena, &"impact", Vector3(-6, 0, -6))
	assert_int(await _until(_active_is(guard, &"investigate"), 60)).is_not_negative()
	await _ticks(60)
	AiNoise.emit(_arena, &"impact", Vector3(6, 0, 6))
	var near := func() -> bool: return guard.global_position.distance_to(Vector3(6, 0, 6)) < 2.0
	assert_int(await _until(near, 600)).is_not_negative()


func test_an_engaged_guard_does_not_turn_for_a_noise() -> void:
	await _ready_arena()
	var guard := _arena.add_kind(BehaviourArena.GUARD, Vector3(0, 0, 0), 0.0, {"curiosity": 1.0})
	_arena.add_target("Player", Vector3(0, 0, 8))
	assert_int(await _until(_active_is(guard, &"engage"), 240)).is_not_negative()
	AiNoise.emit(_arena, &"impact", Vector3(0, 0, -5))
	await _ticks(20)
	assert_str(BehaviourArena.brain_of(guard).last_answer).is_equal("blocked")
	assert_str(String(BehaviourArena.active_of(guard))).is_equal("engage")


func test_barks_wait_their_cooldowns() -> void:
	await _ready_arena()
	var one := _arena.add_kind(BehaviourArena.GUARD, Vector3(-4, 0, 0), 0.0)
	var two := _arena.add_kind(BehaviourArena.GUARD, Vector3(4, 0, 0), 0.0)
	var brain := BehaviourArena.brain_of(one)
	await _ticks(2)
	assert_bool(brain.say(&"contact")).is_true()
	assert_bool(brain.say(&"contact")).is_false()
	assert_bool(brain.say(&"other")).is_false()
	assert_bool(BehaviourArena.brain_of(two).say(&"contact")).is_false()
	await _ticks(int((brain.any_line_cooldown + 0.1) * 60.0))
	assert_bool(brain.say(&"other")).is_true()
	assert_bool(BehaviourArena.brain_of(two).say(&"contact")).is_true()


func test_the_aim_waits_the_reaction_floor_and_turns_no_faster_than_aim_speed() -> void:
	await _ready_arena()
	var guard := _arena.add_kind(BehaviourArena.GUARD, Vector3(0, 0, 0), 0.0)
	_arena.add_target("Player", Vector3(0, 0, 9))
	assert_int(await _until(_active_is(guard, &"engage"), 240)).is_not_negative()
	var attack := BehaviourArena.runner_of(guard).active as AiAttack
	var first := [-1.0]
	var probe := func() -> bool:
		if attack.gun.shots > 0 and first[0] < 0.0:
			first[0] = attack.gun.on_this
		return first[0] >= 0.0
	assert_int(await _until(probe, 240)).is_not_negative()
	assert_float(first[0]).is_greater_equal(AiProfile.REACTION_FLOOR - 0.001)
	# The turn: 90 degrees at 360 a second take a quarter of a second.
	var limit := deg_to_rad(36.0)
	var turned := AiAim._turn(Vector3.BACK, Vector3.RIGHT, limit)
	assert_float(rad_to_deg(Vector3.BACK.angle_to(turned))).is_equal_approx(36.0, 0.01)


func test_a_dry_magazine_with_rounds_in_reserve_is_reloaded() -> void:
	await _ready_arena()
	var guard := _arena.add_kind(BehaviourArena.GUARD, Vector3(0, 0, 0), 0.0)
	guard.weapon.set_ammo(0, 12)
	_arena.add_target("Player", Vector3(0, 0, 9))
	assert_int(await _until(_active_is(guard, &"engage"), 240)).is_not_negative()
	(
		assert_int(await _until(func() -> bool: return guard.weapon.is_reloading(), 120))
		. is_not_negative()
	)
	var attack := BehaviourArena.runner_of(guard).active as AiAttack
	assert_int(await _until(func() -> bool: return attack.gun.shots > 0, 300)).is_not_negative()


func test_the_overlay_shows_the_play_state_the_answer_and_the_task() -> void:
	await _ready_arena()
	var guard := _arena.add_kind(BehaviourArena.GUARD, Vector3(0, 0, 0), 0.0)
	guard.debug = true
	_arena.add_target("Player", Vector3(0, 0, 8))
	assert_int(await _until(_active_is(guard, &"engage"), 240)).is_not_negative()
	await _ticks(12)
	assert_str(guard.debug_label.text).contains("Aggressive")
	assert_str(guard.debug_label.text).contains("noticed: engage")
	var label := guard.get_node("TaskLabel") as Label3D
	assert_str(label.text).contains("> Response: engage")


func test_a_client_of_a_remote_server_routes_nothing() -> void:
	AiNoise._runs_here = 0
	_patrol_markers()
	await _ready_arena()
	var guard := _arena.add_kind(BehaviourArena.GUARD, Vector3(0, 0, 0), 0.0)
	_arena.add_target("Player", Vector3(0, 0, 8))
	await _ticks(120)
	assert_int(BehaviourArena.brain_of(guard).routed).is_equal(0)
	assert_int(BehaviourArena.runner_of(guard).count()).is_equal(0)


func test_the_patrol_visits_every_stop_before_it_repeats_one() -> void:
	_arena.add_marker(AiMarker.Kind.PATROL, Vector3(-8, 0, -8), &"", 0.0, 0.2)
	_arena.add_marker(AiMarker.Kind.PATROL, Vector3(8, 0, -8), &"", 0.0, 0.2)
	_arena.add_marker(AiMarker.Kind.PATROL, Vector3(0, 0, 8), &"", 0.0, 0.2)
	await _ready_arena()
	var guard := _arena.add_kind(BehaviourArena.GUARD, Vector3(-8, 0, -8), 0.0)
	assert_int(await _until(_active_is(guard, &"patrol"), 60)).is_not_negative()
	var patrol := BehaviourArena.runner_of(guard).active as AiPatrol
	var order: Array[String] = []
	for _tick in 1500:
		await get_tree().physics_frame
		if patrol.next != null and (order.is_empty() or order[-1] != String(patrol.next.name)):
			order.append(String(patrol.next.name))
		if order.size() >= 4:
			break
	assert_int(order.size()).is_greater_equal(3)
	var first_three := {order[0]: true, order[1]: true, order[2]: true}
	assert_int(first_three.size()).override_failure_message(str(order)).is_equal(3)


func test_the_choices_keep_what_they_chose_unless_another_is_clearly_better() -> void:
	var ids := [1, 2]
	assert_int(AiChoice.best(ids, PackedFloat32Array([0.5, 0.6]), 1, 0.3)).is_equal(0)
	assert_int(AiChoice.best(ids, PackedFloat32Array([0.5, 0.9]), 1, 0.3)).is_equal(1)
	assert_int(AiChoice.best(ids, PackedFloat32Array([0.5, 0.6]), null, 0.3)).is_equal(1)
	assert_int(AiChoice.best([], PackedFloat32Array(), null, 0.3)).is_equal(-1)


func test_the_cover_choice_prefers_a_spot_facing_the_threat_and_keeps_it() -> void:
	var away := _arena.add_marker(AiMarker.Kind.COVER, Vector3(-3, 0, 0), &"", 0.0)
	var facing := _arena.add_marker(AiMarker.Kind.COVER, Vector3(3, 0, 0), &"", PI)
	await _ready_arena()
	var guard := _arena.add_kind(BehaviourArena.GUARD, Vector3(0, 0, -1), 0.0)
	BehaviourArena.brain_of(guard).behaviour = null
	var cover := AiTakeCover.new()
	cover.bind(BehaviourArena.runner_of(guard), guard, guard.ai_controller())
	cover.goal = Vector3(0, 0, 10)
	assert_object(cover.choose_spot()).is_equal(facing)
	cover.spot = facing
	# The threat moves so that both face it as well as each other: the kept one stays.
	away.rotation.y = PI
	assert_object(cover.choose_spot()).is_equal(facing)

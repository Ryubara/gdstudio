# The AI in an online game (gdstudio #970): a game server and predicting clients, each with a map of
# its own, over a real socket on 127.0.0.1 (`OnlineRig`). The AI runs on the server only: a client's
# own AI stands down when it joins and processes nothing; the server's characters are drawn on
# every client from the TICK's AI block, where the server has them; a late joiner gets the whole
# population in its first snapshot; a character the server kills falls into its ragdoll on another
# client from one event; a player's shot on an AI is a HIT on its puppet; a browser in the match
# caps the population for everyone.
extends GdUnitTestSuite

const COUNTING_AI := "res://tests/fixtures/counting_ai.tscn"
## Open ground west of the push cubes (`test_net_props.gd`'s crate spot), facing north.
const GROUND := Vector3(-9.0, 0.3, 19.0)
const FACING_NORTH := PI
## How far Bo's puppet may be from where the server had the character one send before the tick
## drawn, while it walks (a send's walk at the run speed and a tick of the clock's pull).
const MAX_WALK_GAP := 0.3
const MAX_REST_GAP := 0.02

var _rig: OnlineRig
var _ada: NetClient
var _bo: NetClient


func after_test() -> void:
	_rig = null
	_ada = null
	_bo = null


func test_a_client_runs_no_ai_and_its_map_keeps_none() -> void:
	var counted := CountingAi.new_counts()
	_rig = auto_free(OnlineRig.new(false))
	_rig.prepare_arena = func(arena: Node) -> void:
		var guard := (load(COUNTING_AI) as PackedScene).instantiate() as AiCharacter
		guard.position = GROUND
		arena.get_node("World").add_child(guard)
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_ada = await _rig.join("Ada", 600)
	assert_object(_ada).is_not_null()
	await _rig.wait(60)
	var counts := CountingAi.new_counts()
	assert_int(counts.physics - counted.physics).is_equal(0)
	assert_int(counts.process - counted.process).is_equal(0)
	assert_int(counts.thinks - counted.thinks).is_equal(0)
	# Nothing of the AI is left in the client's map: no director, character, senses, brain,
	# tasks or navigator.
	for node in _rig.views[0].find_children("*", "", true, false):
		var ai_part := (
			node is AiDirector
			or node is AiCharacter
			or node is AiSenses
			or node is AiBrain
			or node is AiTasks
			or node is AiNavigator
		)
		assert_bool(ai_part).override_failure_message(str(node.get_path())).is_false()
	# The same scene in the server's map runs its AI: its director steps it and it thinks.
	var served := (load(COUNTING_AI) as PackedScene).instantiate() as AiCharacter
	served.position = GROUND
	AiNetStage.server_map(_rig.server).add_child(served)
	await _rig.wait(60)
	assert_int(CountingAi.new_counts().thinks - counts.thinks).is_greater(0)
	assert_object(served.director).is_not_null()


func test_a_walking_character_is_drawn_on_bos_screen_where_the_server_has_it() -> void:
	await _start()
	var walker := AiNetStage.walker(GROUND + Vector3(-3.0, 0.0, 0.0), Vector3.RIGHT, 0.6)
	AiNetStage.server_map(_rig.server).add_child(walker)
	var seen := {}
	var worst := 0.0
	var compared := 0
	for _frame in 150:
		await get_tree().physics_frame
		seen[_rig.server.server_tick] = walker.global_position
		var puppet := _bo.ai_replica.puppet_of(_id_of(walker))
		if puppet == null or not puppet.visible:
			continue
		var drawn := roundi(_bo.ai_replica.drawn_time() * NetLimits.TICK_RATE)
		var then: Variant = seen.get(drawn - NetServer.SEND_EVERY)
		if then == null:
			continue
		worst = maxf(worst, _flat(puppet.global_position - (then as Vector3)))
		compared += 1
	AiNetStage.walk(walker, Vector3.ZERO)
	var puppet := _bo.ai_replica.puppet_of(_id_of(walker))
	await _rig.wait(40)
	var rest := puppet.global_position.distance_to(walker.global_position)
	print(
		(
			"ai online: walking gap worst %.3f m over %d frames, at rest %.4f m"
			% [worst, compared, rest]
		)
	)
	assert_int(compared).is_greater(60)
	assert_float(worst).is_less(MAX_WALK_GAP)
	assert_float(rest).is_less(MAX_REST_GAP)
	assert_float(walker.global_position.x - GROUND.x).is_greater(1.0)
	# Bo's puppet is the character's model, and nothing of the AI.
	assert_object(puppet.model).is_not_null()
	assert_bool(puppet is AiCharacter).is_false()


func test_a_late_joiner_receives_the_whole_population_in_one_snapshot() -> void:
	await _start()
	for index in 40:
		var spot := GROUND + Vector3(-6.0 + (index % 10) * 1.2, 0.0, -2.0 - (index / 10) * 1.2)
		AiNetStage.server_map(_rig.server).add_child(AiNetStage.walker(spot))
	# Cy's body starts at a spawn point far from them: an interest radius that holds the map.
	var rates := AiTierRates.new()
	rates.interest_radius = 1000.0
	_rig.server.ai.rates = rates
	await _rig.wait(10)
	var cy := await _rig.join("Cy", 600)
	assert_object(cy).is_not_null()
	assert_bool(await _rig.until(func() -> bool: return cy.ticks_read > 0, 30)).is_true()
	assert_int(cy.ai_replica.snapshot.applied).is_equal(1)
	assert_int(cy.ai_replica.snapshot.rows.size()).is_equal(40)
	# Its puppets are made a few a frame (gdstudio #1208), within the frames the budget needs.
	var frames := ceili(40.0 / cy.ai_replica.puppets_per_frame) + 2
	(
		assert_bool(await _rig.until(func() -> bool: return cy.ai_replica.count() == 40, frames))
		. is_true()
	)
	assert_int(cy.ai_replica.most_made).is_less_equal(cy.ai_replica.puppets_per_frame)


func test_a_killed_character_plays_its_ragdoll_on_bos_screen_from_one_event() -> void:
	await _start()
	var walker := AiNetStage.walker(GROUND + Vector3(0.0, 0.0, -3.0))
	AiNetStage.server_map(_rig.server).add_child(walker)
	var id := await _held_by_bo(walker)
	var events: Array[NetEvent] = []
	_bo.ai_replica.event_played.connect(
		func(event: NetEvent, _puppet: Character) -> void: events.append(event)
	)
	walker.die()
	var puppet := _bo.ai_replica.puppet_of(id)
	assert_bool(await _rig.until(puppet.is_dead, 60)).is_true()
	await _rig.wait(30)
	assert_int(events.size()).is_equal(1)
	assert_int(events[0].code).is_equal(NetEvent.AiCode.DIED)
	assert_bool(puppet.ragdoll_body != null and puppet.ragdoll_body.is_limp()).is_true()


func test_adas_shot_on_an_ai_is_a_hit_on_its_puppet_on_bos_screen() -> void:
	await _start()
	var walker := AiNetStage.walker(GROUND + Vector3(0.0, 0.0, -4.0))
	AiNetStage.server_map(_rig.server).add_child(walker)
	var id := await _held_by_bo(walker)
	var hits := [0]
	var puppet := _bo.ai_replica.puppet_of(id)
	puppet.hit_received.connect(func(_record: HitRecord) -> void: hits[0] += 1)
	var health := Health.of(walker)
	var full := health.value
	_put(_ada, GROUND, FACING_NORTH)
	await _rig.wait(20)
	var chest := walker.global_position + Vector3.UP * 1.2
	var presses: Array[int] = [_rig.controllers[0].ticks + 10]
	_rig.controllers[0].plan = func(tick: int) -> PlayerCommand:
		return _aimed(_ada.player, chest, presses.has(tick))
	assert_bool(await _rig.until(func() -> bool: return hits[0] > 0, 120)).is_true()
	assert_float(health.value).is_less(full)


func test_a_browser_in_the_match_caps_the_population_for_everyone() -> void:
	await _start()
	var director := _rig.server.ai_director()
	director.web_cap = 3
	for index in 5:
		var spot := GROUND + Vector3(-3.0 + index * 1.5, 0.0, -3.0)
		AiNetStage.server_map(_rig.server).add_child(AiNetStage.walker(spot))
	await _rig.wait(10)
	assert_int(director.count()).is_equal(5)
	# Bo plays in a browser (his HELLO said so): three for everyone.
	_rig.server.peer_at(_bo.slot).web = true
	_rig.server._cap_ai()
	assert_int(director.count()).is_equal(3)
	assert_int(director.parked_count()).is_equal(2)
	assert_bool(await _rig.until(func() -> bool: return _ada.ai_replica.count() == 3, 60)).is_true()
	assert_int(_bo.ai_replica.count()).is_equal(3)
	# He leaves: all five again.
	_rig.server.peer_at(_bo.slot).web = false
	_rig.server._cap_ai()
	assert_int(director.count()).is_equal(5)
	assert_bool(await _rig.until(func() -> bool: return _ada.ai_replica.count() == 5, 60)).is_true()


func test_a_hello_from_a_browser_says_so() -> void:
	var hello := NetWire.read_hello(NetWire.hello("Bo", 7, NetWire.F_WEB))
	assert_int(hello.flags & NetWire.F_WEB).is_equal(NetWire.F_WEB)
	assert_int(NetWire.read_hello(NetWire.hello("Bo", 7)).flags).is_equal(0)


# --- Helpers ---


func _start() -> void:
	_rig = auto_free(OnlineRig.new(false))
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_ada = await _rig.join("Ada", 600)
	_bo = await _rig.join("Bo", 600)
	assert_object(_ada).is_not_null()
	assert_object(_bo).is_not_null()
	_put(_ada, GROUND + Vector3(0.0, 0.0, 6.0), FACING_NORTH)
	_put(_bo, GROUND + Vector3(4.0, 0.0, 6.0), FACING_NORTH)
	await _rig.wait(10)


# The wire id of `walker` once Bo draws it.
func _held_by_bo(walker: AiCharacter) -> int:
	var drawn := func() -> bool:
		var puppet := _bo.ai_replica.puppet_of(_id_of(walker))
		return puppet != null and puppet.visible
	assert_bool(await _rig.until(drawn, 60)).is_true()
	return _id_of(walker)


static func _id_of(walker: AiCharacter) -> int:
	return int(walker.get_meta(NetHits.AI_META, -1))


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


static func _aimed(body: Character, point: Vector3, press: bool) -> PlayerCommand:
	var command := PlayerCommand.new()
	var eye := body.global_position + Vector3.UP * body.tuning.camera_height
	var angles := CommandCodec.direction_angles(point - eye)
	command.yaw = angles.x
	command.pitch = angles.y
	command.aim = true
	command.has_shot = true
	command.origin = eye
	command.shot_yaw = angles.x
	command.shot_pitch = angles.y
	command.fire_pressed = press
	return command


func _put(client: NetClient, spot: Vector3, facing: float) -> void:
	_rig.server_body(client).teleport(spot, facing)
	client.player.teleport(spot, facing)

# A client over a real socket joins the game server, sends a recorded stream of 120 commands, and
# the server's body ends where a body stepped offline with the same commands ends (within 1 mm):
# the server applies each command exactly once, in order, and the client's `ack` is the last
# `seq` it applied. Sent one a tick as a client sends them, and all at once as a stalled client's
# arrive (the server then applies six a step, never repeating one).
extends GdUnitTestSuite

const STREAM_LENGTH := 120

var _rig: NetServerRig
var _offline_world: SubViewport


func before_test() -> void:
	_rig = auto_free(NetServerRig.new())
	add_child(_rig)
	assert_bool(_rig.start()).is_true()


func after_test() -> void:
	if _offline_world != null:
		_offline_world.queue_free()
		_offline_world = null


# Walk, sprint while turning, jump, crouch, aim and strafe with the view turning, stop: 120 commands
# as the server reads them (`quantized`), numbered from 1.
static func recorded_stream() -> Array[PlayerCommand]:
	var stream: Array[PlayerCommand] = []
	for index in STREAM_LENGTH:
		var command := PlayerCommand.new()
		command.yaw = -0.3 + index * 0.012
		command.pitch = -0.1 + index * 0.002
		if index < 30:
			command.move = Vector2(0.0, 1.0)
			command.walk = index < 10
		elif index < 55:
			command.move = Vector2(0.3, 0.95)
			command.sprint = true
			command.jump = index >= 50
			command.jump_pressed = index == 50
		elif index < 80:
			command.move = Vector2(-0.2, 0.8)
			command.crouch = true
		elif index < 110:
			command.move = Vector2(1.0, 0.0)
			command.aim = true
		command.seq = index + 1
		stream.append(CommandCodec.quantized(command))
	return stream


func test_a_stream_sent_one_a_tick_ends_where_the_offline_body_ends() -> void:
	var client := await _rig.join("Ada")
	assert_object(client).is_not_null()
	assert_int(client.welcome.slot).is_equal(0)
	var peer := _rig.server.peer_at(0)
	var stream := recorded_stream()
	await _rig.wait(5)
	for command in stream:
		client.send_command(command.clone())
		_rig.pump()
		await get_tree().physics_frame
	assert_bool(await _rig.until(func() -> bool: return peer.ack == STREAM_LENGTH)).is_true()
	var server_end := _rig.server.body_at(0).global_position
	_assert_each_command_once(peer)
	# The server goes on stepping: replay what it had done when its body was read.
	var history := peer.history.duplicate()
	var steps := peer.history_steps.duplicate()
	var offline_end := await _replay_offline(history, steps, stream)
	(
		assert_float(server_end.distance_to(offline_end))
		. override_failure_message("server %s, offline %s" % [server_end, offline_end])
		. is_less(0.001)
	)
	# It walked: the stream is not a body standing still.
	assert_float(server_end.distance_to(_spawn_of(0).origin)).is_greater(5.0)
	var acked := await _rig.until(
		func() -> bool:
			return client.last_tick() != null and client.last_tick().ack == STREAM_LENGTH
	)
	(
		assert_bool(acked)
		. override_failure_message(
			(
				"ticks %d, last ack %d, closed %s, drops %s, lines %s"
				% [
					client.ticks.size(),
					client.last_tick().ack if client.last_tick() != null else -1,
					client.closed,
					client.drops.summary(),
					_rig.lines,
				]
			)
		)
		. is_true()
	)


func test_a_stream_sent_at_once_is_applied_six_a_step_with_no_repeat() -> void:
	var client := await _rig.join("Ada")
	var peer := _rig.server.peer_at(0)
	var stream := recorded_stream()
	await _rig.wait(5)
	for command in stream:
		client.send_command(command.clone())
	assert_bool(await _rig.until(func() -> bool: return peer.ack == STREAM_LENGTH)).is_true()
	var server_end := _rig.server.body_at(0).global_position
	_assert_each_command_once(peer)
	var first := peer.history.find(1)
	assert_bool(peer.history.slice(first).has(PeerSlot.REPEATED)).is_false()
	assert_int(Array(peer.history_steps).max()).is_equal(PeerSlot.MAX_PER_STEP)
	# The same commands stepped one a frame, after as many idle steps, end at the same place.
	var plain_steps := PackedInt32Array()
	var plain := PackedInt64Array()
	for _index in first:
		plain.append(PeerSlot.IDLE)
		plain_steps.append(1)
	for seq in range(1, STREAM_LENGTH + 1):
		plain.append(seq)
		plain_steps.append(1)
	var offline_end := await _replay_offline(plain, plain_steps, stream)
	(
		assert_float(server_end.distance_to(offline_end))
		. override_failure_message("server %s, offline %s" % [server_end, offline_end])
		. is_less(0.001)
	)


# The commands the server applied, in the order it applied them, are 1 to 120, each once.
func _assert_each_command_once(peer: PeerSlot) -> void:
	var applied: Array[int] = []
	for entry in peer.history:
		if entry > 0:
			applied.append(entry)
	var expected: Array[int] = []
	expected.assign(range(1, STREAM_LENGTH + 1))
	assert_array(applied).is_equal(expected)


func _spawn_of(slot: int) -> Transform3D:
	return _rig.server.spawn_transform(slot)


# Steps a body of its own world as the server's history says: each step of `steps` takes that many
# entries, a `seq` steps that command, `HELD` nothing, `REPEATED` the last again without its
# presses, `STOOD` a command that asks for nothing, `IDLE` the view the body started with. Answers
# where it ends.
func _replay_offline(
	history: PackedInt64Array, steps: PackedInt32Array, stream: Array[PlayerCommand]
) -> Vector3:
	_offline_world = SubViewport.new()
	_offline_world.own_world_3d = true
	_offline_world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_offline_world)
	var arena := PlayArena.new()
	_offline_world.add_child(arena)
	var body := (_rig.server.body_scene.instantiate()) as Character
	body.ragdoll_by_command = false
	arena.add_child(body)
	body.set_physics_process(false)
	var spot := _spawn_of(0)
	body.teleport(spot.origin, atan2(-spot.basis.z.x, -spot.basis.z.z))
	var last := PlayerCommand.new()
	last.yaw = body.view_yaw
	last.pitch = body.view_pitch
	var at := 0
	for count in steps:
		await get_tree().physics_frame
		for _index in count:
			var entry := history[at]
			at += 1
			if entry == PeerSlot.HELD:
				continue
			if entry > 0:
				last.copy_from(stream[entry - 1])
			elif entry == PeerSlot.REPEATED:
				last.clear_edges()
			elif entry == PeerSlot.STOOD:
				last.clear()
			body.step(last, CommandDriver.tick_seconds())
	return body.global_position


func test_a_prone_command_lays_the_body_down_and_every_client_sees_it() -> void:
	var client := await _rig.join("Ada")
	var body := _rig.server.body_at(0)
	var prone := PlayerCommand.new()
	prone.prone = true
	var crawl := prone.clone()
	crawl.move = Vector2(0.0, 1.0)
	var lying := func() -> bool:
		return (
			client.last_tick() != null
			and client.last_tick().players[0].state == Character.State.PRONE
		)
	for _frame in 180:
		client.send_command(prone.clone())
		_rig.pump()
		if body.prone and lying.call():
			break
		await get_tree().physics_frame
	assert_bool(body.prone).is_true()
	assert_bool(lying.call()).is_true()
	# It crawls forward lying down, slower than a walk.
	var start := body.global_position
	for _frame in 60:
		client.send_command(crawl.clone())
		_rig.pump()
		await get_tree().physics_frame
	assert_int(body.state).is_equal(Character.State.PRONE)
	var crawled := body.global_position.distance_to(start)
	assert_float(crawled).is_between(0.05, body.tuning.walk_speed)

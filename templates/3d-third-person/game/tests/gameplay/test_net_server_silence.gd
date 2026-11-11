# A client that stops sending: the server steps its last command again for `command_ticks` steps
# (the body keeps walking), then a command that asks for nothing (it stands); after
# `silent_seconds` without a command it hangs up, and the seat is free for the next hello. Pings
# alone keep nobody seated. The seconds are the frame clock's, so 15 s pass in frames.
extends GdUnitTestSuite

var _rig: NetServerRig


func before_test() -> void:
	_rig = auto_free(NetServerRig.new())
	add_child(_rig)
	assert_bool(_rig.start()).is_true()


func test_a_silent_client_walks_on_for_thirty_steps_then_stands() -> void:
	var client := await _rig.join("Ada")
	var peer := _rig.server.peer_at(0)
	var body := _rig.server.body_at(0)
	var jumps: Array[int] = [0]
	body.jumped.connect(func() -> void: jumps[0] += 1)
	var walk := CommandDriver.walking(Vector3.FORWARD)
	walk.jump = true
	walk.jump_pressed = true
	client.send_command(walk)
	assert_bool(await _rig.until(func() -> bool: return peer.ack == 1)).is_true()
	var first := peer.history.find(1)
	var start := body.global_position
	await _rig.wait(_rig.server.command_ticks)
	# It walked on while the command was repeated.
	assert_float(body.global_position.distance_to(start)).is_greater(1.0)
	await _rig.wait(120)
	var later := peer.history.slice(first + 1)
	# Thirty repeats, then it stands, whatever the timing of the first.
	for index in _rig.server.command_ticks:
		assert_int(later[index]).is_equal(PeerSlot.REPEATED)
	for index in range(_rig.server.command_ticks, later.size()):
		assert_int(later[index]).is_equal(PeerSlot.STOOD)
	# The press was used once: one jump, not one on every landing; and the body stands.
	assert_int(jumps[0]).is_equal(1)
	assert_float(body.velocity.length()).is_less(0.05)
	assert_bool(body.is_on_floor()).is_true()
	assert_int(_rig.server.peer_at(0).ack).is_equal(1)


func test_one_silent_for_fifteen_seconds_is_dropped_and_its_seat_is_free() -> void:
	var client := await _rig.join("Ada")
	var other := await _rig.join("Bo")
	client.send_command(CommandDriver.walking(Vector3.FORWARD))
	var seconds := _rig.server.silent_seconds
	assert_float(seconds).is_equal(15.0)
	var silent := int(seconds * NetLimits.TICK_RATE)
	# Bo keeps sending; Ada only pings, which does not count.
	var ada_gone := func() -> bool: return _rig.server.peer_at(0) == null
	for frame in silent + 60:
		other.send_command(CommandDriver.walking(Vector3.LEFT))
		if frame % 30 == 0:
			client.link.send(NetWire.ping(frame))
		_rig.pump()
		if ada_gone.call():
			break
		await get_tree().physics_frame
	assert_bool(ada_gone.call()).is_true()
	var left := _rig.lines_of("left")
	assert_int(left.size()).is_equal(1)
	assert_str(left[0]["reason"]).is_equal("silent")
	assert_int(client.pongs).is_greater(10)
	assert_bool(await _rig.until(func() -> bool: return client.closed, 180)).is_true()
	assert_object(_rig.server.peer_at(1)).is_not_null()
	assert_int(other.heard(NetEvent.Kind.LEFT).size()).is_equal(1)
	var next := await _rig.join("Next")
	assert_int(next.welcome.slot).is_equal(0)

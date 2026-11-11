# The AI block of a TICK (gdstudio #970): a row's 14 bytes and its pinned limits, a full snapshot
# and the deltas that rebuild it on a client, a delta refused without its baseline, the interest
# radius, the tier rates, and a decoder that stays quiet and counts one drop for a hostile block.
extends GdUnitTestSuite

const ORIGIN_ROW := 7


func _row(id: int, at: Vector3, speed := 0.0) -> AiRow:
	var row := AiRow.new()
	row.id = id
	row.position = at
	row.yaw = 0.25 * id
	row.speed = speed
	row.situation = AiSituation.Situation.ALERT
	row.state = Character.State.RUN
	row.aiming = id % 2 == 0
	row.target = NetHits.PLAYER_BASE + 1
	row.variant = id % 3
	return row


func _rows(count: int, spacing := 1.0) -> Array[AiRow]:
	var out: Array[AiRow] = []
	for index in count:
		out.append(_row(index, Vector3(index * spacing, 0.0, -2.0)))
	return out


func _rates() -> AiTierRates:
	var rates := AiTierRates.new()
	rates.keyframe_seconds = 0.0
	return rates


func _held(snapshot: AiSnapshot) -> Array[int]:
	var ids: Array[int] = snapshot.rows.keys()
	ids.sort()
	return ids


func test_a_row_is_14_bytes_and_every_field_comes_back() -> void:
	var row := _row(ORIGIN_ROW, Vector3(12.34, -1.5, 300.25), 3.0)
	row.situation = AiSituation.Situation.FLEEING
	row.state = Character.State.MANTLE
	row.target = NetHits.AI_BASE + 40
	row.variant = 200
	var bytes := AiSnapshot.row_bytes(row)
	assert_int(bytes.size()).is_equal(AiSnapshot.ROW_SIZE).is_equal(14)
	var back := AiSnapshot.read_row(WireReader.new(bytes))
	assert_int(back.id).is_equal(ORIGIN_ROW)
	assert_vector(back.position).is_equal_approx(row.position, Vector3.ONE * 0.005)
	assert_float(absf(angle_difference(back.yaw, row.yaw))).is_less_equal(PI / 256.0 + 0.0001)
	assert_float(back.speed).is_equal_approx(3.0, 0.0001)
	assert_int(back.situation).is_equal(AiSituation.Situation.FLEEING)
	assert_int(back.state).is_equal(Character.State.MANTLE)
	assert_bool(back.aiming).is_equal(row.aiming)
	assert_int(back.target).is_equal(NetHits.AI_BASE + 40)
	assert_int(back.variant).is_equal(200)


func test_the_limits_of_a_row_are_pinned() -> void:
	var drops := NetDrops.new()
	# An id past the AI range, a situation past 3 bits, a state past 4: refused, counted.
	var row := _row(NetLimits.MAX_AI_ID + 1, Vector3.ZERO)
	assert_array(AiSnapshot.row_bytes(row, drops)).is_empty()
	row = _row(1, Vector3.ZERO)
	row.situation = 8
	assert_array(AiSnapshot.row_bytes(row, drops)).is_empty()
	row = _row(1, Vector3.ZERO)
	row.state = 16
	assert_array(AiSnapshot.row_bytes(row, drops)).is_empty()
	row = _row(1, Vector3(NAN, 0.0, 0.0))
	assert_array(AiSnapshot.row_bytes(row, drops)).is_empty()
	assert_int(drops.counts.get(NetDrops.BAD_VALUE, 0)).is_equal(3)
	assert_int(drops.counts.get(NetDrops.NOT_FINITE, 0)).is_equal(1)
	# The highest id travels; a position past the range is held at its edge; a speed past
	# 12.75 m/s at it; a negative speed at 0.
	row = _row(NetLimits.MAX_AI_ID, Vector3(500.0, -400.0, 327.67), 40.0)
	var back := AiSnapshot.snap_row(row)
	assert_int(back.id).is_equal(NetLimits.MAX_AI_ID)
	assert_float(back.position.x).is_equal_approx(NetLimits.POSITION_RANGE, 0.0001)
	assert_float(back.position.y).is_equal_approx(-NetLimits.POSITION_RANGE, 0.0001)
	assert_float(back.position.z).is_equal_approx(NetLimits.POSITION_RANGE, 0.0001)
	assert_float(back.speed).is_equal_approx(AiSnapshot.MAX_SPEED, 0.0001)
	row.speed = -1.0
	assert_float(AiSnapshot.snap_row(row).speed).is_equal(0.0)
	# The yaw wraps: a full turn reads as none.
	row.yaw = TAU
	assert_float(AiSnapshot.snap_row(row).yaw).is_equal_approx(0.0, 0.0001)


func test_a_full_snapshot_round_trips_and_a_late_joiner_gets_everyone_in_one() -> void:
	var rows := _rows(120, 0.5)
	var view := AiPeerView.new()
	var block := AiSnapshot.encode(rows, view, _rates(), 100)
	assert_int(block[0]).is_equal(AiSnapshot.Mode.FULL)
	assert_int(block.size()).is_equal(AiSnapshot.FULL_HEADER + 120 * AiSnapshot.ROW_SIZE)
	var client := AiSnapshot.new()
	assert_bool(client.apply_bytes(block)).is_true()
	assert_int(client.rows.size()).is_equal(120)
	assert_int(client.changed.size()).is_equal(120)
	for row in rows:
		var held: AiRow = client.rows[row.id]
		assert_vector(held.position).is_equal_approx(row.position, Vector3.ONE * 0.005)


func test_deltas_rebuild_the_server_rows_from_the_baseline() -> void:
	var rows := _rows(40)
	var rates := _rates()
	var view := AiPeerView.new()
	var client := AiSnapshot.new()
	assert_bool(client.apply_bytes(AiSnapshot.encode(rows, view, rates, 2))).is_true()
	# Nothing moved: one byte.
	var still := AiSnapshot.encode(rows, view, rates, 4)
	assert_array(still).is_equal(PackedByteArray([AiSnapshot.Mode.NONE]))
	# Five move, one leaves, one arrives.
	for index in 5:
		rows[index * 3].position += Vector3(0.1 * (index + 1), 0.0, 0.0)
	var arriving := _row(500, Vector3(3.0, 0.0, 3.0))
	var leaving := rows[39]
	rows.remove_at(39)
	rows.append(arriving)
	var delta := AiSnapshot.encode(rows, view, rates, 6)
	assert_int(delta[0]).is_equal(AiSnapshot.Mode.DELTA)
	assert_int(delta.size()).is_equal(AiSnapshot.DELTA_HEADER + 6 * AiSnapshot.ROW_SIZE + 2)
	assert_bool(client.apply_bytes(delta)).is_true()
	assert_int(client.changed.size()).is_equal(6)
	assert_array(client.gone).contains_exactly([leaving.id])
	assert_int(client.rows.size()).is_equal(40)
	for row in rows:
		assert_vector(client.rows[row.id].position).is_equal_approx(
			row.position, Vector3.ONE * 0.005
		)


func test_a_delta_with_a_missing_baseline_is_refused_until_a_full_one() -> void:
	var rows := _rows(10)
	var rates := _rates()
	var view := AiPeerView.new()
	var client := AiSnapshot.new()
	var full := AiSnapshot.encode(rows, view, rates, 2)
	rows[0].position.x += 1.0
	var first := AiSnapshot.encode(rows, view, rates, 4)
	rows[1].position.x += 1.0
	var second := AiSnapshot.encode(rows, view, rates, 6)
	var drops := NetDrops.new()
	# A delta before any full snapshot: nothing to build on.
	assert_bool(client.apply_bytes(first, drops)).is_false()
	assert_int(client.rows.size()).is_equal(0)
	assert_bool(client.apply_bytes(full, drops)).is_true()
	# The first delta lost: the second's base is not what the client holds.
	assert_bool(client.apply_bytes(second, drops)).is_false()
	assert_int(drops.counts.get(NetDrops.NO_BASELINE, 0)).is_equal(2)
	assert_int(client.refused).is_equal(2)
	assert_float(client.rows[1].position.x).is_equal_approx(rows[1].position.x - 1.0, 0.005)
	# The next full snapshot (a keyframe, or after a refused TICK) mends it.
	view.reset()
	assert_bool(client.apply_bytes(AiSnapshot.encode(rows, view, rates, 8), drops)).is_true()
	assert_float(client.rows[1].position.x).is_equal_approx(rows[1].position.x, 0.005)


func test_a_keyframe_is_full_after_its_seconds() -> void:
	var rates := AiTierRates.new()
	rates.keyframe_seconds = 2.0
	var rows := _rows(3)
	var view := AiPeerView.new()
	assert_int(AiSnapshot.encode(rows, view, rates, 10)[0]).is_equal(AiSnapshot.Mode.FULL)
	assert_int(AiSnapshot.encode(rows, view, rates, 12)[0]).is_equal(AiSnapshot.Mode.NONE)
	var due := 10 + 2 * NetLimits.TICK_RATE
	assert_int(AiSnapshot.encode(rows, view, rates, due - 2)[0]).is_equal(AiSnapshot.Mode.NONE)
	assert_int(AiSnapshot.encode(rows, view, rates, due)[0]).is_equal(AiSnapshot.Mode.FULL)


func test_the_interest_radius_leaves_out_a_far_character_and_takes_it_out_when_it_goes() -> void:
	var rates := _rates()
	var near := _row(1, Vector3(10.0, 0.0, 0.0))
	var far := _row(2, Vector3(rates.interest_radius + 1.0, 0.0, 0.0))
	var rows: Array[AiRow] = [near, far]
	var view := AiPeerView.new()
	var client := AiSnapshot.new()
	client.apply_bytes(AiSnapshot.encode(rows, view, rates, 2))
	assert_array(_held(client)).contains_exactly([1])
	# The near one walks out of the radius: a delta takes it out.
	near.position.x = rates.interest_radius + 5.0
	client.apply_bytes(AiSnapshot.encode(rows, view, rates, 4))
	assert_array(_held(client)).is_empty()
	assert_array(client.gone).contains_exactly([1])
	# The client walks to them: both come in.
	view.viewer = Vector3(rates.interest_radius, 0.0, 0.0)
	client.apply_bytes(AiSnapshot.encode(rows, view, rates, 6))
	assert_array(_held(client)).contains_exactly([1, 2])


func test_tier_rates_are_honoured() -> void:
	var rates := _rates()
	var full := _row(1, Vector3(rates.full_radius - 1.0, 0.0, 0.0), 3.0)
	var reduced := _row(2, Vector3(rates.reduced_radius - 1.0, 0.0, 0.0), 3.0)
	var dormant := _row(3, Vector3(rates.interest_radius - 1.0, 0.0, 0.0), 3.0)
	var rows: Array[AiRow] = [full, reduced, dormant]
	var view := AiPeerView.new()
	var client := AiSnapshot.new()
	var sent := {1: 0, 2: 0, 3: 0}
	# Six seconds of TICKs (every second step), every character moving every tick.
	var tick := 0
	for _send in NetLimits.SNAPSHOT_RATE * 6:
		tick += NetLimits.TICK_RATE / NetLimits.SNAPSHOT_RATE
		for row in rows:
			row.position.z += 0.01
		client.apply_bytes(AiSnapshot.encode(rows, view, rates, tick))
		for id in client.changed:
			sent[id] += 1
	# The first TICK is full; after it each tier at its rate.
	assert_int(sent[1]).is_equal(NetLimits.SNAPSHOT_RATE * 6)
	assert_int(sent[2]).is_between(roundi(rates.reduced_hz * 6), roundi(rates.reduced_hz * 6) + 1)
	assert_int(sent[3]).is_between(roundi(rates.dormant_hz * 6), roundi(rates.dormant_hz * 6) + 1)


func test_a_client_capped_lower_is_sent_the_nearest() -> void:
	var rows := _rows(50)
	var view := AiPeerView.new()
	view.cap = 20
	view.viewer = Vector3(49.0, 0.0, -2.0)
	var client := AiSnapshot.new()
	client.apply_bytes(AiSnapshot.encode(rows, view, _rates(), 2))
	assert_int(client.rows.size()).is_equal(20)
	for id: int in client.rows:
		assert_int(id).is_greater_equal(30)


func test_the_block_rides_the_tick_and_a_tick_with_no_ai_carries_one_byte() -> void:
	var players: Array[PlayerEntry] = []
	var events: Array[NetEvent] = []
	var none := SnapshotCodec.tick(10, 4, events, players)
	var read := SnapshotCodec.read_tick(none)
	assert_object(read).is_not_null()
	assert_int(read.ai.mode).is_equal(AiSnapshot.Mode.NONE)
	var block := AiSnapshot.encode(_rows(5), AiPeerView.new(), _rates(), 10)
	var with_ai := SnapshotCodec.tick(10, 4, events, players, null, [], block)
	assert_int(with_ai.size()).is_equal(none.size() - 1 + block.size())
	read = SnapshotCodec.read_tick(with_ai)
	assert_int(read.ai.mode).is_equal(AiSnapshot.Mode.FULL)
	assert_int(read.ai.rows.size()).is_equal(5)


func test_every_prefix_and_hostile_bytes_are_one_counted_drop_each() -> void:
	var view := AiPeerView.new()
	var rates := _rates()
	var rows := _rows(6)
	AiSnapshot.encode(rows, view, rates, 2)
	rows[2].position.x += 1.0
	rows.remove_at(4)
	var delta := AiSnapshot.encode(rows, view, rates, 4)
	var players: Array[PlayerEntry] = []
	var events: Array[NetEvent] = []
	var packet := SnapshotCodec.tick(4, 1, events, players, null, [], delta)
	var drops := NetDrops.new()
	for size in packet.size():
		assert_object(SnapshotCodec.read_tick(packet.slice(0, size), drops)).is_null()
	assert_int(drops.total()).is_equal(packet.size())
	# A count past the bytes, an unknown mode, a repeated id: refused, counted.
	var claimed := delta.duplicate()
	claimed.encode_u16(3, NetLimits.MAX_AI_ROWS)
	var bad_mode := PackedByteArray([9])
	var twice := AiSnapshot.encode(_rows(2), AiPeerView.new(), rates, 2)
	twice.encode_u16(AiSnapshot.FULL_HEADER + AiSnapshot.ROW_SIZE, 0)
	drops = NetDrops.new()
	for bad in [claimed, bad_mode, twice]:
		assert_object(AiSnapshot.read(bad, drops)).is_null()
	assert_int(drops.total()).is_equal(3)
	# A few hundred one-byte mutations of the packet: each read or one counted drop.
	var rng := RandomNumberGenerator.new()
	rng.seed = 970
	drops = NetDrops.new()
	var dropped := 0
	for _try in 400:
		var mutated := packet.duplicate()
		mutated[rng.randi_range(0, mutated.size() - 1)] = rng.randi_range(0, 255)
		var counted := drops.total()
		if SnapshotCodec.read_tick(mutated, drops) == null:
			dropped += 1
			assert_int(drops.total()).is_equal(counted + 1)
		else:
			assert_int(drops.total()).is_equal(counted)
	assert_int(drops.total()).is_equal(dropped)


func test_the_bytes_of_40_and_120_characters_against_deadnight() -> void:
	# The population of the issue on a 100 x 100 m ground, walking, seen from its middle.
	var rates := AiTierRates.new()
	var lines := PackedStringArray()
	for count in [40, 120]:
		var rng := RandomNumberGenerator.new()
		rng.seed = count
		var rows: Array[AiRow] = []
		for index in count:
			var at := Vector3(rng.randf_range(-50.0, 50.0), 0.0, rng.randf_range(-50.0, 50.0))
			rows.append(_row(index, at, 1.5))
		var view := AiPeerView.new()
		var full := AiSnapshot.encode(rows, view, rates, 2).size()
		var total := 0
		var tick := 2
		for _send in NetLimits.SNAPSHOT_RATE * 10:
			tick += 2
			for row in rows:
				row.position += Vector3(0.05, 0.0, 0.0).rotated(Vector3.UP, row.yaw)
			total += AiSnapshot.encode(rows, view, rates, tick).size()
		var per_tick := float(total) / (NetLimits.SNAPSHOT_RATE * 10)
		lines.append("%d: full %d B, delta %.0f B a tick" % [count, full, per_tick])
		# Deadnight's target: 561 B a tick at 120 with an interest radius.
		assert_float(per_tick).is_less(561.0 if count == 120 else 300.0)
	print("ai snapshot bytes: ", "; ".join(lines))

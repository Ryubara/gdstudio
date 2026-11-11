# On the clock: two cases time a client's and the server's work for the props, in microseconds.
# A pushed prop's record (`PropState`, 11 bytes), a client's track of them (`PropTrack`), and what
# the props and targets of the prototype map cost on the wire and in a step (gdstudio #1073), with
# a game server and two clients over a real socket on 127.0.0.1 (`OnlineRig`).
extends GdUnitTestSuite

const SETTLE_TICKS := 150

var _rig: OnlineRig
var _bo: NetClient


func after_test() -> void:
	_rig = null
	_bo = null


func test_a_record_keeps_the_place_to_a_centimetre_and_the_turn_to_a_fifth_of_a_degree() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1073
	var worst := 0.0
	for _index in 2000:
		var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if axis.length_squared() < 0.0001:
			continue
		var turned := Quaternion(axis.normalized(), rng.randf_range(-PI, PI))
		var at := Vector3(
			rng.randf_range(-300, 300), rng.randf_range(-30, 30), rng.randf_range(-300, 300)
		)
		var state := PropState.make(at, turned, rng.randf() < 0.5, rng.randf() < 0.5)
		var bytes := state.write()
		assert_int(bytes.size()).is_equal(PropState.SIZE)
		var read := PropState.read(bytes)
		assert_float(read.position.distance_to(at)).is_less_equal(0.0087)
		worst = maxf(worst, rad_to_deg(read.rotation.angle_to(turned)))
		assert_bool(read.asleep).is_equal(state.asleep)
		assert_bool(read.jumped).is_equal(state.jumped)
	prints("prop record: worst turn off %.3f degrees" % worst)
	assert_float(worst).is_less(0.2)
	assert_object(PropState.read(PackedByteArray([1, 2, 3]))).is_null()
	var nan := PropState.make(Vector3.ZERO, Quaternion(NAN, 0, 0, 1)).write()
	assert_float(PropState.read(nan).rotation.angle_to(Quaternion.IDENTITY)).is_less(0.003)


func test_the_track_blends_between_records_and_goes_on_at_their_speed_for_a_while() -> void:
	var track := PropTrack.new()
	var fallback := Transform3D(Basis.IDENTITY, Vector3(9, 9, 9))
	assert_vector(track.sample(10, fallback).origin).is_equal(fallback.origin)
	var turn := Quaternion(Vector3.UP, 0.2)
	track.push(100, PropState.make(Vector3(0, 0, 0), Quaternion.IDENTITY))
	track.push(102, PropState.make(Vector3(0, 0, -0.1), turn))
	assert_vector(track.sample(101, fallback).origin).is_equal_approx(
		Vector3(0, 0, -0.05), Vector3.ONE * 1e-5
	)
	assert_vector(track.sample(90, fallback).origin).is_equal(Vector3.ZERO)
	# Past the newest: on at 0.05 m a tick, and the turn with it, for at most AHEAD_TICKS.
	assert_vector(track.sample(106, fallback).origin).is_equal_approx(
		Vector3(0, 0, -0.3), Vector3.ONE * 1e-5
	)
	var turned := Quaternion(track.sample(104, fallback).basis)
	assert_float(turned.angle_to(Quaternion(Vector3.UP, 0.4))).is_less(1e-4)
	var far := track.sample(102 + PropTrack.AHEAD_TICKS + 50, fallback).origin
	assert_vector(far).is_equal_approx(
		Vector3(0, 0, -0.1 - 0.05 * PropTrack.AHEAD_TICKS), Vector3.ONE * 1e-5
	)
	# An asleep record is held; a jumped one forgets the rest (no slide from where it was).
	track.push(104, PropState.make(Vector3(0, 0, -0.2), turn, true))
	assert_vector(track.sample(140, fallback).origin).is_equal(Vector3(0, 0, -0.2))
	track.push(106, PropState.make(Vector3(5, 0, 5), Quaternion.IDENTITY, false, true))
	assert_int(track.size()).is_equal(1)
	assert_vector(track.sample(105, fallback).origin).is_equal(Vector3(5, 0, 5))
	# An older record is ignored, one of the same tick replaces the newest.
	track.push(100, PropState.make(Vector3(1, 1, 1), Quaternion.IDENTITY))
	track.push(106, PropState.make(Vector3(6, 0, 6), Quaternion.IDENTITY))
	assert_int(track.size()).is_equal(1)
	assert_vector(track.newest().position).is_equal(Vector3(6, 0, 6))


func test_records_far_apart_in_time_give_no_speed() -> void:
	var track := PropTrack.new()
	track.push(10, PropState.make(Vector3.ZERO, Quaternion.IDENTITY, true))
	track.push(400, PropState.make(Vector3(1, 0, 0), Quaternion.IDENTITY))
	assert_vector(track.sample(410, Transform3D.IDENTITY).origin).is_equal(Vector3(1, 0, 0))


func test_a_tick_carries_the_streamed_rows_and_a_decoder_refuses_a_lying_count() -> void:
	var players: Array[PlayerEntry] = []
	var rows: Array[EntityEntry] = []
	for index in 3:
		var state := PropState.make(Vector3(index, 0.5, -index), Quaternion.IDENTITY).write()
		rows.append(EntityEntry.make(20 + index, 0, state))
	var packet := SnapshotCodec.tick(77, 5, [] as Array[NetEvent], players, null, rows)
	var read := SnapshotCodec.read_tick(packet, NetDrops.new())
	assert_object(read).is_not_null()
	assert_int(read.parts.size()).is_equal(3)
	assert_int(read.parts[2].id).is_equal(22)
	assert_vector(PropState.read(read.parts[2].state).position).is_equal(Vector3(2, 0.5, -2))
	var lying := packet.duplicate()
	lying[NetWire.TICK_HEADER] = 9
	var drops := NetDrops.new()
	assert_object(SnapshotCodec.read_tick(lying, drops)).is_null()
	assert_int(drops.total()).is_equal(1)
	var cut := packet.slice(0, packet.size() - 1)
	assert_object(SnapshotCodec.read_tick(cut, NetDrops.new())).is_null()
	var too_many: Array[EntityEntry] = []
	for index in NetLimits.MAX_STREAMED_PARTS + 1:
		too_many.append(rows[0])
	(
		assert_bool(
			SnapshotCodec.tick(1, 1, [] as Array[NetEvent], players, null, too_many).is_empty()
		)
		. is_true()
	)


func test_the_props_and_targets_fit_the_wire_and_cost_a_client_little() -> void:
	await _start()
	var parts := _rig.server.map_parts
	var players: Array[PlayerEntry] = []
	var table := parts.table(_rig.server.server_tick)
	var by_kind := {}
	var counts := {}
	for entry in table:
		by_kind[entry.kind] = entry.state.size()
		counts[entry.kind] = int(counts.get(entry.kind, 0)) + 1
	var welcome := SnapshotCodec.welcome(0, 1, 1, table, players).size()
	var rows := parts.stream_rows(_rig.server.server_tick, true)
	var bare := SnapshotCodec.tick(1, 1, [] as Array[NetEvent], players).size()
	var one := SnapshotCodec.tick(
		1, 1, [] as Array[NetEvent], players, null, rows.slice(0, 1) as Array[EntityEntry]
	)
	var every := SnapshotCodec.tick(1, 1, [] as Array[NetEvent], players, null, rows)
	var target := _target(_rig.server_view, "TargetA").get_node("NetEntity") as NetEntity
	var target_event := NetEvent.entity(target.id, 1, target.write_state.call(1))
	var with_event := SnapshotCodec.tick(1, 1, [target_event] as Array[NetEvent], players).size()
	# A client's work for the props: reading a TICK's rows, every prop moving (a TICK every second
	# step, `MAX_STREAMED_PARTS` rows each), and putting every prop at the predicted tick each step.
	var map := _bo.map_parts
	var props := map.entities.filter(
		func(entity: NetEntity) -> bool: return entity.kind() == NetEntity.KINDS[&"prop"]
	)
	var read_us := 0
	var place_us := 0
	var steps := 600
	var from_tick := _bo.seq + 1000
	for index in steps:
		var tick := from_tick + index
		if index % 2 == 0:
			var moving: Array[EntityEntry] = []
			for offset in NetLimits.MAX_STREAMED_PARTS:
				var turn := (index >> 1) * NetLimits.MAX_STREAMED_PARTS + offset
				var entity: NetEntity = props[turn % props.size()]
				var at := Vector3(entity.id, 0.5, index * 0.02)
				var state := PropState.make(at, Quaternion(Vector3.UP, index * 0.01)).write()
				moving.append(EntityEntry.make(entity.id, 0, state))
			var read_began := Time.get_ticks_usec()
			map.read_stream(moving, tick)
			read_us += Time.get_ticks_usec() - read_began
		var place_began := Time.get_ticks_usec()
		map.place(tick + 12)
		place_us += Time.get_ticks_usec() - place_began
	var read_each := read_us / float(steps)
	var place_each := place_us / float(steps)
	var server_began := Time.get_ticks_usec()
	for index in 300:
		parts.stream_rows(index, true)
	var server_each := (Time.get_ticks_usec() - server_began) / 300.0
	prints(
		"props online: %d props, %d targets," % [counts.get(5, 0), counts.get(6, 0)],
		"WELCOME %d bytes," % welcome,
		(
			"TICK row of one moving prop %d bytes, of %d %d bytes,"
			% [one.size() - bare, rows.size(), every.size() - bare]
		),
		"target event %d bytes;" % (with_event - bare),
		(
			"client a step, every prop moving: %.1f us reading, %.1f us placing;"
			% [read_each, place_each]
		),
		"server %.1f us a TICK's rows" % server_each
	)
	assert_int(by_kind[NetEntity.KINDS[&"prop"]]).is_equal(PropState.SIZE)
	assert_int(by_kind[NetEntity.KINDS[&"target"]]).is_equal(1)
	var prop_count: int = counts[NetEntity.KINDS[&"prop"]]
	assert_int(prop_count).is_equal(props.size())
	assert_int(rows.size()).is_equal(mini(prop_count, NetLimits.MAX_STREAMED_PARTS))
	assert_int(parts.all_ticks()).is_equal(ceili(prop_count / float(NetLimits.MAX_STREAMED_PARTS)))
	assert_int(one.size() - bare).is_equal(NetWire.STREAM_ROW_HEADER + PropState.SIZE)
	assert_int(with_event - bare).is_equal(9)
	assert_int(welcome).is_less(SnapshotCodec.MAX_WELCOME)
	assert_float(read_each + place_each).is_less(200.0)
	assert_float(server_each).is_less(200.0)


func test_a_prop_at_rest_rides_no_tick() -> void:
	await _start()
	await _rig.wait(SETTLE_TICKS)
	assert_int(_rig.server.map_parts.stream_rows(_rig.server.server_tick).size()).is_equal(0)


func _start() -> void:
	_rig = auto_free(OnlineRig.new(false))
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	assert_object(await _rig.join("Ada", 600)).is_not_null()
	_bo = await _rig.join("Bo", 600)
	assert_object(_bo).is_not_null()
	await _rig.wait(30)


static func _target(view: Node, target_name: String) -> Target:
	return view.find_child(target_name, true, false) as Target

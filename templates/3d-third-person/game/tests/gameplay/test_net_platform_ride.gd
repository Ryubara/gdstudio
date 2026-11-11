# A predicted body that rides the map's moving platform (`Platforms/Shuttle`): the server steps each
# command with the slab where it is at the command's tick, and the client predicts the command with
# its slab at the same tick (`NetWorld.place`), so the two bodies are carried alike
# (`PlatformRider`) and stay within 2 cm over whole ping-pong rides, over a real socket and over
# 100 ms each way.
extends GdUnitTestSuite

## The shuttle's path in `world/prototype/prototype_level.tscn`: z 6 to 10 at x 18, its top at
## y 2; `Landings/BridgeEnd` (top y 2) starts at z 12.
const BRIDGE_END := Vector3(18.0, 2.0, 13.6)
## The shuttle's whole ping-pong (two crossings of 2 s and two waits of 1.5 s), in ticks.
const CYCLE_TICKS := 420
const MAX_ERROR := 0.02

var _rig: OnlineRig
var _client: NetClient
var _phase := 0
var _boarded_at := -1


func before_test() -> void:
	_phase = 0
	_boarded_at = -1


func test_a_rider_stays_with_the_server_body_over_two_rides() -> void:
	await _ride(0.0, 0.0)


func test_a_rider_stays_with_the_server_body_at_100_ms_each_way() -> void:
	await _ride(0.1, 0.01)


func test_both_worlds_hold_the_slab_at_the_same_place_for_a_tick() -> void:
	_rig = auto_free(OnlineRig.new(false))
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_client = await _rig.join("Ada")
	await _rig.wait(30)
	var ours := _shuttle(_rig.views[0])
	var theirs := _shuttle(_rig.server_view)
	for tick in range(_client.seq, _client.seq + CYCLE_TICKS, 7):
		assert_vector(ours.position_at(tick)).is_equal_approx(
			theirs.position_at(tick), Vector3.ONE * 0.0001
		)
	# What each side shows now: the client's slab at its predicted command, the server's at its
	# step, each the same function of its own tick.
	assert_vector(ours.global_position).is_equal_approx(
		theirs.position_at(_client.seq), Vector3.ONE * 0.0001
	)
	assert_vector(theirs.global_position).is_equal_approx(
		theirs.position_at(_rig.server.server_tick), Vector3.ONE * 0.0001
	)


func test_player_two_sees_the_rider_standing_still_on_the_slab_it_draws() -> void:
	# Player two draws the slab at its own predicted tick and the rider's puppet 100 ms behind the
	# newest snapshot; the puppet is moved with the slab it stands on (`RemotePlayers`), so a rider
	# standing still on the slab stays at one place on it.
	_rig = auto_free(OnlineRig.new(false))
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_client = await _rig.join("Ada")
	var bo := await _rig.join("Bo")
	await _rig.wait(20)
	_client.player.teleport(BRIDGE_END, 0.0)
	_rig.server_body(_client).teleport(BRIDGE_END, 0.0)
	_rig.controllers[0].plan = _board
	assert_bool(await _rig.until(func() -> bool: return _boarded_at >= 0, 900)).is_true()
	await _rig.wait(60)
	var adas_slab := _shuttle(_rig.views[0])
	var bos_slab := _shuttle(_rig.views[1])
	var puppet := bo.remote_players.puppet_at(_client.slot)
	var on_ada := _client.player.global_position - adas_slab.global_position
	var worst := 0.0
	var moved := 0.0
	var last_z := bos_slab.global_position.z
	for _i in CYCLE_TICKS:
		await get_tree().physics_frame
		var on_bo := puppet.global_position - bos_slab.global_position
		worst = maxf(worst, (on_bo - on_ada).length())
		moved += absf(bos_slab.global_position.z - last_z)
		last_z = bos_slab.global_position.z
	prints(
		(
			"rider on player two's slab: worst %.4f m off its place over %.1f m of ride"
			% [worst, moved]
		)
	)
	assert_float(moved).is_greater(7.9)
	assert_float(worst).is_less(0.05)


func test_commands_are_numbered_by_the_server_tick_again_after_a_stall() -> void:
	# A client that stops stepping for a while (a frozen tab: its stall guard skips the catch-up
	# ticks) numbers its next commands behind the server's tick; the first TICK moves the numbers
	# on, so the slab's tick for a command is again about when the server steps it.
	_rig = auto_free(OnlineRig.new(false))
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_client = await _rig.join("Ada")
	await _rig.wait(60)
	var ahead := _client.seq - _rig.server.server_tick
	_client.set_physics_process(false)
	await _rig.wait(90)
	var behind := _client.seq + 1 - _rig.server.server_tick
	_client.set_physics_process(true)
	await _rig.wait(60)
	var settled := _client.seq - _rig.server.server_tick
	prints("renumbered:", _client.renumbered, "ahead", ahead, "then", behind, "after", settled)
	assert_int(behind).is_less(ahead - 60)
	assert_int(_client.renumbered).is_greater_equal(1)
	assert_int(absi(settled - ahead)).is_less_equal(NetClient.SEQ_SLACK)
	assert_int(_rig.server.kicked).is_equal(0)


func _ride(delay: float, jitter: float) -> void:
	_rig = auto_free(OnlineRig.new(false))
	_rig.delay = delay
	_rig.jitter = jitter
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_client = await _rig.join("Ada")
	assert_object(_client).is_not_null()
	await _rig.wait(20)
	# Both bodies on the far landing, facing the shuttle (-Z).
	_client.player.teleport(BRIDGE_END, 0.0)
	_rig.server_body(_client).teleport(BRIDGE_END, 0.0)
	_rig.controllers[0].plan = _board
	assert_bool(await _rig.until(func() -> bool: return _boarded_at >= 0, 900)).is_true()
	# Settled on the slab: from here on, every answer counts.
	await _rig.wait(60)
	var reconciler := _client.reconciler
	var corrections := reconciler.corrections
	reconciler.worst_error = 0.0
	var shuttle := _shuttle(_rig.views[0])
	var lowest_z := INF
	var highest_z := -INF
	var worst_gap := 0.0
	for _i in 2 * CYCLE_TICKS:
		await get_tree().physics_frame
		var at := _client.player.global_position
		lowest_z = minf(lowest_z, at.z)
		highest_z = maxf(highest_z, at.z)
		var slab := shuttle.global_position
		worst_gap = maxf(worst_gap, absf(at.z - slab.z))
	# The last answer compares the server's body after a command with where the client's was after
	# the same command (the live bodies are a round trip of commands apart while the slab moves).
	var gap := reconciler.last_error
	prints(
		"platform ride, %.0f ms each way:" % (delay * 1000.0),
		"corrections",
		reconciler.corrections - corrections,
		"worst error %.4f m," % reconciler.worst_error,
		"last error %.4f m," % gap,
		"rode z %.2f to %.2f" % [lowest_z, highest_z]
	)
	# It rode the whole way, standing on the slab, and the server's body with it.
	assert_float(highest_z - lowest_z).is_greater(3.9)
	assert_float(worst_gap).is_less(2.0)
	assert_float(reconciler.worst_error).is_less(MAX_ERROR)
	assert_float(gap).is_less(MAX_ERROR)
	assert_int(reconciler.snaps).is_equal(0)


# Waits on the landing until the shuttle has just reached this end, walks onto it and stands.
func _board(_tick: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	var shuttle := _shuttle(_rig.views[0])
	var ride := shuttle.ride_at(_client.seq)
	match _phase:
		0:
			if ride.wait > 1.2 and ride.distance >= shuttle.travel.length() - 0.001:
				_phase = 1
		1:
			if _client.player.global_position.z > shuttle.global_position.z + 0.6:
				command.move = Vector2(0.0, 1.0)
			else:
				_phase = 2
		2:
			if _boarded_at < 0 and _client.player.is_on_floor():
				_boarded_at = _client.seq
	command.yaw = 0.0
	return command


static func _shuttle(view: Node) -> MovingPlatform:
	return view.find_child("Shuttle", true, false) as MovingPlatform

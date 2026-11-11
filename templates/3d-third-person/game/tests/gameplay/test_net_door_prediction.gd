# A predicted body that walks into a closing door: the server decides the close, it starts
# `NetServer.entity_lead_ticks` later, and the client hears of it before its predicted commands
# reach that tick, so both bodies meet the same panel at every tick (`Door.openness_at`) and the
# client is not corrected by more than 5 cm in 200 ticks at 100 ms round trip.
extends GdUnitTestSuite

## In front of the room's door (`Doors/MainDoor`, a panel that slides along +X, at z -9.5), facing
## it (-Z), clear of the pressure pad (z -6.5 to -3.5).
const START := Vector3(13.0, 0.0, -7.4)
const FACING_NORTH := PI
const RUN_TICKS := 200
## The plan tick the closing panel's edge crosses the doorway's middle (its start and half the
## door's `open_time`), as the walking body reaches it; the server decides the close the lead
## earlier.
const CLOSE_CROSSES_AT := 74

var _rig: OnlineRig
var _client: NetClient
var _door: Door
var _close_at := 0


func test_walking_into_a_closing_door_at_100_ms_round_trip_meets_the_same_panel() -> void:
	var run := await _walk_into_closing_door(0.05, 0.0, 12)
	assert_float(run["worst"]).is_less(0.05)
	assert_bool(run["blocked"]).is_true()


func test_at_500_ms_the_lead_must_cover_the_round_trip() -> void:
	# The control: a close that starts at the tick it is decided reaches a client a round trip of
	# commands after its predicted body stepped them (30 at 500 ms, the server's commands are
	# numbered by the tick they are stepped at), and the panel meets this body 16 ticks after it
	# starts: the client walks on where the server's body was pushed back. A lead of 36 steps
	# covers it again.
	var late := await _walk_into_closing_door(0.25, 0.0, 0)
	assert_float(late["worst"]).is_greater(0.05)
	var covered := await _walk_into_closing_door(0.25, 0.0, 36)
	assert_float(covered["worst"]).is_less(0.05)


func _walk_into_closing_door(delay: float, jitter: float, lead: int) -> Dictionary:
	_rig = auto_free(OnlineRig.new(false))
	_rig.delay = delay
	_rig.jitter = jitter
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_rig.server.entity_lead_ticks = lead
	_close_at = CLOSE_CROSSES_AT - 24 - lead
	_client = await _rig.join("Ada")
	assert_object(_client).is_not_null()
	_door = _rig.server_view.find_child("MainDoor", true, false) as Door
	_door.open()
	var ours := _rig.views[0].find_child("MainDoor", true, false) as Door
	assert_bool(await _rig.until(ours.is_open, 240)).is_true()
	_client.player.teleport(START, FACING_NORTH)
	_rig.server_body(_client).teleport(START, FACING_NORTH)
	await _rig.wait(30)
	var reconciler := _client.reconciler
	var corrections := reconciler.corrections
	reconciler.worst_error = 0.0
	_rig.controllers[0].ticks = 0
	_rig.controllers[0].plan = _walk
	await _rig.wait(RUN_TICKS)
	var furthest := _client.player.global_position.z
	var result := {
		"worst": reconciler.worst_error,
		"corrections": reconciler.corrections - corrections,
		"blocked": furthest > -9.6,
	}
	prints(
		"closing door, %.0f ms each way, lead %d:" % [delay * 1000.0, lead],
		"corrections",
		result["corrections"],
		"worst error %.4f m," % result["worst"],
		"body at z %.2f," % furthest,
		"door %.2f open" % ours.openness()
	)
	return result


# Walks north into the doorway; the server closes the door so it starts at the same moment
# whatever the lead.
func _walk(tick: int) -> PlayerCommand:
	if tick == _close_at:
		_door.close()
	var command := PlayerCommand.new()
	command.yaw = 0.0
	command.move = Vector2(0.0, 1.0)
	command.walk = true
	return command

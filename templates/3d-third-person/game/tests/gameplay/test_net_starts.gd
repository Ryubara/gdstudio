# Starts from standing online (gdstudio #1453). The controller's acceleration carries a body past
# `GaitSettings.standing_speed` on the tick it is first asked to move (0.47 m/s at 28 m/s²), so a
# start read from the speed alone never played; `GaitTransitions.START_GRACE` (gdstudio #1427)
# keeps the start for a few frames after the body last stood. On Ada's own screen her body is
# stepped by the predicting client in a game served over a loopback link: it plays the walk's,
# the jog's and the sprint's start from standing as the body stepped offline does. Bo's puppet of
# her plays the same gait's start.
extends GdUnitTestSuite

## Where Ada runs from, westwards along z = 16.6, clear of the prototype level's parts (the lane
## `tools/capture/puppet_gait_tour.tscn` films).
const START := Vector3(5.0, 0.0, 16.6)
const WEST := -PI / 2.0
## Where Bo stands and watches.
const BO_AT := Vector3(3.5, 0.0, 14.0)
## Physics frames of each start, and of the stand before it (long enough for the stop to end and
## the snapshots' delay to pass).
const MOVE_FRAMES := 30
const STAND_FRAMES := 90
## The starts each gait plays, by base (no foot).
const PLAYER := "res://gameplay/player/player.tscn"
const STARTS := {
	"walk": &"gds/Idle_To_Walk",
	"jog": &"gds/Idle_To_Jog",
	"sprint": &"gds/Idle_To_Sprint",
}

var _rig: OnlineRig
var _ada: NetClient
var _bo: NetClient


func after_test() -> void:
	_rig = null
	_ada = null
	_bo = null


func test_starts_from_standing_play_on_her_own_screen_and_on_the_puppet() -> void:
	_rig = auto_free(OnlineRig.new(true))
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_ada = await _rig.join("Ada")
	_bo = await _rig.join("Bo")
	assert_object(_ada).is_not_null()
	assert_object(_bo).is_not_null()
	await _rig.wait(20)
	_put(_bo, BO_AT, 0.0)
	var puppet := _bo.remote_players.puppet_at(_ada.slot)
	assert_object(puppet).is_not_null()
	for gait: String in STARTS:
		_put(_ada, START, WEST)
		await _stand(STAND_FRAMES)
		var seen := await _run(gait, MOVE_FRAMES, puppet)
		var want: Array[StringName] = [STARTS[gait]]
		(
			assert_array(seen.own)
			. override_failure_message(
				"%s from standing: her own body began %s, not %s" % [gait, seen.own, want]
			)
			. is_equal(want)
		)
		(
			assert_array(seen.puppet)
			. override_failure_message(
				"%s from standing: the puppet began %s, her own body %s" % [gait, seen.puppet, want]
			)
			. is_equal(want)
		)


func test_the_entry_carries_the_goal_speed_in_the_state_byte() -> void:
	# The goal speed travels in the state byte's top four bits, in fifteenths of the sprint speed:
	# no byte more, and every state still fits the low four.
	assert_int(Character.State.size()).is_less_equal(SnapshotCodec.STATE_MASK + 1)
	var entry := PlayerEntry.new()
	entry.state = Character.State.MANTLE
	entry.goal_step = SnapshotCodec.GOAL_STEPS
	var read := SnapshotCodec.snap_player(entry)
	assert_int(read.state).is_equal(Character.State.MANTLE)
	assert_int(read.goal_step).is_equal(SnapshotCodec.GOAL_STEPS)
	assert_int(SnapshotCodec.player_size(entry)).is_equal(SnapshotCodec.PLAYER_SIZE)
	# The server sends the goal its body's command asks for; a puppet reads back the same gait.
	var body := (load(PLAYER) as PackedScene).instantiate() as Player
	add_child(body)
	var tuning := body.tuning
	for gait: String in STARTS:
		var command := CommandDriver.walking(Vector3.LEFT)
		command.walk = gait == "walk"
		command.sprint = gait == "sprint"
		body.last_command = command
		var sent := SnapshotCodec.snap_player(NetServer.entry_of(0, body))
		var goal := SnapshotCodec.goal_from_step(sent.goal_step, tuning.sprint_speed)
		assert_float(goal).is_equal_approx(body.goal_speed, tuning.sprint_speed / 30.0)
	body.last_command = PlayerCommand.new()
	assert_int(NetServer.entry_of(0, body).goal_step).is_equal(0)
	body.free()
	# The puppet's goal: the entry's speed along where the snapshots head, along the goal it had
	# while they head too slowly, along the facing with neither.
	var asked := PlayerEntry.new()
	asked.goal_step = SnapshotCodec.GOAL_STEPS
	asked.yaw = PI / 2.0
	(
		assert_vector(PlayerPuppet.goal_of(asked, Vector3.LEFT * 1.2, Vector3.ZERO, 6.5))
		. is_equal_approx(Vector3.LEFT * 6.5, Vector3.ONE * 0.001)
	)
	assert_vector(PlayerPuppet.goal_of(asked, Vector3.ZERO, Vector3.BACK, 6.5)).is_equal_approx(
		Vector3.BACK * 6.5, Vector3.ONE * 0.001
	)
	assert_vector(PlayerPuppet.goal_of(asked, Vector3.ZERO, Vector3.ZERO, 6.5)).is_equal_approx(
		Vector3.RIGHT * 6.5, Vector3.ONE * 0.001
	)


# Ada stands for `frames` physics frames.
func _stand(frames: int) -> void:
	for frame in frames:
		var stand := PlayerCommand.new()
		stand.yaw = WEST - PI
		_rig.controllers[0].next = stand
		await get_tree().physics_frame


# Ada moves west in `gait` for `frames` physics frames. Answers the transition clips her own body
# and Bo's puppet of her began (`own`, `puppet`), by base: no foot.
func _run(gait: String, frames: int, puppet: Player) -> Dictionary:
	var transitions := _transitions(puppet)
	var own_transitions := _transitions(_ada.player)
	var serials := [transitions.serial, own_transitions.serial]
	var begun: Array[StringName] = []
	var own_begun: Array[StringName] = []
	for frame in frames:
		var command := CommandDriver.walking(Vector3.LEFT, Vector3.LEFT)
		command.walk = gait == "walk"
		command.sprint = gait == "sprint"
		_rig.controllers[0].next = command
		await get_tree().physics_frame
		serials[0] = _note_begun(transitions, serials[0], begun)
		serials[1] = _note_begun(own_transitions, serials[1], own_begun)
	return {"puppet": begun, "own": own_begun}


static func _transitions(body: Character) -> GaitTransitions:
	return (body.get_node(^"Animation") as CharacterAnimation).gait.transitions


# Adds the clip `transitions` began since `serial` to `begun` (its base, without the foot), and
# answers the serial now.
static func _note_begun(transitions: GaitTransitions, serial: int, begun: Array[StringName]) -> int:
	if transitions.serial != serial and transitions.is_playing():
		var clip := String(transitions.clip)
		if clip.ends_with("_L") or clip.ends_with("_R"):
			clip = clip.left(-2)
		begun.append(StringName(clip))
	return transitions.serial


func _put(client: NetClient, spot: Vector3, heading: float) -> void:
	_rig.server_body(client).teleport(spot, heading)
	client.player.teleport(spot, heading)
	var stand := PlayerCommand.new()
	stand.yaw = heading - PI
	_rig.controllers[_rig.clients.find(client)].next = stand

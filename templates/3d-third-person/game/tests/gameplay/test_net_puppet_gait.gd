# Starts and stops seen on another screen (gdstudio #1420). `GaitTransitions` read the goal from
# `Character.goal_speed`, which comes from the last command, and a puppet never steps: its goal
# was always 0, so every moving puppet was taken for a body asked to stop and stood in the stop
# clip's last frame while it slid along the ground. Now a puppet's goal is the velocity its
# snapshots head for (`InterpolationTrack.heading`), and none once the entry says the player asked
# for no move (`PlayerEntry.halt`, one bit of the flags byte: the drawn motion cannot tell a stop
# from a slow-down to a jog for the first tenth of a second of the brake, and a stop picked late
# took the jog's or the walk's clip). Ada walks, sprints and stops in a game served over a loopback
# link; Bo's puppet of her plays a start, keeps its gait (no stop, a pose that moves) while she
# moves, and plays the stop her own body plays when she stops.
extends GdUnitTestSuite

## Where Ada runs from, westwards along z = 16.6, clear of the prototype level's parts (the lane
## `tools/capture/puppet_aim_tour.tscn` films).
const START := Vector3(5.0, 0.0, 16.6)
const WEST := -PI / 2.0
## Where Bo stands and watches.
const BO_AT := Vector3(3.5, 0.0, 14.0)
## Physics frames of each part, and the frames at its start left out of the steady checks (the
## start and the snapshots' delay).
const WALK_FRAMES := 70
const SPRINT_FRAMES := 70
const STOP_FRAMES := 60
const SETTLE := 30
## The least mean turn of the puppet's largest-turning bone a frame, in degrees, while it walks
## and sprints: the stepped body's gait turns 10 to 19; one held in a stop clip's last frame 0.2.
const LEAST_POSE_TURN := 3.0
const PLAYER := "res://gameplay/player/player.tscn"

var _rig: OnlineRig
var _ada: NetClient
var _bo: NetClient


func after_test() -> void:
	_rig = null
	_ada = null
	_bo = null


func test_a_puppet_starts_keeps_its_gait_and_stops_as_the_player_does() -> void:
	_rig = auto_free(OnlineRig.new(true))
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_ada = await _rig.join("Ada")
	_bo = await _rig.join("Bo")
	assert_object(_ada).is_not_null()
	assert_object(_bo).is_not_null()
	await _rig.wait(20)
	_put(_bo, BO_AT, 0.0)
	_put(_ada, START, WEST)
	await _rig.wait(30)
	var puppet := _bo.remote_players.puppet_at(_ada.slot)
	assert_object(puppet).is_not_null()

	var walk := await _run("walk", Vector3.LEFT, WALK_FRAMES, puppet)
	var sprint := await _run("sprint", Vector3.LEFT, SPRINT_FRAMES, puppet)
	var stop := await _run("", Vector3.ZERO, STOP_FRAMES, puppet)

	# As she sets off and speeds up the puppet begins what her own body begins (a stop before the
	# fix), and as she stops the stop her own body plays, the sprint's (the foot may differ: each
	# picks it from its own gait phase).
	for part: Dictionary in [walk, sprint]:
		(
			assert_array(part.puppet)
			. override_failure_message(
				"%s: the puppet began %s, her own body %s" % [part.name, part.puppet, part.own]
			)
			. is_equal(part.own)
		)
	(
		assert_array(stop.own)
		. override_failure_message("stop: her own body began %s" % [stop.own])
		. is_equal([&"gds/Sprint_Stop"])
	)
	(
		assert_array(stop.puppet)
		. override_failure_message(
			"stop: the puppet began %s, her own body %s" % [stop.puppet, stop.own]
		)
		. is_equal(stop.own)
	)
	# While she walks and sprints on, the puppet is in its gait, not in a stop, and its pose moves.
	for part: Dictionary in [walk, sprint]:
		var label: String = part.name
		(
			assert_int(part.stop_frames)
			. override_failure_message(
				"%s: a stop played on %d steady frames" % [label, part.stop_frames]
			)
			. is_equal(0)
		)
		(
			assert_float(part.pose_turn)
			. override_failure_message(
				"%s: the puppet's pose turns %.2f degrees a frame" % [label, part.pose_turn]
			)
			. is_greater(LEAST_POSE_TURN)
		)
		assert_float(part.speed).is_greater(1.0)
	# She stands at the end, and so does the puppet.
	assert_float(puppet.ground_speed()).is_less(0.3)


func test_the_entry_says_when_the_player_asked_for_no_move() -> void:
	# The halt flag travels in the entry's flags byte, bit 7, at no cost in bytes.
	var entry := PlayerEntry.new()
	entry.halt = true
	entry.dead = true
	var read := SnapshotCodec.snap_player(entry)
	assert_bool(read.halt).is_true()
	assert_bool(read.dead).is_true()
	assert_int(SnapshotCodec.player_size(entry)).is_equal(SnapshotCodec.PLAYER_SIZE)
	entry.halt = false
	assert_bool(SnapshotCodec.snap_player(entry).halt).is_false()
	# The server sets it from the body's goal: a body asked to move is not halted, even while it
	# still stands; one let go is, even while it still moves.
	var body := (load(PLAYER) as PackedScene).instantiate() as Player
	add_child(body)
	body.last_command = CommandDriver.walking(Vector3.LEFT)
	assert_bool(NetServer.entry_of(0, body).halt).is_false()
	body.velocity = Vector3.LEFT * 6.0
	body.last_command = PlayerCommand.new()
	assert_bool(NetServer.entry_of(0, body).halt).is_true()
	body.free()
	# A puppet drawn from a halted entry has no goal whatever its drawn motion.
	assert_bool(_drawn_goal(true).is_zero_approx()).is_true()
	assert_vector(_drawn_goal(false)).is_equal(Vector3.LEFT * 6.0)
	# Its goal over the network: none once halted; asked to move, where the snapshots head, but the
	# goal it had while they head too slowly to tell a way (a reversal's speed passes through 0).
	var asked := PlayerEntry.new()
	var kept := Vector3.LEFT * 6.0
	assert_vector(PlayerPuppet.goal_of(asked, Vector3.RIGHT * 3.0, kept)).is_equal(
		Vector3.RIGHT * 3.0
	)
	assert_vector(PlayerPuppet.goal_of(asked, Vector3.RIGHT * 0.2, kept)).is_equal(kept)
	asked.halt = true
	assert_vector(PlayerPuppet.goal_of(asked, Vector3.RIGHT * 3.0, kept)).is_equal(Vector3.ZERO)


# The goal of a puppet `PlayerPuppet.place` puts where an entry (halted or not) says, moving at
# 6 m/s to the west.
func _drawn_goal(halt: bool) -> Vector3:
	var puppet := (load(PLAYER) as PackedScene).instantiate() as Player
	puppet.make_puppet()
	add_child(puppet)
	var entry := PlayerEntry.new()
	entry.position = Vector3(0.0, 0.0, 30.0)
	entry.halt = halt
	PlayerPuppet.place(puppet, entry, Vector3.LEFT * 6.0, 1.0 / 60.0)
	var goal := puppet.motion_goal
	puppet.free()
	return goal


# Ada moves along `move` in `gait` for `frames` physics frames. Answers what her own body and Bo's
# puppet of her did: the transition clips each began (`own`, `puppet`, by their base: no foot),
# and for the puppet the steady frames (past `SETTLE`) with a stop playing, the mean largest bone
# turn a steady frame and the mean speed then.
func _run(gait: String, move: Vector3, frames: int, puppet: Player) -> Dictionary:
	var transitions := _transitions(puppet)
	var own_transitions := _transitions(_ada.player)
	var serials := [transitions.serial, own_transitions.serial]
	var begun: Array[StringName] = []
	var own_begun: Array[StringName] = []
	var skeleton := puppet.model.skeleton()
	var stop_frames := 0
	var turn_sum := 0.0
	var speed_sum := 0.0
	var steady := 0
	var last_pose := _pose(skeleton)
	for frame in frames:
		var command := CommandDriver.walking(move, Vector3.LEFT)
		command.walk = gait == "walk"
		command.sprint = gait == "sprint"
		_rig.controllers[0].next = command
		await get_tree().physics_frame
		serials[0] = _note_begun(transitions, serials[0], begun)
		serials[1] = _note_begun(own_transitions, serials[1], own_begun)
		var pose := _pose(skeleton)
		if frame >= SETTLE:
			steady += 1
			speed_sum += puppet.ground_speed()
			turn_sum += _largest_turn(last_pose, pose)
			if transitions.kind == GaitTransitions.Kind.STOP:
				stop_frames += 1
		last_pose = pose
	return {
		"name": gait if gait != "" else "stop",
		"puppet": begun,
		"own": own_begun,
		"stop_frames": stop_frames,
		"pose_turn": turn_sum / maxf(steady, 1.0),
		"speed": speed_sum / maxf(steady, 1.0),
	}


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


static func _pose(skeleton: Skeleton3D) -> Array[Quaternion]:
	var out: Array[Quaternion] = []
	for bone in skeleton.get_bone_count():
		out.append(skeleton.get_bone_pose_rotation(bone))
	return out


static func _largest_turn(a: Array[Quaternion], b: Array[Quaternion]) -> float:
	var largest := 0.0
	for bone in mini(a.size(), b.size()):
		largest = maxf(largest, rad_to_deg(a[bone].angle_to(b[bone])))
	return largest


func _put(client: NetClient, spot: Vector3, heading: float) -> void:
	_rig.server_body(client).teleport(spot, heading)
	client.player.teleport(spot, heading)
	var stand := PlayerCommand.new()
	stand.yaw = heading - PI
	_rig.controllers[_rig.clients.find(client)].next = stand

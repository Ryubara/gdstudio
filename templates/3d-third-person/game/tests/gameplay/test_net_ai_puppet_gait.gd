# Starts and stops of an AI seen on a client (gdstudio #1452). An AI's puppet (`AiReplica`) never
# steps, so, like a player's puppet before #1420, `GaitTransitions` read its goal from an empty
# command: every moving AI puppet was taken for a body asked to stop and stood in a stop clip's last
# frame while it glided along. Now its goal is where its rows head (`AiGlide.heading`) at the speed
# the row says the body is asked for (`AiRow.speed`, the server body's `goal_speed`), none at a
# speed of 0. A server AI walks, runs, sprints and stops in a game served over a loopback link; Bo's
# puppet of it begins the clips the server's body begins, keeps its gait (no stop, a pose that
# moves) while it moves, and stops as the server's body does.
extends GdUnitTestSuite

## Where the AI runs from, westwards along z = 16.6, clear of the prototype level's parts (the lane
## `test_net_puppet_gait.gd` runs a player along).
const START := Vector3(6.0, 0.0, 16.6)
const WEST := -PI / 2.0
## Where Bo stands and watches (within the full-rate radius of the whole lane).
const BO_AT := Vector3(1.0, 0.0, 13.0)
## The share of a full push of a walk (`CharacterTuning.walk_speed` over `run_speed`: 1.7 m/s).
const WALK_SHARE := 0.4
## Physics frames of each part, and the frames at its start left out of the steady checks (the
## start and the rows' delay).
const PART_FRAMES := 70
const STOP_FRAMES := 60
const SETTLE := 30
## The least mean turn of the puppet's largest-turning bone a frame, in degrees, while it moves:
## the stepped body's gait turns 10 to 19; one held in a stop clip's last frame 0.2.
const LEAST_POSE_TURN := 3.0

var _rig: OnlineRig
var _bo: NetClient


func after_test() -> void:
	_rig = null
	_bo = null


func test_an_ai_puppet_starts_keeps_its_gait_and_stops_as_its_server_body_does() -> void:
	_rig = auto_free(OnlineRig.new(true))
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_bo = await _rig.join("Bo")
	assert_object(_bo).is_not_null()
	await _rig.wait(20)
	_rig.server_body(_bo).teleport(BO_AT, PI)
	_bo.player.teleport(BO_AT, PI)
	var runner := AiNetStage.walker(START)
	runner.facing = WEST
	AiNetStage.server_map(_rig.server).add_child(runner)
	var shown := func() -> bool:
		var seen := _bo.ai_replica.puppet_of(_ai_id(runner))
		return seen != null and seen.visible
	assert_bool(await _rig.until(shown, 120)).is_true()
	await _rig.wait(20)
	var puppet := _bo.ai_replica.puppet_of(_ai_id(runner))
	assert_object(puppet).is_not_null()
	if puppet == null:
		return

	var walk := await _run("walk", runner, puppet, Vector3.LEFT, PART_FRAMES)
	var run := await _run("run", runner, puppet, Vector3.LEFT, PART_FRAMES)
	var sprint := await _run("sprint", runner, puppet, Vector3.LEFT, PART_FRAMES)
	var stop := await _run("stop", runner, puppet, Vector3.ZERO, STOP_FRAMES)

	# As it sets off, speeds up and stops, the puppet begins what the server's body begins (the
	# foot may differ: each picks it from its own gait phase). The server's body plays no start
	# from standing (#1453: it is past `standing_speed` on its first tick); the puppet may play
	# the walk's, and only the walk's.
	assert_array(walk.puppet).is_not_empty()
	if walk.puppet == [&"gds/Idle_To_Walk"] and walk.own.is_empty():
		walk.puppet = []
	for part: Dictionary in [walk, run, sprint, stop]:
		(
			assert_array(part.puppet)
			. override_failure_message(
				"%s: the puppet began %s, the server's body %s" % [part.name, part.puppet, part.own]
			)
			. is_equal(part.own)
		)
	(
		assert_array(stop.own)
		. override_failure_message("stop: the server's body began %s" % [stop.own])
		. is_equal([&"gds/Sprint_Stop"])
	)
	# While it moves on, the puppet is in its gait, not in a stop, and its pose moves.
	for part: Dictionary in [walk, run, sprint]:
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
		# Drawn at the server body's speed.
		(
			assert_float(part.speed)
			. override_failure_message(
				(
					"%s: the puppet ran %.2f m/s, the server's body %.2f"
					% [label, part.speed, part.own_speed]
				)
			)
			. is_equal_approx(part.own_speed, 0.15 * part.own_speed)
		)
	assert_float(puppet.ground_speed()).is_less(0.3)


func test_a_row_carries_the_speed_the_body_is_asked_for() -> void:
	# The row's speed byte is the body's goal speed, not its measured speed: a body let go reads 0
	# while it still moves, so a client starts its stop when the server's body does.
	var body := AiNetStage.walker(Vector3(0.0, 0.0, 30.0), Vector3.LEFT)
	add_child(body)
	body.velocity = Vector3.LEFT * 6.0
	body.last_command = CommandDriver.walking(Vector3.LEFT)
	var broadcast := AiBroadcast.new()
	assert_float(broadcast.row_of(0, body).speed).is_equal_approx(body.goal_speed, 0.001)
	assert_float(body.goal_speed).is_greater(1.0)
	body.last_command = PlayerCommand.new()
	assert_float(broadcast.row_of(0, body).speed).is_equal(0.0)
	body.free()
	# The glide's goal: none at a speed of 0; else its heading at the row's speed, and the way it
	# had while its rows head too slowly to tell one.
	var glide := AiGlide.new()
	glide.push(1, _row(Vector3.ZERO, 4.0))
	glide.step(1)
	glide.push(3, _row(Vector3(0.0, 0.0, -0.2), 4.0))
	glide.push(5, _row(Vector3(0.0, 0.0, -0.4), 4.0))
	glide.step(3)
	assert_vector(glide.goal(Vector3.ZERO)).is_equal_approx(
		Vector3.FORWARD * 4.0, Vector3.ONE * 0.001
	)
	var kept := Vector3.LEFT * 4.0
	var still := AiGlide.new()
	still.push(1, _row(Vector3.ZERO, 4.0))
	still.step(1)
	assert_vector(still.goal(kept)).is_equal(kept)
	glide.push(7, _row(Vector3(0.0, 0.0, -0.5), 0.0))
	glide.step(7)
	assert_vector(glide.goal(kept)).is_equal(Vector3.ZERO)


static func _row(spot: Vector3, speed: float) -> AiRow:
	var row := AiRow.new()
	row.position = spot
	row.speed = speed
	return row


# The AI walks along `move` in `gait` for `frames` physics frames. Answers what its server body and
# Bo's puppet of it did: the transition clips each began (`own`, `puppet`, by their base: no foot),
# and for the puppet the steady frames (past `SETTLE`) with a stop playing, the mean largest bone
# turn a steady frame and the mean speed then (and the server body's).
func _run(
	gait: String, runner: AiCharacter, puppet: Character, move: Vector3, frames: int
) -> Dictionary:
	var controller := runner.controller as AiController
	controller.sprint = gait == "sprint"
	AiNetStage.walk(runner, move, WALK_SHARE if gait == "walk" else 1.0)
	var transitions := _transitions(puppet)
	var own_transitions := _transitions(runner)
	var serials := [transitions.serial, own_transitions.serial]
	var begun: Array[StringName] = []
	var own_begun: Array[StringName] = []
	var skeleton := puppet.model.skeleton()
	var stop_frames := 0
	var turn_sum := 0.0
	var speed_sum := 0.0
	var own_speed_sum := 0.0
	var steady := 0
	var last_pose := _pose(skeleton)
	for frame in frames:
		await get_tree().physics_frame
		serials[0] = _note_begun(transitions, serials[0], begun)
		serials[1] = _note_begun(own_transitions, serials[1], own_begun)
		var pose := _pose(skeleton)
		if frame >= SETTLE:
			steady += 1
			speed_sum += puppet.ground_speed()
			own_speed_sum += runner.ground_speed()
			turn_sum += _largest_turn(last_pose, pose)
			if transitions.kind == GaitTransitions.Kind.STOP:
				stop_frames += 1
		last_pose = pose
	return {
		"name": gait,
		"puppet": begun,
		"own": own_begun,
		"stop_frames": stop_frames,
		"pose_turn": turn_sum / maxf(steady, 1.0),
		"speed": speed_sum / maxf(steady, 1.0),
		"own_speed": own_speed_sum / maxf(steady, 1.0),
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


static func _ai_id(body: AiCharacter) -> int:
	return int(body.get_meta(NetHits.AI_META, -1))

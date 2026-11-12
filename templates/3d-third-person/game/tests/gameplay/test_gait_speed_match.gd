# The gaits hold the floor at any speed the controller moves the body (gdstudio #1158): each
# gait plays at the ground speed over its clip's speed (`clips.json`, times the body's leg length
# over the reference's), the walk, the jog and the sprint share one phase, and a planted foot
# keeps its place in the world at the walk, the jog and the sprint and between them, on both of
# the template's bodies and on a body with longer legs. The body is stepped by commands and the
# tree by the same time, by hand.
#
# Before the speed matching our own clips, each played at its own pace at the tuning's speed,
# held the floor only at those three speeds: between them the feet slid, and on a taller body.
extends GdUnitTestSuite

## The furthest a planted foot may move over the floor in one contact, in metres.
const SLIDE := 0.010
## The share of a gait's contact its foot takes to roll down onto the floor, left out of the
## measure (`test_own_clips.gd` holds the clip's own feet to the same window).
const ROLL_ON := 0.25
## The fewest contacts a run must measure on each foot.
const CONTACTS := 2
const RECORDS := "res://assets/animation/own/locomotion.json"
## Each blend space's gait points, by name, and the clip each plays.
const GAITS := {
	&"ground": {&"walk": "Walk", &"run": "Jog", &"sprint": "Sprint"},
	&"crouch": {&"walk": "Crouch_Walk"},
}
## Seconds to reach a steady speed, then seconds measured.
const SETTLE := 1.0
const MEASURE := 3.0
## The runs: a name, the stick's push forward, the walk button, the sprint button, the crouch
## button, and a run speed the tuning is set to for the run (0 keeps the tuning's). The speed
## follows from the controller (`Character._target_speed`): the walk button walks at the walk speed
## times the push (at least half), a push from 0.45 runs at the run speed times the push, sprint
## is the sprint speed, a crouch the crouch speed times the push (at least half). With the
## template's `GaitSettings` the walk plays alone from 0.85 to 2.21 m/s, the walk and the jog
## blend from there to 3.2, the jog plays alone to 5.2 and blends with the sprint above.
const RUNS: Array[Array] = [
	["walk", 1.0, true, false, false, 0.0],
	["slow walk", 0.62, true, false, false, 0.0],
	["fast walk", 0.5, false, false, false, 0.0],
	["walk and jog blended, more walk", 0.65, false, false, false, 0.0],
	["walk and jog blended, more jog", 0.7125, false, false, false, 0.0],
	["jog", 1.0, false, false, false, 0.0],
	["jog and sprint blended", 1.0, false, false, false, 5.25],
	["sprint", 1.0, false, true, false, 0.0],
	["crouch walk", 1.0, false, false, true, 0.0],
	["slow crouch walk", 0.6, false, false, true, 0.0],
]

var _arena: PlayArena
var _player: Player
var _animation: CharacterAnimation
var _records: Dictionary


func before_test() -> void:
	_records = JSON.parse_string(FileAccess.get_file_as_string(RECORDS)).clips
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_player.tuning = (
		(load("res://gameplay/player/player_tuning.tres") as CharacterTuning).duplicate()
	)
	_animation = _player.get_node("Animation")
	CommandDriver.take(_player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_animation.set_throttled(true)


func after_test() -> void:
	InputSim.release_all()


func _command(run: Array) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.yaw = 0.0
	command.move = Vector2(0.0, run[1])
	command.walk = run[2]
	command.sprint = run[3]
	command.crouch = run[4]
	return command


func _space(state: StringName) -> AnimationNodeBlendSpace1D:
	var root := _animation.tree.tree_root as AnimationNodeBlendTree
	var machine := root.get_node("Locomotion") as AnimationNodeStateMachine
	return machine.get_node(state) as AnimationNodeBlendSpace1D


# Each point's weight in the blend space of `state` now, by name: the space's own linear blend
# between the two points either side of its position.
func _weights(state: StringName) -> Dictionary:
	var space := _space(state)
	var at: float = _animation.tree.get("parameters/Locomotion/%s/blend_position" % state)
	var points: Array = []
	for index in space.get_blend_point_count():
		points.append([space.get_blend_point_position(index), space.get_blend_point_name(index)])
	points.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var weights := {}
	for point: Array in points:
		weights[point[1]] = 0.0
	if at <= points[0][0]:
		weights[points[0][1]] = 1.0
		return weights
	for index in range(1, points.size()):
		if at <= points[index][0]:
			var share: float = (
				(at - points[index - 1][0]) / (points[index][0] - points[index - 1][0])
			)
			weights[points[index - 1][1]] = 1.0 - share
			weights[points[index][1]] = share
			return weights
	weights[points[-1][1]] = 1.0
	return weights


# True while the foot on `side` is down in every gait the blend of `state` weighs: past the roll
# onto it and before it leaves, at the frame each gait's clip is on now.
func _planted(state: StringName, side: String, weights: Dictionary) -> bool:
	for point: StringName in GAITS[state]:
		if weights.get(point, 0.0) < 0.02:
			continue
		var record: Dictionary = _records[GAITS[state][point]]
		var path := "parameters/Locomotion/%s/%s/Clip/current_position" % [state, point]
		var at: float = _animation.tree.get(path)
		var frame := fmod(at * 30.0, record.frames)
		var down := false
		for contact: Array in record.contacts[side]:
			var start: float = contact[0] + ROLL_ON * (contact[1] - contact[0])
			down = down or (frame >= start and frame <= contact[1])
		if not down:
			return false
	return true


# Steps the body and its tree by hand for `seconds` after `settle` seconds and returns, per foot,
# the slide of each contact: how far its ball joint moved over the floor from where it was down.
func _drive(command: PlayerCommand, settle: float, seconds: float) -> Dictionary:
	var skeleton := (_player.get_node("Model") as CharacterModel).skeleton()
	var balls := {"l": skeleton.find_bone(&"ball_l"), "r": skeleton.find_bone(&"ball_r")}
	var contacts := {"l": [], "r": []}
	var since := {"l": Vector3.INF, "r": Vector3.INF}
	var step := CommandDriver.tick_seconds()
	var first := roundi(settle / step)
	for tick in first + roundi(seconds / step):
		await get_tree().physics_frame
		_player.step(command, step)
		_animation.advance(step)
		if tick < first:
			continue
		var state := _animation.body_state()
		var weights := _weights(state)
		for side: String in balls:
			var place := (
				skeleton.global_transform * skeleton.get_bone_global_pose(balls[side]).origin
			)
			if not _planted(state, side, weights):
				since[side] = Vector3.INF
				continue
			if since[side] == Vector3.INF:
				since[side] = place
				(contacts[side] as Array).append(0.0)
			var moved: Vector3 = place - since[side]
			var slid := Vector2(moved.x, moved.z).length()
			contacts[side][-1] = maxf(contacts[side][-1], slid)
	return contacts


func _measure_runs(body: String) -> Array[String]:
	var failures: Array[String] = []
	var run_speed := _player.tuning.run_speed
	for run in RUNS:
		_player.tuning.run_speed = run[5] if run[5] > 0.0 else run_speed
		_player.teleport(Vector3.ZERO, PI)
		var contacts := await _drive(_command(run), SETTLE, MEASURE)
		var speed := _player.ground_speed()
		for side: String in contacts:
			var slid: Array = contacts[side]
			var worst: float = slid.max() if not slid.is_empty() else 0.0
			var line := (
				"%s on %s at %.2f m/s, the %s foot: %.1f mm in the worst of %d contacts"
				% [run[0], body, speed, side, worst * 1000.0, slid.size()]
			)
			print(line)
			if worst > SLIDE or slid.size() < CONTACTS:
				failures.append(line)
	_player.tuning.run_speed = run_speed
	return failures


func test_a_planted_foot_holds_the_floor_at_every_gait_and_between_them() -> void:
	var failures := await _measure_runs("female")
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()


func test_the_male_body_holds_the_floor_too() -> void:
	_player.model.variant = load(CharacterBodies.MALE) as PackedScene
	await get_tree().process_frame
	await get_tree().physics_frame
	var failures := await _measure_runs("male")
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()


func test_a_body_with_longer_legs_plays_its_gaits_slower_and_holds_the_floor() -> void:
	# The model drawn 15 % larger: its legs cover 15 % more ground a stride, so each gait plays
	# 15 % slower at the same speed and its blend points sit 15 % faster.
	_player.model.scale = Vector3.ONE * 1.15
	await get_tree().physics_frame
	var failures := await _measure_runs("a body 15 % larger")
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()

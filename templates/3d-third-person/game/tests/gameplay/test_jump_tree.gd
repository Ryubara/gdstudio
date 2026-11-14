# The jump's states pick our own clips by the body's numbers (gdstudio #1371, `JumpAnimation`):
# a standing take-off from a standstill and a run's from the foot the run is on, the air blended by
# vertical speed, a soft or a hard landing by fall speed and the landing into a run when the body
# lands asked to run, handing over to the jog at the phase it ends on. The player is stepped by
# commands and its tree advanced by hand, frame by frame; the drawn pose (after every modifier) is
# read at `skeleton_updated`, and no bone moves further in one frame through a take-off or a
# landing than the gaits themselves move it (`test_own_clip_blends.gd`'s measure).
extends GdUnitTestSuite

const RECORDS := "res://assets/animation/own/locomotion.json"
const OWN := "res://assets/animation/own/locomotion.glb"
# Parts of the bone names left out: what the hold, the IK and the root move on their own.
const SKIPPED: Array[String] = [
	"thumb", "index", "middle", "ring", "pinky", "ik_", "root", "socket"
]
# A frame's move may reach this many times the jog's own largest, and never less than `FLOOR`.
const SHARE := 1.6
const FLOOR := 0.15
# How far the lowest foot joint may be from the floor on the landing's first drawn frame (m).
const PLANTED := 0.05
# How far a bone of a run take-off's first frame may be from the jog's pose on its foot strike, as
# the test reaches it (within a twentieth of the cycle, m).
const JOIN := 0.08
# Ticks of each gait before a jump, so it plays alone.
const RUN_UP := 60

var _arena: PlayArena
var _player: Player
var _animation: CharacterAnimation
var _skeleton: Skeleton3D
var _bones: Array[int] = []
var _last: Array[Vector3] = []
var _moves: Array[float] = []
var _states: Array[StringName] = []


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_animation = _player.get_node("Animation")
	CommandDriver.take(_player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_skeleton = _player.model.skeleton()
	for bone in _skeleton.get_bone_count():
		var bone_name := String(_skeleton.get_bone_name(bone)).to_lower()
		if not SKIPPED.any(func(part: String) -> bool: return bone_name.contains(part)):
			_bones.append(bone)
	_skeleton.skeleton_updated.connect(_on_skeleton_updated)
	_animation.set_throttled(true)


func after_test() -> void:
	if (
		is_instance_valid(_skeleton)
		and _skeleton.skeleton_updated.is_connected(_on_skeleton_updated)
	):
		_skeleton.skeleton_updated.disconnect(_on_skeleton_updated)


func _on_skeleton_updated() -> void:
	var largest := 0.0
	var seen := _last.size() == _bones.size()
	_last.resize(_bones.size())
	for index in _bones.size():
		var place := _skeleton.get_bone_global_pose(_bones[index]).origin
		if seen:
			largest = maxf(largest, place.distance_to(_last[index]))
		_last[index] = place
	_moves.append(largest)
	_states.append(_animation.body_state())


func _command(push: float, jump := false, walk := false) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.move = Vector2(0.0, push)
	command.walk = walk
	command.jump = jump
	command.jump_pressed = jump
	return command


# Steps one tick of `command` and draws it.
func _tick(command: PlayerCommand) -> void:
	var step := CommandDriver.tick_seconds()
	await get_tree().physics_frame
	_player.step(command, step)
	command.clear_edges()
	_animation.advance(step)


# Steps `count` ticks of `command`; the largest frame-to-frame move of a bone over them, in metres.
func _largest(command: PlayerCommand, count: int) -> float:
	var from := _moves.size()
	for tick in count:
		await _tick(command)
	await get_tree().process_frame
	var largest := 0.0
	for index in range(from, _moves.size()):
		largest = maxf(largest, _moves[index])
	return largest


# Steps `command` until the ground gaits' phase is within a twentieth of `phase`.
func _until_phase(command: PlayerCommand, phase: float) -> void:
	for tick in 120:
		var now := _animation.gait.blend.phase(_animation.tree, CharacterAnimation.GROUND)
		if JumpAnimation._apart(now, phase) < 0.05:
			return
		await _tick(command)
	fail("the gait never reached phase %.2f" % phase)


# Steps `command` until the tree is in `state`, at most `count` ticks; the ticks it took.
func _until_state(command: PlayerCommand, state: StringName, count := 200) -> int:
	for tick in count:
		if _animation.body_state() == state:
			return tick
		await _tick(command)
	fail("the tree never went to %s (it is in %s)" % [state, _animation.body_state()])
	return count


func _jump() -> JumpAnimation:
	return _animation.gait.jump


func _check(label: String, largest: float, gait: float) -> void:
	var limit := maxf(gait * SHARE, FLOOR)
	(
		assert_float(largest)
		. override_failure_message(
			(
				"%s: a bone moved %.0f cm in one frame; the jog itself moves one %.0f cm at most"
				% [label, largest * 100.0, gait * 100.0]
			)
		)
		. is_less_equal(limit)
	)


func test_the_settings_name_our_clips_and_the_records_numbers() -> void:
	var settings := GaitSettings.new()
	var records: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RECORDS))
	assert_bool(settings.jump_choices).is_true()
	assert_str(String(settings.run_takeoff_left)).is_equal(String(CharacterClips.JUMP_START_RUN_L))
	assert_str(String(settings.run_takeoff_right)).is_equal(String(CharacterClips.JUMP_START_RUN_R))
	assert_str(String(settings.rise_clip)).is_equal(String(CharacterClips.JUMP_RISE))
	assert_str(String(settings.apex_clip)).is_equal(String(CharacterClips.JUMP_APEX))
	assert_str(String(settings.hard_land_clip)).is_equal(String(CharacterClips.LAND_HARD))
	assert_str(String(settings.run_land_clip)).is_equal(String(CharacterClips.LAND_TO_JOG))
	# The fallback is the record's own number, and a run take-off is faster than the walk.
	assert_float(settings.hard_land_speed).is_equal_approx(
		float(records.clips["Land_Hard"].fall_speed.from), 0.0001
	)
	var tuning := CharacterTuning.new()
	assert_float(settings.run_takeoff_speed).is_between(tuning.walk_speed, tuning.run_speed)
	assert_float(settings.run_land_speed).is_between(tuning.walk_speed, tuning.run_speed)
	# The take-offs join the jog's two foot strikes; the landing into a run ends on its right one.
	assert_float(JumpAnimation.join_phase(CharacterClips.JUMP_START_RUN_L, -1.0)).is_equal(0.0)
	assert_float(JumpAnimation.join_phase(CharacterClips.JUMP_START_RUN_R, -1.0)).is_equal(0.5)
	assert_vector(JumpAnimation.range_of(CharacterClips.LAND_HARD, 0.0, INF)).is_equal(
		Vector2(9.0, INF)
	)


func test_a_standing_jump_takes_off_standing_and_lands_softly() -> void:
	await _largest(_command(0.0), 30)
	await _tick(_command(0.0, true))
	var held := _command(0.0)
	held.jump = true
	assert_int(await _until_state(held, CharacterAnimation.JUMP, 5)).is_less(5)
	assert_str(String(_jump().takeoff)).is_equal(String(CharacterClips.JUMP_START))
	# The take-off plays to its end, then the air follows on the vertical speed.
	var ticks := await _until_state(held, CharacterAnimation.FALL, 60)
	var length := _animation.animation_player.get_animation(CharacterClips.JUMP_START).length
	assert_float(ticks * CommandDriver.tick_seconds()).is_greater_equal(length - 0.05)
	await _tick(held)
	var air: float = _animation.tree.get(JumpAnimation._P_AIR)
	assert_float(air).is_equal_approx(_player.velocity.y, 0.5)
	await _until_state(held, CharacterAnimation.LAND, 60)
	assert_str(String(_jump().landing)).is_equal(String(CharacterClips.LAND))
	assert_float(_jump().fall_speed).is_between(4.5, 9.0)


func test_the_air_plays_the_rise_the_top_and_the_fall_by_vertical_speed() -> void:
	var space := _animation._machine.get_node(CharacterAnimation.FALL) as AnimationNodeBlendSpace1D
	assert_object(space).is_not_null()
	var clips := {}
	for index in space.get_blend_point_count():
		var node := space.get_blend_point_node(index) as AnimationNodeAnimation
		clips[String(node.animation)] = space.get_blend_point_position(index)
	var settings := CharacterGait.settings_of(_animation)
	assert_float(clips[String(CharacterClips.JUMP_RISE)]).is_equal(settings.air_rise_speed)
	assert_float(clips[String(CharacterClips.JUMP_APEX)]).is_equal(0.0)
	assert_float(clips[String(CharacterClips.AIR)]).is_equal(-settings.air_fall_speed)


func test_a_running_jump_takes_off_from_the_foot_the_run_is_on(
	phase: float,
	clip: StringName,
	_test_parameters := [
		[0.0, CharacterClips.JUMP_START_RUN_L],
		[0.5, CharacterClips.JUMP_START_RUN_R],
		[0.2, CharacterClips.JUMP_START_RUN_L],
		[0.4, CharacterClips.JUMP_START_RUN_R],
		[0.7, CharacterClips.JUMP_START_RUN_R],
		[0.9, CharacterClips.JUMP_START_RUN_L],
	]
) -> void:
	# The jog's left foot is down from 0 to 0.3 of its cycle and its right from 0.5 to 0.8; in
	# the flights between, the foot that lands next pushes off.
	var run := _command(1.0)
	await _largest(_command(0.0), 20)
	var jog := await _largest(run, RUN_UP)
	await _until_phase(run, phase)
	var now := _animation.gait.blend.phase(_animation.tree, CharacterAnimation.GROUND)
	var jog_pose := _file_pose(CharacterClips.RUN, now)
	var takeoff := await _largest(_command(1.0, true), 3)
	assert_str(String(_jump().takeoff)).is_equal(String(clip))
	var gap := _pose_gap(jog_pose, _file_pose(clip, 0.0))
	prints(
		(
			"JUMP_TAKEOFF phase %.2f %s: its first frame %.0f mm from the jog's pose"
			% [now, clip.get_file(), gap * 1e3]
		)
	)
	# On a foot strike, the take-off's first frame is the jog's pose, bone by bone.
	if is_equal_approx(fposmod(phase, 0.5), 0.0):
		assert_float(gap).is_less(JOIN)
	takeoff = maxf(takeoff, await _largest(_command(1.0), 20))
	_check("the take-off from the jog at %.2f" % phase, takeoff, jog)


func test_a_long_fall_lands_hard_and_holds_the_body_until_it_has_settled() -> void:
	await _largest(_command(0.0), 20)
	_player.global_position = Vector3(0.0, 3.0, 0.0)
	await _until_state(_command(0.0), CharacterAnimation.LAND, 120)
	assert_str(String(_jump().landing)).is_equal(String(CharacterClips.LAND_HARD))
	assert_float(_jump().fall_speed).is_greater_equal(9.0)
	# Standing, the body is out of its landing state after `land_time`; the tree plays the
	# landing through its settle to its end, then the ground state.
	var land_time := _player.tuning.land_time
	await _largest(_command(0.0), int(land_time * 60.0) + 6)
	assert_int(_player.state).is_equal(Character.State.IDLE)
	assert_str(String(_animation.body_state())).is_equal(String(CharacterAnimation.LAND))
	var length := _animation.animation_player.get_animation(CharacterClips.LAND_HARD).length
	var still := await _largest(_command(0.0), int(length * 60.0))
	assert_str(String(_animation.body_state())).is_equal(String(CharacterAnimation.GROUND))
	_check("the hard landing's settle into the idle", still, 0.0)


func test_a_landing_asked_to_move_gives_the_body_back_at_its_control_frame() -> void:
	await _largest(_command(0.0), 20)
	_player.global_position = Vector3(0.0, 3.0, 0.0)
	await _until_state(_command(0.0), CharacterAnimation.LAND, 120)
	var record := GaitClips.record(CharacterClips.LAND_HARD)
	var control := float(record.control) / GaitClips.FPS
	var walk := _command(1.0, false, true)
	var ticks := await _until_state(walk, CharacterAnimation.GROUND, 120)
	var left_at := ticks * CommandDriver.tick_seconds()
	prints("JUMP_LAND hard, asked to walk: left at %.2f s (control %.2f s)" % [left_at, control])
	assert_float(left_at).is_less_equal(maxf(control, _player.tuning.land_time) + 0.05)


func test_a_landing_into_a_run_hands_over_to_the_jog_on_its_right_foot() -> void:
	var run := _command(1.0)
	await _largest(_command(0.0), 20)
	var jog := await _largest(run, RUN_UP)
	var held := _command(1.0, true)
	await _tick(held)
	held.jump_pressed = false
	await _until_state(held, CharacterAnimation.LAND, 120)
	assert_str(String(_jump().landing)).is_equal(String(CharacterClips.LAND_TO_JOG))
	var length := _animation.animation_player.get_animation(CharacterClips.LAND_TO_JOG).length
	var ticks := await _until_state(run, CharacterAnimation.GROUND, 60)
	# The tree draws the state it travels to on the update after (animation-tree.md#gait-fitting).
	await _tick(run)
	var phase := _animation.gait.blend.phase(_animation.tree, CharacterAnimation.GROUND)
	prints(
		(
			"JUMP_LAND into the run: %.2f s, the jog goes on at phase %.2f"
			% [ticks * CommandDriver.tick_seconds(), phase]
		)
	)
	assert_float(ticks * CommandDriver.tick_seconds()).is_between(length - 0.05, length + 0.05)
	assert_float(JumpAnimation._apart(phase, 0.5)).is_less(0.06)
	var jogging := await _largest(run, 20)
	_check("the landing into the run and the jog after it", jogging, jog)


func test_a_foot_is_on_the_floor_on_the_landing_s_first_frame(
	from_height: float, _test_parameters := [[0.0], [3.0]]
) -> void:
	await _largest(_command(0.0), 40)
	var rest := _ball_rest_height()
	var seen := {"low": INF}
	var reader := func() -> void:
		if _animation.body_state() == CharacterAnimation.LAND and seen.low == INF:
			for bone: StringName in [&"ball_l", &"ball_r", &"foot_l", &"foot_r"]:
				var at := (
					_skeleton.global_transform
					* _skeleton.get_bone_global_pose(_skeleton.find_bone(bone))
				)
				seen.low = minf(seen.low, at.origin.y)
	_skeleton.skeleton_updated.connect(reader)
	if from_height > 0.0:
		_player.global_position = Vector3(0.0, from_height, 0.0)
	else:
		await _tick(_command(0.0, true))
	var held := _command(0.0)
	held.jump = from_height <= 0.0
	await _until_state(held, CharacterAnimation.LAND, 120)
	await _largest(_command(0.0), 2)
	_skeleton.skeleton_updated.disconnect(reader)
	prints(
		(
			"JUMP_LAND from %.1f m: the lowest foot joint %.0f mm up (%.0f standing)"
			% [from_height, seen.low * 1e3, rest * 1e3]
		)
	)
	assert_float(absf(seen.low - rest)).is_less(PLANTED)


func test_with_the_choices_off_the_three_clips_play_as_before() -> void:
	var settings := GaitSettings.new()
	settings.transition_clips = GaitTransitionSet.new()
	settings.jump_choices = false
	_animation.gait_settings = settings
	var space := _animation._machine.get_node(CharacterAnimation.FALL)
	assert_object(space).is_instanceof(AnimationNodeAnimation)
	await _largest(_command(0.0), 10)
	await _largest(_command(1.0), RUN_UP)
	await _tick(_command(1.0, true))
	await _largest(_command(1.0), 3)
	var jump_node := _animation._machine.get_node(CharacterAnimation.JUMP) as AnimationNodeAnimation
	assert_str(String(jump_node.animation)).is_equal(String(_animation.jump_clip))
	assert_str(String(_jump().takeoff)).is_equal("")


func test_library_stand_ins_are_picked_by_the_settings_numbers() -> void:
	var settings := GaitSettings.new()
	settings.transition_clips = GaitTransitionSet.new()
	settings.run_takeoff_left = &"ual1/Jump_Start"
	settings.run_takeoff_right = &"ual1/Jump_Start"
	settings.rise_clip = &"ual1/Jump"
	settings.apex_clip = &"ual1/Jump"
	settings.hard_land_clip = &"ual1/Jump_Land"
	settings.run_land_clip = &"ual2/NinjaJump_Land"
	_animation.gait_settings = settings
	var jump := _jump()
	assert_float(JumpAnimation.join_phase(&"ual1/Jump_Start", 0.5)).is_equal(0.5)
	assert_str(String(jump.landing_for(10.0, 0.0))).is_equal("ual1/Jump_Land")
	assert_str(String(jump.landing_for(6.0, 4.0))).is_equal("ual2/NinjaJump_Land")
	assert_str(String(jump.landing_for(6.0, 0.0))).is_equal(String(_animation.land_clip))
	await _largest(_command(0.0), 20)
	_player.global_position = Vector3(0.0, 3.0, 0.0)
	await _until_state(_command(0.0), CharacterAnimation.LAND, 120)
	assert_str(String(jump.landing)).is_equal("ual1/Jump_Land")


# Every bone's place in the model's space with `clip` held at `share` of its length, read on a
# bare copy of the player's body.
func _file_pose(clip: StringName, share: float) -> Dictionary:
	var model: Node3D = (load(CharacterBodies.FEMALE) as PackedScene).instantiate()
	add_child(model)
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var player := AnimationPlayer.new()
	add_child(player)
	player.root_node = player.get_path_to(model)
	player.add_animation_library(&"gds", load(OWN))
	player.play(clip)
	player.seek(share * player.get_animation(clip).length, true)
	player.pause()
	var out := {}
	for bone in skeleton.get_bone_count():
		var bone_name := String(skeleton.get_bone_name(bone))
		if SKIPPED.any(func(part: String) -> bool: return bone_name.to_lower().contains(part)):
			continue
		out[bone_name] = skeleton.get_bone_global_pose(bone).origin
	player.free()
	model.free()
	return out


func _pose_gap(a: Dictionary, b: Dictionary) -> float:
	var most := 0.0
	for bone: String in a:
		most = maxf(most, (a[bone] as Vector3).distance_to(b[bone]))
	return most


# The lowest foot joint's height standing on the idle, in the world (the floor's top is 0).
func _ball_rest_height() -> float:
	var low := INF
	for bone: StringName in [&"ball_l", &"ball_r", &"foot_l", &"foot_r"]:
		var at := (
			_skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(bone))
		)
		low = minf(low, at.origin.y - _player.global_position.y)
	return low

# The parts of the gait fitting (gdstudio #1158), each an inspector choice of `GaitSettings`: the
# ground blend space's points at the clips' speeds (a stand-in clip at the tuning's), the momentum
# blend in place of the cross-fade, the transitions chosen from the controller's numbers and
# played along their travel, and the lean, built only when its poses exist. The transition clips
# do not exist yet (gdstudio #1156, #1157): the tests give the player clips of their own in a
# library `test`, with records registered in `GaitClips`. The lean poses are GDStudio's own
# (`gds/Lean_Left` and the rest, gdstudio #1159).
extends GdUnitTestSuite

const SETTINGS := "res://gameplay/character/gait_settings.tres"

const STOP := &"test/Walk_Stop"
const START := &"test/Idle_To_Walk"

var _arena: PlayArena
var _player: Player
var _animation: CharacterAnimation
var _settings: GaitSettings


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_player.tuning = (
		(load("res://gameplay/player/player_tuning.tres") as CharacterTuning).duplicate()
	)
	_animation = _player.get_node("Animation")
	_settings = (load(SETTINGS) as GaitSettings).duplicate(true)
	CommandDriver.take(_player)
	await get_tree().physics_frame
	await get_tree().physics_frame


func after_test() -> void:
	GaitClips.forget(STOP)
	GaitClips.forget(START)


func _ground() -> AnimationNodeBlendSpace1D:
	var machine := (_animation.tree.tree_root as AnimationNodeBlendTree).get_node("Locomotion")
	return (machine as AnimationNodeStateMachine).get_node("ground") as AnimationNodeBlendSpace1D


func _machine() -> AnimationNodeStateMachine:
	var root := _animation.tree.tree_root as AnimationNodeBlendTree
	return root.get_node("Locomotion") as AnimationNodeStateMachine


func _walk(push: float) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.move = Vector2(0.0, push)
	command.walk = true
	return command


# Steps the body and the tree by hand; `each` is called after every tick with its number.
func _steps(command: PlayerCommand, count: int, each := Callable()) -> void:
	var step := CommandDriver.tick_seconds()
	for tick in count:
		await get_tree().physics_frame
		_player.step(command, step)
		_animation.advance(step)
		if each.is_valid():
			each.call(tick)


# A clip of the library `test`: the walk's first pose held for `seconds`, with `record`.
func _give_clip(clip: StringName, seconds: float, record: Dictionary) -> void:
	var player: AnimationPlayer = _player.get_node("AnimationPlayer")
	if not player.has_animation_library(&"test"):
		player.add_animation_library(&"test", AnimationLibrary.new())
	var made := player.get_animation(CharacterClips.WALK).duplicate() as Animation
	made.length = seconds
	made.loop_mode = Animation.LOOP_NONE
	player.get_animation_library(&"test").add_animation(StringName(clip.get_slice("/", 1)), made)
	GaitClips.register(clip, record)


func test_the_gait_settings_defaults_are_pinned() -> void:
	var fresh := GaitSettings.new()
	var pins := {
		&"speed_match": true,
		&"pace_range": Vector2(0.4, 2.0),
		&"stretch": Vector2(0.8, 1.3),
		&"slowest_pace": 0.5,
		&"transitions": true,
		&"transition_clips": null,
		&"pivot_angle": 45.0,
		&"reversal_angle": 135.0,
		&"turn_angle": 50.0,
		&"standing_speed": 0.3,
		&"momentum_blend": true,
		&"momentum_half_life": 0.05,
		&"momentum_speed_limit": 720.0,
		&"lean": true,
		&"lean_clips": fresh.lean_clips,
		&"lean_full_at": 20.0,
		&"lean_time": 0.12,
	}
	assert_array(ExportPins.differences(fresh, pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, pins)).is_empty()
	# The template's characters share the file, with the transitions' clip names in it.
	var shared := load(SETTINGS) as GaitSettings
	assert_object(shared.transition_clips).is_not_null()
	assert_str(String(shared.transition_clips.stops[&"walk"])).is_equal("gds/Walk_Stop")


func test_the_gait_points_sit_at_the_clips_speeds_and_a_stand_in_at_the_tuning_s() -> void:
	_player.tuning.walk_speed = 2.5
	await get_tree().process_frame
	# Our walk covers 1.7 m/s: its point stays there whatever the tuning says.
	assert_float(_ground().get_blend_point_position(1)).is_equal_approx(1.7, 0.001)
	assert_float(_ground().get_blend_point_position(2)).is_equal_approx(4.0, 0.001)
	assert_float(_ground().get_blend_point_position(3)).is_equal_approx(6.5, 0.001)
	# The library's walk has no record: it sits at the tuning's walk speed and keeps its pace.
	_animation.walk_clip = CharacterClips.stand_in(CharacterClips.WALK)
	assert_float(_ground().get_blend_point_position(1)).is_equal_approx(2.5, 0.001)


func test_a_gait_plays_at_the_ground_speed_over_its_clip_s() -> void:
	_animation.set_throttled(true)
	await _steps(_walk(0.6), 60)
	var pace: float = _animation.tree.get(&"parameters/Locomotion/ground/walk/Pace/scale")
	# The walk button at 0.6 of a push walks at 1.02 m/s: the walk alone, at 1.02 / 1.7.
	assert_float(_player.ground_speed()).is_equal_approx(1.02, 0.01)
	assert_float(pace).is_equal_approx(1.02 / 1.7, 0.01)
	_settings.speed_match = false
	_animation.gait_settings = _settings
	await _steps(_walk(0.6), 2)
	pace = _animation.tree.get(&"parameters/Locomotion/ground/walk/Pace/scale")
	assert_float(pace).is_equal(1.0)


func test_the_momentum_blend_replaces_the_cross_fade_and_dies_away() -> void:
	var skeleton := _player.model.skeleton()
	var momentum := skeleton.get_child(0, true) as MomentumBlend
	assert_object(momentum).is_not_null()
	for index in _machine().get_transition_count():
		if _machine().get_transition_from(index) != &"Start":
			assert_float(_machine().get_transition(index).xfade_time).is_equal(0.0)
	_animation.set_throttled(true)
	await _steps(_walk(1.0), 40)
	var crouch := _walk(1.0)
	crouch.crouch = true
	var offsets: Array[float] = []
	await _steps(crouch, 30, func(_tick: int) -> void: offsets.append(momentum.largest_offset()))
	# The crouch walk's pose differs from the walk's: the blend starts from the drawn walk and
	# the difference is all but gone in a quarter of a second.
	assert_float(offsets.max()).is_greater(0.05)
	assert_float(offsets[15]).is_less(0.01)
	# Off, the node leaves the skeleton and the states cross-fade again.
	_settings.momentum_blend = false
	_animation.gait_settings = _settings
	await get_tree().process_frame
	assert_bool(is_instance_valid(momentum) and momentum.is_inside_tree()).is_false()


func test_a_stop_is_chosen_by_the_controller_and_played_along_its_travel() -> void:
	# Our stop: 0.6 m of travel over 18 frames, ending on both feet.
	var record := {
		"kind": "transition",
		"frames": 18,
		"seconds": 0.6,
		"travel": [[0, 0.0, 0.0], [18, 0.6, 0.0]],
		"turn": [[0, 0.0], [18, 0.0]],
		"end_foot": "both",
	}
	_give_clip(STOP, 0.6, record)
	_settings.transition_clips.stops = {&"walk": STOP, &"run": STOP, &"sprint": STOP}
	_animation.gait_settings = _settings
	_animation.set_throttled(true)
	await _steps(_walk(1.0), 60)
	assert_str(String(_animation.body_state())).is_equal("ground")
	var from := _player.global_position
	var seen: Array[Vector2] = []
	var transitions := _animation.gait.transitions
	var each := func(_tick: int) -> void:
		if transitions.is_playing():
			var covered := (_player.global_position - from).length()
			seen.append(Vector2(covered, transitions.time()))
	await _steps(PlayerCommand.new(), 50, each)
	assert_bool(seen.is_empty()).is_false()
	# Played by the ground covered, not by time: the clip is where its travel curve has come as
	# far as the body (the body stops in 0.05 m; then it plays on to its end).
	var first: Vector2 = seen[1]
	assert_float(first.y).is_equal_approx(GaitClips.time_at_travel(STOP, first.x), 0.02)
	assert_bool(transitions.is_playing()).is_false()
	assert_str(String(_animation.body_state())).is_equal("ground")


func test_a_start_hands_over_to_the_walk_and_a_push_back_leaves_a_stop() -> void:
	var record := {
		"kind": "transition",
		"frames": 15,
		"seconds": 0.5,
		"travel": [[0, 0.0, 0.0], [15, 0.4, 0.0]],
		"end_foot": "r",
	}
	_give_clip(START, 0.5, record)
	_settings.transition_clips.starts = {&"walk": START, &"run": START, &"sprint": START}
	_animation.gait_settings = _settings
	_animation.set_throttled(true)
	var states: Array[String] = []
	var each := func(_tick: int) -> void: states.append(String(_animation.body_state()))
	await _steps(_walk(1.0), 60, each)
	assert_array(states).contains(["gait_transition"])
	assert_str(states[-1]).is_equal("ground")
	# Ending on the right foot's landing, the gaits go on from half their cycle.
	assert_bool(_animation.gait.transitions.serial >= 2).is_true()


func test_no_transition_clip_leaves_the_states_as_they_were() -> void:
	_animation.set_throttled(true)
	var states: Array[String] = []
	var each := func(_tick: int) -> void: states.append(String(_animation.body_state()))
	await _steps(_walk(1.0), 40, each)
	await _steps(PlayerCommand.new(), 40, each)
	assert_array(states).not_contains(["gait_transition"])


func test_the_stop_s_foot_is_the_one_that_lands_next() -> void:
	# The walk lands on the left at 0 and on the right at half its cycle.
	assert_str(GaitTransitions.next_foot(CharacterClips.WALK, 0.1)).is_equal("r")
	assert_str(GaitTransitions.next_foot(CharacterClips.WALK, 0.7)).is_equal("l")


func test_the_lean_is_built_only_with_its_poses_and_follows_the_acceleration() -> void:
	# The template's own lean poses are in the libraries, so the player has the lean.
	assert_bool(_animation.gait.lean.is_built()).is_true()
	# A lean clip missing from the libraries leaves the tree without one.
	var missing := _settings.duplicate(true) as GaitSettings
	missing.lean_clips[&"back"] = &"test/Lean_None"
	_animation.gait_settings = missing
	assert_bool(_animation.gait.lean.is_built()).is_false()
	_animation.gait_settings = _settings
	assert_bool(_animation.gait.lean.is_built()).is_true()
	_animation.set_throttled(true)
	var leans: Array[float] = []  # A lambda keeps a copy of a float; an array is shared.
	var each := func(_tick: int) -> void: leans.append(_animation.gait.lean.amount.y)
	await _steps(_walk(1.0), 10, each)
	# Setting off (28 m/s² on the tuning, full lean at 20), the body leans forward as it speeds up
	# for a few ticks, through the lean's lag of 0.12 s.
	assert_float(leans.max()).is_greater(0.3)
	var forward: float = _animation.tree.get(&"parameters/LeanForward/add_amount")
	assert_float(forward).is_greater(0.0)

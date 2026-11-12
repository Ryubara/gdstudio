# The animation's inspector contract: every export has its default pinned, and each one is changed
# on a running player and read back from the tree it builds.
extends GdUnitTestSuite

var _arena: PlayArena
var _player: Player
var _animation: CharacterAnimation


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_player.tuning = (
		(load("res://gameplay/player/player_tuning.tres") as CharacterTuning).duplicate()
	)
	_animation = _player.get_node("Animation")
	await InputSim.ticks(get_tree(), 6)


func after_test() -> void:
	InputSim.release_all()


func _ground() -> AnimationNodeBlendSpace1D:
	var root := _animation.tree.tree_root as AnimationNodeBlendTree
	var machine := root.get_node("Locomotion") as AnimationNodeStateMachine
	return machine.get_node("ground") as AnimationNodeBlendSpace1D


func _machine() -> AnimationNodeStateMachine:
	var root := _animation.tree.tree_root as AnimationNodeBlendTree
	return root.get_node("Locomotion") as AnimationNodeStateMachine


func _clip_of(state: StringName) -> StringName:
	return (_machine().get_node(state) as AnimationNodeAnimation).animation


func test_every_export_has_its_default_pinned() -> void:
	var fresh := CharacterAnimation.new()
	var pins := {
		&"character": null,
		&"model": null,
		&"animation_player": null,
		&"tree": null,
		&"idle_clip": CharacterClips.IDLE,
		&"walk_clip": CharacterClips.WALK,
		&"run_clip": CharacterClips.RUN,
		&"sprint_clip": CharacterClips.SPRINT,
		&"jump_clip": CharacterClips.JUMP_START,
		&"air_clip": CharacterClips.AIR,
		&"land_clip": CharacterClips.LAND,
		&"crouch_idle_clip": CharacterClips.CROUCH_IDLE,
		&"crouch_walk_clip": CharacterClips.CROUCH_WALK,
		&"slide_start_clip": CharacterClips.SLIDE_START,
		&"slide_clip": CharacterClips.SLIDE,
		&"slide_exit_clip": CharacterClips.SLIDE_EXIT,
		&"push_clip": CharacterClips.PUSH,
		&"interact_clip": CharacterClips.INTERACT,
		&"hit_clip": CharacterClips.HIT,
		&"vault_clip": CharacterClips.VAULT_LOW,
		&"vault_high_clip": CharacterClips.VAULT_HIGH,
		&"vault_land_clip": CharacterClips.VAULT_LAND,
		&"vault_libraries": {},
		&"mantle_clip": CharacterClips.CLIMB_UP,
		&"mantle_high_clip": CharacterClips.CLIMB_UP,
		&"traversal_speed_range": Vector2(0.5, 2.0),
		&"prone_idle_clip": CharacterClips.PRONE_IDLE,
		&"prone_idle_pace": 1.0,
		&"crawl_clip": CharacterClips.CRAWL,
		&"crawl_clip_speed": 0.618,
		&"to_prone_clip": CharacterClips.TO_PRONE,
		&"to_crouch_clip": CharacterClips.TO_CROUCH,
		&"prone_libraries": {},
		&"carry": CharacterAnimation.Carry.HAND_ONLY,
		&"upper_body_bone": &"spine_01",
		&"aim_brace": true,
		&"aim_stance": true,
		&"aim_pitch_range": 45.0,
		&"shoot_speed": 1.6,
		&"shot_hold_time": 0.2,
		&"blend_time": 0.15,
		&"action_blend_time": 0.1,
	}
	assert_array(ExportPins.differences(fresh, pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, pins)).is_empty()
	fresh.free()


func test_a_clip_changed_while_the_game_runs_is_in_the_tree_and_the_state_goes_on() -> void:
	InputSim.key(KEY_SPACE, true)
	await InputSim.ticks(get_tree(), 4)
	InputSim.key(KEY_SPACE, false)
	var state := _animation.body_state()
	_animation.walk_clip = CharacterClips.SPRINT
	_animation.jump_clip = CharacterClips.WALK
	_animation.air_clip = CharacterClips.IDLE
	_animation.land_clip = CharacterClips.IDLE
	_animation.push_clip = CharacterClips.IDLE
	_animation.idle_clip = CharacterClips.WALK
	_animation.run_clip = CharacterClips.WALK
	_animation.sprint_clip = CharacterClips.WALK
	assert_str(_ground().get_blend_point_node(1).animation).is_equal(CharacterClips.SPRINT)
	# The idle point is the idle playing and held still under a standing aim (`AimStance`).
	var idle := _ground().get_blend_point_node(0) as AnimationNodeBlendTree
	assert_str(idle.get_node(&"Playing").animation).is_equal(CharacterClips.WALK)
	assert_str(idle.get_node(&"Held").animation).is_equal(CharacterClips.WALK)
	assert_str(_ground().get_blend_point_node(2).animation).is_equal(CharacterClips.WALK)
	assert_str(_ground().get_blend_point_node(3).animation).is_equal(CharacterClips.WALK)
	assert_str(_clip_of(CharacterAnimation.JUMP)).is_equal(CharacterClips.WALK)
	assert_str(_clip_of(CharacterAnimation.FALL)).is_equal(CharacterClips.IDLE)
	assert_str(_clip_of(CharacterAnimation.LAND)).is_equal(CharacterClips.IDLE)
	assert_str(_clip_of(CharacterAnimation.PUSH)).is_equal(CharacterClips.IDLE)
	assert_str(_animation.body_state()).is_equal(state)


func test_the_interact_and_hit_clips_are_read_when_the_action_plays() -> void:
	_animation.interact_clip = CharacterClips.HIT
	_animation.hit_clip = CharacterClips.INTERACT
	_player.hit(1.0)
	assert_str(_animation.last_action()).is_equal(String(CharacterClips.INTERACT))
	await InputSim.ticks(get_tree(), 40)
	_player.teleport(Vector3.ZERO)
	var door := load("res://gameplay/door/door.tscn").instantiate() as Door
	door.position = Vector3(0.0, 0.0, -1.2)
	_arena.add_child(door)
	await InputSim.ticks(get_tree(), 4)
	_player.interact()
	assert_str(_animation.last_action()).is_equal(String(CharacterClips.HIT))


func test_the_blend_times_reach_the_transitions_and_the_action_layer() -> void:
	_animation.blend_time = 0.4
	_animation.action_blend_time = 0.3
	var machine := _machine()
	for index in machine.get_transition_count():
		var transition := machine.get_transition(index)
		if machine.get_transition_from(index) != &"Start":
			assert_float(transition.xfade_time).is_equal_approx(0.4, 0.001)
	var root := _animation.tree.tree_root as AnimationNodeBlendTree
	var action := root.get_node("Action") as AnimationNodeOneShot
	assert_float(action.fadein_time).is_equal_approx(0.3, 0.001)
	assert_float(action.fadeout_time).is_equal_approx(0.3, 0.001)


func test_the_walk_run_and_sprint_points_follow_the_tuning_speeds() -> void:
	_player.tuning.walk_speed = 2.5
	_player.tuning.run_speed = 5.0
	_player.tuning.sprint_speed = 9.0
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(_ground().get_blend_point_position(1)).is_equal(2.5)
	assert_float(_ground().get_blend_point_position(2)).is_equal(5.0)
	assert_float(_ground().get_blend_point_position(3)).is_equal(9.0)
	assert_float(_ground().max_space).is_equal(9.0)

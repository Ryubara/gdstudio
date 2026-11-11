# The animation follows the body: each state of the player is a state of the tree, and any other
# clip of the libraries plays over it on one call.
extends GdUnitTestSuite

var _arena: PlayArena
var _player: Player
var _animation: CharacterAnimation


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_animation = _player.get_node("Animation")
	await InputSim.ticks(get_tree(), 6)


func after_test() -> void:
	InputSim.release_all()


func _locomotion_blend() -> float:
	return _animation.tree.get(&"parameters/Locomotion/ground/blend_position")


func test_standing_plays_the_ground_blend_at_zero_speed() -> void:
	assert_str(_animation.body_state()).is_equal("ground")
	assert_float(_locomotion_blend()).is_equal_approx(0.0, 0.05)


func test_the_ground_blend_follows_the_speed() -> void:
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 30)
	assert_float(_locomotion_blend()).is_equal_approx(_player.tuning.run_speed, 0.2)
	InputSim.key(KEY_SHIFT, true)
	await InputSim.ticks(get_tree(), 30)
	assert_float(_locomotion_blend()).is_equal_approx(_player.tuning.sprint_speed, 0.2)


func test_a_jump_goes_through_jump_fall_and_land_back_to_ground() -> void:
	var seen: Array[String] = []
	InputSim.key(KEY_SPACE, true)
	for tick in 120:
		await get_tree().physics_frame
		var now := String(_animation.body_state())
		if seen.is_empty() or seen[-1] != now:
			seen.append(now)
		if tick == 10:
			InputSim.key(KEY_SPACE, false)
	assert_array(seen).contains(["jump", "fall", "land"])
	(
		assert_bool(seen.find("jump") < seen.find("fall") and seen.find("fall") < seen.find("land"))
		. is_true()
	)
	await InputSim.ticks(get_tree(), 40)
	assert_str(_animation.body_state()).is_equal("ground")


func test_a_small_drop_skips_the_landing_clip() -> void:
	_player.global_position = Vector3(0.0, 0.3, 0.0)
	var seen := {}
	for _tick in 40:
		await get_tree().physics_frame
		seen[String(_animation.body_state())] = true
	assert_bool(seen.has("land")).is_false()
	assert_str(_animation.body_state()).is_equal("ground")


func test_any_clip_of_the_libraries_plays_over_the_body_once() -> void:
	var started := []
	var finished := []
	_animation.action_started.connect(func(clip: StringName) -> void: started.append(clip))
	_animation.action_finished.connect(func(clip: StringName) -> void: finished.append(clip))
	_animation.play_clip(CharacterClips.SWORD_ATTACK, 0.5)
	await InputSim.ticks(get_tree(), 6)
	assert_bool(_animation.is_acting()).is_true()
	assert_array(started).is_equal([CharacterClips.SWORD_ATTACK])
	await InputSim.ticks(get_tree(), 60)
	assert_bool(_animation.is_acting()).is_false()
	assert_array(finished).is_equal([CharacterClips.SWORD_ATTACK])


func test_a_clip_of_the_second_library_plays_too() -> void:
	_animation.play_clip(CharacterClips.OPEN_CHEST)
	await InputSim.ticks(get_tree(), 6)
	assert_bool(_animation.is_acting()).is_true()
	assert_str(_animation.last_action()).is_equal(String(CharacterClips.OPEN_CHEST))

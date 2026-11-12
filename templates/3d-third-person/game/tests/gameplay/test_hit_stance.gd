# A hit on a crouched or lying character keeps it in its stance (kit #1292): the hit clip is made
# standing, so in a low stance it plays on the upper body only and the hips stay at the stance's
# height through the stun, while a standing hit still plays on the whole body.
extends GdUnitTestSuite

## How far the hips may move up from the stance's height while the hit plays (the standing hit
## clip lifts a crouched pelvis by about 0.3 m).
const HIPS_RISE := 0.06

var _arena: PlayArena
var _player: Player
var _animation: CharacterAnimation
var _skeleton: Skeleton3D
var _pelvis := -1


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_animation = _player.get_node("Animation")
	var rig := (_player.get_node("Model") as CharacterModel).rig()
	_skeleton = rig.get_node("Armature/Skeleton3D") as Skeleton3D
	_pelvis = _skeleton.find_bone(&"pelvis")
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


func _ticks(seconds: float) -> int:
	return ceili(seconds * Engine.physics_ticks_per_second) + 2


# The pelvis's height over the character's feet, as the skeleton shows it this frame.
func _hips() -> float:
	var at := _skeleton.global_transform * _skeleton.get_bone_global_pose(_pelvis)
	return at.origin.y - _player.global_position.y


# The highest the hips reach from the hit until its clip has faded out.
func _highest_hips_while_hit() -> float:
	_player.hit(1.0)
	var highest := -INF
	var until := _player.tuning.hit_stun_time + _animation.action_blend_time + 0.1
	var waited := 0.0
	while waited < until:
		await get_tree().process_frame
		waited += get_process_delta_time()
		highest = maxf(highest, _hips())
	return highest


func _stance_hips() -> float:
	var total := 0.0
	for frame in 10:
		await get_tree().process_frame
		total += _hips()
	return total / 10.0


func _action_filtered() -> bool:
	var root := _animation.tree.tree_root as AnimationNodeBlendTree
	return (root.get_node("Action") as AnimationNodeOneShot).filter_enabled


func test_a_crouched_character_keeps_its_hips_down_while_hit() -> void:
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 40)
	assert_str(String(_animation.body_state())).is_equal(String(CharacterAnimation.CROUCH))
	var stance := await _stance_hips()
	var highest := await _highest_hips_while_hit()
	assert_bool(_player.crouching).is_true()
	(
		assert_float(highest - stance)
		. override_failure_message("crouched hips %.3f, rose to %.3f" % [stance, highest])
		. is_less(HIPS_RISE)
	)


func test_a_lying_character_keeps_its_hips_down_while_hit() -> void:
	InputSim.key(KEY_Z, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_Z, false)
	await InputSim.ticks(get_tree(), _ticks(_player.prone_tuning.enter_time) + 20)
	assert_str(String(_animation.body_state())).is_equal(String(CharacterAnimation.PRONE))
	var stance := await _stance_hips()
	var highest := await _highest_hips_while_hit()
	assert_bool(_player.prone).is_true()
	(
		assert_float(highest - stance)
		. override_failure_message("lying hips %.3f, rose to %.3f" % [stance, highest])
		. is_less(HIPS_RISE)
	)


func test_a_standing_hit_still_plays_on_the_whole_body() -> void:
	_player.hit(1.0)
	await InputSim.ticks(get_tree(), 2)
	assert_bool(_animation.is_acting()).is_true()
	assert_str(String(_animation.last_action())).is_equal(String(_animation.hit_clip))
	assert_bool(_action_filtered()).is_false()


func test_the_low_stances_play_the_hit_on_the_upper_body() -> void:
	for state: StringName in [
		CharacterAnimation.GROUND,
		CharacterAnimation.JUMP,
		CharacterAnimation.FALL,
		CharacterAnimation.LAND,
		CharacterAnimation.PUSH,
	]:
		assert_bool(HitLayer.upper_body_only(state)).override_failure_message(state).is_false()
	for state: StringName in [
		CharacterAnimation.CROUCH,
		CharacterAnimation.PRONE,
		CharacterAnimation.SLIDE_START,
		CharacterAnimation.SLIDE,
		CharacterAnimation.SLIDE_EXIT,
	]:
		assert_bool(HitLayer.upper_body_only(state)).override_failure_message(state).is_true()


func test_another_action_after_a_low_hit_plays_on_the_whole_body_again() -> void:
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 40)
	_player.hit(1.0)
	await get_tree().process_frame
	assert_bool(_action_filtered()).is_true()
	InputSim.key(KEY_C, false)
	await InputSim.ticks(get_tree(), 40)
	_animation.play_clip(_animation.interact_clip)
	await get_tree().process_frame
	assert_bool(_action_filtered()).is_false()

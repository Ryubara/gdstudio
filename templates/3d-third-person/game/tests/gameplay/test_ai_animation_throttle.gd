# The `AiAnimationThrottle` moves AI characters' animation on less often where nobody would see it:
# a Full character near the camera animates every frame as before (its tree runs itself), a
# Dormant one not at all, a far or Reduced one every few frames by the time it missed, one out of
# view holds its pose and catches up when seen; footsteps listen only near the camera; a death,
# `enabled` off or leaving the director gives the tree back; the player is never touched.
extends GdUnitTestSuite

const DRESSED := "res://gameplay/character/character_dressed.tscn"

var _arena: AiArena
var _throttle: AiAnimationThrottle
var _camera: Camera3D


func before_test() -> void:
	_arena = auto_free(AiArena.new())
	add_child(_arena)
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 1.6, 4.0)
	_arena.add_child(_camera)


func after_test() -> void:
	AudioDrain.stop_all(_arena)


# The director with a throttle that measures from the test's camera.
func _add_director() -> AiDirector:
	var director := AiDirector.new()
	director.name = "AiDirector"
	_throttle = AiAnimationThrottle.new()
	_throttle.camera = _camera
	director.add_child(_throttle)
	director.animation_throttle = _throttle
	_arena.director = director
	_arena.add_child(director)
	return director


# Frames until every new character has had its first period (it is left alone at first).
func _settle_frames() -> int:
	return AiAnimationThrottle.FIRST_FRAMES + _throttle.recheck_frames + 1


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _tree(character: Character) -> AnimationTree:
	return character.get_node("AnimationTree") as AnimationTree


func _animation(character: Character) -> CharacterAnimation:
	return character.get_node("Animation") as CharacterAnimation


# Where the body state machine's clip is now, in seconds: it moves on only when the tree does.
func _clip_time(character: Character) -> float:
	var playback := (
		_tree(character).get(&"parameters/Locomotion/playback") as AnimationNodeStateMachinePlayback
	)
	return playback.get_current_play_position()


func _clip_length(character: Character) -> float:
	var playback := (
		_tree(character).get(&"parameters/Locomotion/playback") as AnimationNodeStateMachinePlayback
	)
	return playback.get_current_length()


# The clip times of `character` over `count` frames, one a frame.
func _clip_times(character: Character, count: int) -> Array[float]:
	var times: Array[float] = []
	for _i in count:
		await get_tree().process_frame
		times.append(_clip_time(character))
	return times


func _moves(times: Array[float]) -> int:
	var moved := 0
	for index in range(1, times.size()):
		if not is_equal_approx(times[index], times[index - 1]):
			moved += 1
	return moved


func test_a_dormant_tree_does_not_advance_and_a_full_one_advances_every_frame() -> void:
	var near := _arena.add_character(Vector3(0.0, 0.0, -2.0))
	var far := _arena.add_character(Vector3(0.0, 0.0, -120.0))
	_add_director()
	await _frames(_settle_frames())
	assert_int(near.tier).is_equal(AiDirector.Tier.FULL)
	assert_int(far.tier).is_equal(AiDirector.Tier.DORMANT)
	assert_int(_throttle.period_of(near)).is_equal(1)
	assert_int(_throttle.period_of(far)).is_equal(0)
	var near_times := await _clip_times(near, 12)
	var far_times := await _clip_times(far, 12)
	assert_int(_moves(near_times)).is_equal(11)
	assert_int(_moves(far_times)).is_equal(0)
	# The near one is untouched: its tree runs itself, as the player's does.
	assert_bool(_animation(near).is_throttled()).is_false()
	assert_int(_tree(near).callback_mode_process).is_equal(
		AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	)
	assert_bool(_animation(far).is_throttled()).is_true()


func test_a_new_character_animates_as_before_for_its_first_frames() -> void:
	var far := _arena.add_character(Vector3(0.0, 0.0, -120.0))
	_add_director()
	await _frames(AiAnimationThrottle.FIRST_FRAMES - 2)
	assert_int(far.tier).is_equal(AiDirector.Tier.DORMANT)
	assert_int(_throttle.period_of(far)).is_equal(1)
	assert_bool(_animation(far).is_throttled()).is_false()
	await _frames(_throttle.recheck_frames + 2)
	assert_int(_throttle.period_of(far)).is_equal(0)


func test_a_reduced_character_in_view_advances_every_few_frames_by_the_time_it_missed() -> void:
	var director := _add_director()
	director.web_full_cap = 0
	director.desktop_full_cap = 0
	var character := _arena.add_character(Vector3(0.0, 0.0, -18.0))
	await _frames(_settle_frames())
	assert_int(character.tier).is_equal(AiDirector.Tier.REDUCED)
	assert_int(_throttle.period_of(character)).is_equal(_throttle.reduced_period)
	var start := _clip_time(character)
	var times := await _clip_times(character, 30)
	assert_int(_moves(times)).is_between(9, 10)
	# 30 frames at 60 a second: half a second of clip, give or take one period's wait.
	var moved := fposmod(times[-1] - start, _clip_length(character))
	assert_float(moved).is_between(0.5 - 3.0 / 60.0 - 0.001, 0.5 + 0.001)


func test_a_far_character_in_view_advances_every_far_period() -> void:
	_add_director()
	# Full (24 m from the player's body), 28 m from the camera.
	var character := _arena.add_character(Vector3(0.0, 0.0, -24.0))
	await _frames(_settle_frames())
	assert_int(character.tier).is_equal(AiDirector.Tier.FULL)
	assert_int(_throttle.period_of(character)).is_equal(_throttle.far_period)
	var times := await _clip_times(character, 36)
	assert_int(_moves(times)).is_between(5, 6)


func test_an_unseen_character_holds_its_pose_and_catches_up_when_seen() -> void:
	_add_director()
	# Past the near distance, in view, then behind the camera once it turns.
	var character := _arena.add_character(Vector3(0.0, 0.0, -16.0))
	await _frames(_settle_frames())
	assert_int(_throttle.period_of(character)).is_equal(1)
	_camera.rotation.y = PI
	await _frames(_throttle.recheck_frames + 1)
	assert_int(_throttle.period_of(character)).is_equal(0)
	var held := await _clip_times(character, 10)
	assert_int(_moves(held)).is_equal(0)
	# Held where it was, not started over (the tree's state machine kept its place).
	assert_float(held[0]).is_greater(0.1)
	_camera.rotation.y = 0.0
	await _frames(_throttle.recheck_frames)
	assert_int(_throttle.period_of(character)).is_equal(1)
	# Seen again it moved on by the time it missed, `max_catch_up` at most, and runs itself again.
	var caught := fposmod(_clip_time(character) - held[-1], _clip_length(character))
	assert_float(caught).is_between(_throttle.max_catch_up - 0.001, _throttle.max_catch_up + 0.1)
	assert_bool(_animation(character).is_throttled()).is_false()


func test_footsteps_listen_only_near_the_camera_and_every_frame() -> void:
	var near := _arena.add_character(Vector3(0.0, 0.0, -2.0))
	var far := _arena.add_character(Vector3(0.0, 0.0, -20.0))
	_add_director()
	await _frames(_settle_frames())
	assert_bool(near.get_node("Footsteps").is_processing()).is_true()
	assert_bool(far.get_node("Footsteps").is_processing()).is_false()


func test_a_throttled_tree_hands_the_skeleton_and_the_hand_over_and_a_death_gives_them_back(
) -> void:
	var character := _arena.add_character(Vector3(0.0, 0.0, -120.0))
	_add_director()
	await _frames(_settle_frames())
	var skeleton := character.model.skeleton()
	var hold := character.get_node("WeaponHold") as WeaponHold
	assert_int(skeleton.modifier_callback_mode_process).is_equal(
		Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	)
	assert_bool(hold.is_processing()).is_false()
	assert_bool(character.ragdoll_body.pose_velocity).is_false()
	character.die()
	await _frames(2)
	assert_bool(_animation(character).is_throttled()).is_false()
	assert_int(_throttle.period_of(character)).is_equal(1)
	assert_int(skeleton.modifier_callback_mode_process).is_equal(
		Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
	)
	assert_bool(hold.is_processing()).is_true()
	assert_bool(character.ragdoll_body.pose_velocity).is_true()


func test_turning_it_off_or_leaving_the_director_gives_the_tree_back() -> void:
	var first := _arena.add_character(Vector3(0.0, 0.0, -120.0))
	var second := _arena.add_character(Vector3(2.0, 0.0, -120.0))
	_add_director()
	await _frames(_settle_frames())
	assert_bool(_animation(first).is_throttled()).is_true()
	_throttle.enabled = false
	assert_bool(_animation(first).is_throttled()).is_false()
	assert_bool(_animation(second).is_throttled()).is_false()
	_throttle.enabled = true
	assert_bool(_animation(second).is_throttled()).is_true()
	_arena.director.unregister(second)
	assert_bool(_animation(second).is_throttled()).is_false()
	assert_int(_throttle.period_of(second)).is_equal(-1)
	assert_int(_tree(second).callback_mode_process).is_equal(
		AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	)


func test_without_a_throttle_every_character_animates_every_frame() -> void:
	var far := _arena.add_character(Vector3(0.0, 0.0, -120.0))
	_arena.add_director()
	await _frames(16)
	assert_int(far.tier).is_equal(AiDirector.Tier.DORMANT)
	assert_bool(_animation(far).is_throttled()).is_false()
	assert_int(_moves(await _clip_times(far, 6))).is_equal(5)


func test_a_dressed_character_alone_is_never_throttled() -> void:
	var character: Character = (load(DRESSED) as PackedScene).instantiate()
	character.position = Vector3(0.0, 0.0, -2.0)
	_arena.add_child(character)
	await _frames(6)
	assert_bool(_animation(character).is_throttled()).is_false()
	assert_int(_tree(character).callback_mode_process).is_equal(
		AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	)
	assert_int(character.model.skeleton().modifier_callback_mode_process).is_equal(
		Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
	)
	assert_bool(character.get_node("Footsteps").is_processing()).is_true()

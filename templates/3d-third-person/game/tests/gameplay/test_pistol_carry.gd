# How the character carries the pistol: off aim and fire it sits in one hand and the arms and the
# spine follow the locomotion clip (the pistol layer's weight on them is 0, only the gripping
# hand takes the grip pose); aiming and firing bring the full layer back. Read from the tree of a
# running player, with simulated input.
extends GdUnitTestSuite

const SKELETON := "Armature/Skeleton3D"
## Bones that must follow the locomotion clip while the pistol only sits in the hand.
const FREE_BONES: Array[StringName] = [
	&"pelvis",
	&"spine_01",
	&"spine_02",
	&"spine_03",
	&"neck_01",
	&"Head",
	&"clavicle_r",
	&"upperarm_r",
	&"lowerarm_r",
	&"clavicle_l",
	&"upperarm_l",
	&"lowerarm_l",
	&"hand_l",
	&"thigh_r",
	&"foot_l",
]
## Bones of the gripping hand: the wrist and the fingers.
const GRIP_BONES: Array[StringName] = [
	&"hand_r",
	&"thumb_01_r",
	&"index_01_r",
	&"index_03_r",
	&"middle_02_r",
	&"pinky_01_r",
]

var _arena: PlayArena
var _player: Player
var _animation: PlayerAnimation
var _camera: Camera3D


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_player.tuning = (load("res://gameplay/player/player_tuning.tres") as PlayerTuning).duplicate()
	_animation = _player.get_node("Animation")
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(_camera)
	_camera.make_current()
	await InputSim.ticks(get_tree(), 6)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


# The tree is driven per render frame and a rebuild can make the physics catch up first, so wait
# for a few render frames before reading what a changed export did.
func _settle() -> void:
	for _frame in 3:
		await get_tree().process_frame


func _root() -> AnimationNodeBlendTree:
	return _animation.tree.tree_root as AnimationNodeBlendTree


# How much of a bone the pistol layer drives: the holding pose (`Armed`) and the aim (`Aim`), each
# its blend amount where the node's filter takes the bone and 0 where it does not.
func _layer(bone: StringName, layer: String) -> float:
	var node := _root().get_node(layer) as AnimationNodeBlend2
	var path := NodePath("%s:%s" % [SKELETON, bone])
	if node.filter_enabled and not node.is_path_filtered(path):
		return 0.0
	return _animation.tree.get(&"parameters/%s/blend_amount" % layer)


func _assert_follows_the_clip(label: String) -> void:
	for bone in FREE_BONES:
		var held := _layer(bone, "Armed")
		var aimed := _layer(bone, "Aim")
		assert_float(held).override_failure_message("%s: %s held" % [label, bone]).is_equal(0.0)
		assert_float(aimed).override_failure_message("%s: %s aim" % [label, bone]).is_equal(0.0)


func _assert_grip_only(label: String) -> void:
	for bone in GRIP_BONES:
		var held := _layer(bone, "Armed")
		assert_float(held).override_failure_message("%s: %s grip" % [label, bone]).is_equal(1.0)


func test_standing_with_the_pistol_the_arms_follow_the_clip_and_the_hand_grips() -> void:
	assert_object(_player.weapon).is_not_null()
	_assert_follows_the_clip("stand")
	_assert_grip_only("stand")


func test_walking_jogging_and_sprinting_with_the_pistol_follow_the_clip() -> void:
	var gaits := {
		"walk": [KEY_W, KEY_X],
		"jog": [KEY_W],
		"sprint": [KEY_W, KEY_SHIFT],
	}
	for gait: String in gaits:
		for code: Key in gaits[gait]:
			InputSim.key(code, true)
		await InputSim.ticks(get_tree(), 40)
		assert_float(_player.ground_speed()).override_failure_message(gait).is_greater(1.0)
		assert_str(String(_animation.body_state())).is_equal("ground")
		_assert_follows_the_clip(gait)
		_assert_grip_only(gait)
		InputSim.release_all()
		await InputSim.ticks(get_tree(), 30)


func test_crouch_walking_and_jumping_with_the_pistol_follow_the_clip() -> void:
	InputSim.key(KEY_C, true)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 40)
	assert_str(String(_animation.body_state())).is_equal("crouch")
	_assert_follows_the_clip("crouch walk")
	_assert_grip_only("crouch walk")
	InputSim.release_all()
	await InputSim.ticks(get_tree(), 40)
	InputSim.key(KEY_W, true)
	InputSim.key(KEY_SPACE, true)
	await InputSim.ticks(get_tree(), 8)
	assert_bool(_player.is_on_floor()).is_false()
	_assert_follows_the_clip("jump")
	_assert_grip_only("jump")


func test_aiming_brings_the_whole_layer_back_and_letting_go_takes_it_away() -> void:
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), 30)
	for bone in FREE_BONES.slice(1):
		if bone == &"thigh_r" or bone == &"foot_l" or bone == &"pelvis":
			continue
		assert_float(_layer(bone, "Aim")).override_failure_message(String(bone)).is_equal(1.0)
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)
	await InputSim.ticks(get_tree(), 30)
	_assert_follows_the_clip("after aiming")
	_assert_grip_only("after aiming")


func test_firing_brings_the_aim_layer_back_too() -> void:
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 30)
	assert_float(_layer(&"upperarm_r", "Aim")).is_equal(1.0)
	assert_float(_layer(&"spine_02", "Aim")).is_equal(1.0)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	# Long enough for the arm to come down whether or not aiming is kept after a shot.
	await InputSim.ticks(get_tree(), 80)
	_assert_follows_the_clip("after firing")


func test_the_held_pose_carry_holds_the_whole_upper_body_as_before() -> void:
	_animation.carry = PlayerAnimation.Carry.HELD_POSE
	await _settle()
	for bone in [&"spine_01", &"spine_03", &"upperarm_r", &"lowerarm_l", &"hand_r", &"Head"]:
		assert_float(_layer(bone, "Armed")).override_failure_message(String(bone)).is_equal(1.0)
	for bone in [&"pelvis", &"thigh_l", &"foot_r"]:
		assert_float(_layer(bone, "Armed")).override_failure_message(String(bone)).is_equal(0.0)
	_animation.carry = PlayerAnimation.Carry.HAND_ONLY
	await _settle()
	_assert_follows_the_clip("back to hand only")


func test_the_grip_bones_choose_which_hands_take_the_grip() -> void:
	_animation.grip_bones = [&"hand_r", &"hand_l"]
	await _settle()
	for bone in [&"hand_r", &"index_02_r", &"hand_l", &"thumb_02_l", &"pinky_03_l"]:
		assert_float(_layer(bone, "Armed")).override_failure_message(String(bone)).is_equal(1.0)
	for bone in [&"lowerarm_l", &"lowerarm_r", &"spine_02"]:
		assert_float(_layer(bone, "Armed")).override_failure_message(String(bone)).is_equal(0.0)
	_animation.grip_bones = [&"hand_r", &"no_such_bone"]
	await _settle()
	assert_float(_layer(&"hand_r", "Armed")).is_equal(1.0)
	assert_float(_layer(&"hand_l", "Armed")).is_equal(0.0)


func test_the_grip_clip_is_the_one_the_tree_plays_on_the_hand() -> void:
	var clip := _root().get_node("PistolIdle") as AnimationNodeAnimation
	assert_str(String(clip.animation)).is_equal(String(CharacterClips.PISTOL_IDLE))
	_animation.grip_clip = CharacterClips.PISTOL_AIM
	clip = _root().get_node("PistolIdle") as AnimationNodeAnimation
	assert_str(String(clip.animation)).is_equal(String(CharacterClips.PISTOL_AIM))


func test_an_unarmed_player_carries_nothing_in_either_carry() -> void:
	_player.weapon = null
	for mode in [PlayerAnimation.Carry.HAND_ONLY, PlayerAnimation.Carry.HELD_POSE]:
		_animation.carry = mode
		await _settle()
		assert_float(_layer(&"hand_r", "Armed")).is_equal(0.0)
		assert_float(_layer(&"spine_01", "Armed")).is_equal(0.0)
		assert_float(_layer(&"hand_r", "Aim")).is_equal(0.0)


# A shot fired with no aim: the arm goes up for the shot, stays up for the shot hold and comes down
# at the speed of the aim, and no render frame moves it further than that speed allows (the tree
# is driven per render frame, and a physics burst can make one of them long).
func test_a_shot_without_aiming_keeps_the_arm_up_for_the_hold_and_never_pops() -> void:
	_animation.shot_hold_time = 0.3
	var aim_time := _player.tuning.aim_pose_time
	assert_float(_animation.pistol_weights().y).is_equal(0.0)
	assert_object(_player.weapon.fire()).is_not_null()
	var started := Time.get_ticks_msec()
	var last := 0.0
	var worst := 0.0
	var peak := 0.0
	var up_since := -1.0
	var up_until := -1.0
	var delta := 0.0
	while Time.get_ticks_msec() - started < 1200:
		# `process_frame` comes before the nodes' `_process`, so the value read here was set by the
		# frame before, with the delta that frame had.
		await get_tree().process_frame
		var now := _animation.pistol_weights().y
		var seconds := (Time.get_ticks_msec() - started) / 1000.0
		worst = maxf(worst, absf(now - last) - delta / aim_time)
		delta = get_process_delta_time()
		last = now
		peak = maxf(peak, now)
		if now >= 0.99:
			up_since = seconds if up_since < 0.0 else up_since
			up_until = seconds
	assert_float(peak).is_equal(1.0)
	# The step of a frame never goes past the speed of the aim (a few thousandths of rounding).
	assert_float(worst).is_less(0.01)
	assert_float(up_until - up_since).is_greater(0.1)
	assert_float(_animation.pistol_weights().y).is_equal(0.0)


func test_without_a_shot_hold_a_shot_leaves_the_arm_down() -> void:
	_animation.shot_hold_time = 0.0
	assert_object(_player.weapon.fire()).is_not_null()
	for _frame in 20:
		await get_tree().process_frame
		assert_float(_animation.pistol_weights().y).is_equal(0.0)


# A tap of the fire button with no aim shoots, and the arm comes all the way up for it.
func test_a_tapped_shot_without_aim_raises_the_arm_for_the_shot() -> void:
	var shots: Array[Projectile] = []
	_player.weapon.fired.connect(func(shot: Projectile) -> void: shots.append(shot))
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	var peak := 0.0
	for frame in 40:
		await get_tree().process_frame
		if frame == 6:
			InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
		peak = maxf(peak, _animation.pistol_weights().y)
	assert_array(shots).has_size(1)
	assert_float(peak).is_equal(1.0)

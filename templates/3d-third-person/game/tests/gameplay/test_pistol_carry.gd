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
	await InputSim.ticks(get_tree(), 30)
	_assert_follows_the_clip("after firing")

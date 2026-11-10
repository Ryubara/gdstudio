# The animation tree's crouch state and its pistol layer on the upper body: the crouch idle and
# walk blend by speed, the holding pose is on the arms and spine but not on the legs, the aim pose
# follows the camera's pitch and a shot plays the recoil. Read from the real tree of a running
# player.
extends GdUnitTestSuite

var _arena: PlayArena
var _player: Player
var _animation: PlayerAnimation
var _camera: Camera3D


func before_test() -> void:
	# Another suite may have left a button down (a base suite leaves `fire` pressed).
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


func test_the_crouch_state_blends_the_crouch_idle_into_the_crouch_walk_by_speed() -> void:
	var machine := _root().get_node("Locomotion") as AnimationNodeStateMachine
	var space := machine.get_node("crouch") as AnimationNodeBlendSpace1D
	assert_int(space.get_blend_point_count()).is_equal(2)
	assert_float(space.get_blend_point_position(0)).is_equal(0.0)
	assert_float(space.get_blend_point_position(1)).is_equal(_player.tuning.crouch_speed)
	(
		assert_str(String((space.get_blend_point_node(0) as AnimationNodeAnimation).animation))
		. is_equal(String(CharacterClips.CROUCH_IDLE))
	)
	(
		assert_str(String((space.get_blend_point_node(1) as AnimationNodeAnimation).animation))
		. is_equal(String(CharacterClips.CROUCH_WALK))
	)
	# The machine links every state to every other, the crouch included.
	assert_bool(machine.has_transition(&"ground", &"crouch")).is_true()
	assert_bool(machine.has_transition(&"crouch", &"jump")).is_true()


func test_the_crouch_walk_point_follows_the_tuning() -> void:
	_player.tuning.crouch_speed = 2.2
	for _frame in 4:
		await get_tree().process_frame
	var machine := _root().get_node("Locomotion") as AnimationNodeStateMachine
	var space := machine.get_node("crouch") as AnimationNodeBlendSpace1D
	assert_float(space.get_blend_point_position(1)).is_equal_approx(2.2, 0.001)
	assert_float(space.max_space).is_equal_approx(2.2, 0.001)


func test_crouching_travels_the_body_to_the_crouch_state_and_standing_back() -> void:
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 20)
	assert_str(String(_animation.body_state())).is_equal("crouch")
	InputSim.key(KEY_C, false)
	await InputSim.ticks(get_tree(), 40)
	assert_str(String(_animation.body_state())).is_equal("ground")


func test_the_pistol_layer_holds_the_upper_body_and_leaves_the_legs() -> void:
	for layer in ["Armed", "Aim", "Shoot"]:
		var node := _root().get_node(layer) as AnimationNode
		assert_bool(node.filter_enabled).override_failure_message(layer).is_true()
		assert_bool(node.is_path_filtered(NodePath("Armature/Skeleton3D:spine_01"))).is_true()
		assert_bool(node.is_path_filtered(NodePath("Armature/Skeleton3D:hand_r"))).is_true()
		assert_bool(node.is_path_filtered(NodePath("Armature/Skeleton3D:index_01_r"))).is_true()
		assert_bool(node.is_path_filtered(NodePath("Armature/Skeleton3D:Head"))).is_true()
		assert_bool(node.is_path_filtered(NodePath("Armature/Skeleton3D:pelvis"))).is_false()
		assert_bool(node.is_path_filtered(NodePath("Armature/Skeleton3D:thigh_l"))).is_false()
		assert_bool(node.is_path_filtered(NodePath("Armature/Skeleton3D:foot_r"))).is_false()


func test_an_armed_player_holds_the_pistol_and_the_aim_follows_the_arm() -> void:
	await InputSim.ticks(get_tree(), 4)
	assert_float(_animation.pistol_weights().x).is_equal(1.0)
	assert_float(_animation.pistol_weights().y).is_equal(0.0)
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await InputSim.ticks(get_tree(), 30)
	assert_float(_animation.pistol_weights().y).is_equal(1.0)
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await InputSim.ticks(get_tree(), 30)
	assert_float(_animation.pistol_weights().y).is_equal(0.0)


func test_an_unarmed_player_holds_nothing() -> void:
	_player.weapon = null
	await InputSim.ticks(get_tree(), 6)
	assert_float(_animation.pistol_weights().x).is_equal(0.0)
	assert_float(_animation.pistol_weights().y).is_equal(0.0)


func test_the_aim_pose_follows_the_pitch_of_the_camera() -> void:
	_camera.look_at_from_position(Vector3(0.0, 1.3, 3.0), Vector3(0.0, 8.0, -3.0))
	await InputSim.ticks(get_tree(), 6)
	assert_float(_animation.aim_pitch()).is_equal_approx(45.0, 0.01)
	_camera.look_at_from_position(Vector3(0.0, 1.3, 3.0), Vector3(0.0, 1.3, -10.0))
	await InputSim.ticks(get_tree(), 6)
	assert_float(_animation.aim_pitch()).is_equal_approx(0.0, 0.01)
	_camera.look_at_from_position(Vector3(0.0, 1.3, 3.0), Vector3(0.0, -2.0, -2.0))
	await InputSim.ticks(get_tree(), 6)
	assert_float(_animation.aim_pitch()).is_less(-20.0)
	_animation.aim_pitch_range = 20.0
	await InputSim.ticks(get_tree(), 6)
	assert_float(_animation.aim_pitch()).is_equal_approx(-20.0, 0.01)


func test_a_shot_plays_the_recoil_over_the_aim() -> void:
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await InputSim.ticks(get_tree(), 30)
	var path := &"parameters/Shoot/active"
	assert_bool(_animation.tree.get(path)).is_false()
	_player.weapon.fire()
	await InputSim.ticks(get_tree(), 3)
	assert_bool(_animation.tree.get(path)).is_true()
	await InputSim.ticks(get_tree(), 60)
	assert_bool(_animation.tree.get(path)).is_false()


func test_the_pistol_clips_are_the_ones_the_template_names() -> void:
	for clip: StringName in [
		CharacterClips.PISTOL_IDLE,
		CharacterClips.PISTOL_AIM,
		CharacterClips.PISTOL_AIM_UP,
		CharacterClips.PISTOL_AIM_DOWN,
		CharacterClips.PISTOL_SHOOT,
		CharacterClips.CROUCH_IDLE,
		CharacterClips.CROUCH_WALK,
	]:
		(
			assert_bool(_animation.animation_player.has_animation(clip))
			. override_failure_message(String(clip))
			. is_true()
		)
		assert_bool(CharacterClips.ALL.has(clip)).is_true()


func test_a_clip_set_in_the_inspector_replaces_the_one_in_the_tree() -> void:
	_animation.shoot_clip = CharacterClips.PUNCH
	_animation.crouch_walk_clip = CharacterClips.WALK
	var shoot := _root().get_node("ShootClip") as AnimationNodeAnimation
	assert_str(String(shoot.animation)).is_equal(String(CharacterClips.PUNCH))
	var machine := _root().get_node("Locomotion") as AnimationNodeStateMachine
	var space := machine.get_node("crouch") as AnimationNodeBlendSpace1D
	(
		assert_str(String((space.get_blend_point_node(1) as AnimationNodeAnimation).animation))
		. is_equal(String(CharacterClips.WALK))
	)

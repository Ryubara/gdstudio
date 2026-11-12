# The inspector contract of the rifle's hold (kit #889, the template checklist's item 12): every
# export of `TwoHandHold` and of `HandPoseModifier` with its default, so a new export fails here
# until its default is pinned, and a stance export changed while the game runs moves the rifle.
extends GdUnitTestSuite

const HOLD_PINS := {
	&"character": null,
	&"aim_pocket": Vector3(-0.124, 0.12, 0.04),
	&"low_pocket": Vector3(-0.114, 0.06, 0.04),
	&"low_pitch": 35.0,
	&"low_yaw": 20.0,
	&"chest_turn": -30.0,
	&"arm_stretch": 0.97,
	&"pull_limit": 0.12,
	&"pitch_limit": 60.0,
	&"raise_time": 0.15,
	&"shot_hold_time": 0.6,
	&"stow_pocket": Vector3(-0.114, 0.0, 0.04),
	&"stow_pitch": 55.0,
	&"stow_yaw": 30.0,
	&"kick_distance": 0.02,
	&"kick_degrees": 2.0,
	&"kick_recover_time": 0.08,
	&"grip_pose": null,
	&"trigger_pose": null,
	&"trigger_way": null,
	&"support_pose": null,
	&"open_pose": null,
	&"magazine_pose": null,
	&"fingers_far_distance": 10.0,
	&"reload_belt": Vector3(0.17, -0.3, 0.1),
	&"magazine_well": 0.1,
	&"reload_clearance": Vector3(0.0, -0.07, 0.035),
	&"magazine_approach": Vector3(0.0, 0.0, 0.07),
	&"reload_leave": Vector2(0.0, 0.18),
	&"reload_out": Vector2(0.2, 0.42),
	&"reload_in": Vector2(0.48, 0.62),
	&"reload_return": Vector2(0.66, 0.86),
	&"magazine": NodePath(),
	&"magazine_far": NodePath(),
	&"fits": [] as Array[HoldFit],
	&"chest_bone": &"spine_03",
	&"spine_bones": [&"spine_01", &"spine_02", &"spine_03"] as Array[StringName],
	&"right_arm": [&"upperarm_r", &"lowerarm_r", &"hand_r"] as Array[StringName],
	&"left_arm": [&"upperarm_l", &"lowerarm_l", &"hand_l"] as Array[StringName],
}
const MODIFIER_PINS := {
	&"pose": null,
	&"second": null,
	&"second_weight": 0.0,
	&"second_way": [] as Array[HandPose],
	&"open": null,
	&"open_weight": 0.0,
	&"open_first": [] as Array[StringName],
	&"open_first_share": 0.5,
	&"open_together": false,
	&"swing_bone": &"",
	&"swing_degrees": 0.0,
}


func test_every_export_of_the_two_hand_hold_has_its_pinned_default() -> void:
	var hold: TwoHandHold = auto_free(TwoHandHold.new())
	assert_array(ExportPins.differences(hold, HOLD_PINS)).is_empty()
	assert_array(ExportPins.wrong_values(hold, HOLD_PINS)).is_empty()


func test_every_export_of_the_hand_pose_modifier_has_its_pinned_default() -> void:
	var modifier: HandPoseModifier = auto_free(HandPoseModifier.new())
	assert_array(ExportPins.differences(modifier, MODIFIER_PINS)).is_empty()
	assert_array(ExportPins.wrong_values(modifier, MODIFIER_PINS)).is_empty()


func test_the_rifles_scene_lists_the_male_bodys_fit() -> void:
	var hold := (
		(load("res://gameplay/weapon/rifle_held.tscn") as PackedScene).instantiate() as TwoHandHold
	)
	assert_int(hold.fits.size()).is_equal(1)
	assert_str(hold.fits[0].body).is_equal(CharacterBodies.MALE.get_file())
	hold.free()


func test_a_stance_export_changed_while_it_runs_moves_the_rifle() -> void:
	var holder: Node3D = auto_free(Node3D.new())
	add_child(holder)
	var stage := RifleStage.make_rifle(holder, "female", false)
	var hold := stage.hold as TwoHandHold
	stage.pose_rifle(CharacterClips.IDLE, 0.0, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var first := stage.rifle.global_basis.x
	hold.low_pitch += 20.0
	stage.pose_rifle(CharacterClips.IDLE, 0.0, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var turned := rad_to_deg(first.angle_to(stage.rifle.global_basis.x))
	# The barrel is also turned `low_yaw` aside, so 20 degrees of pitch turn it a little less.
	assert_float(turned).is_between(17.0, 20.5)
	stage.free()

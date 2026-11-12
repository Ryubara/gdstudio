# The four characters a level places (kit #969): each is an inherited `ai_character.tscn` with
# its profile, its behaviour set and its look, opens with no configuration warning and no empty
# slot, holds the pistol in its hand (the civilian goes unarmed), shows the male mannequin through
# the `Model` slot's variant where it says so, and takes a profile edited while it runs at its
# next think.
extends GdUnitTestSuite

const SCENES := {
	"grunt": "res://gameplay/ai/characters/enemy_grunt.tscn",
	"shooter": "res://gameplay/ai/characters/enemy_shooter.tscn",
	"ally": "res://gameplay/ai/characters/ally.tscn",
	"civilian": "res://gameplay/ai/characters/civilian.tscn",
}
## What makes each kind: its profile file, its set, its faction, its model and whether it is armed.
const KINDS := {
	"grunt": ["grunt.tres", "hostile_guard.tres", &"enemy", "form_male.glb", true],
	"shooter": ["shooter.tres", "hostile_guard.tres", &"enemy", "form_male.glb", true],
	"ally": ["ally.tres", "friendly_ally.tres", &"ally", "form_female.glb", true],
	"civilian": ["civilian.tres", "civilian.tres", &"civilian", "form_female.glb", false],
}
## How far the pistol's seat may be from the right hand's bone, metres.
const SEAT_TOLERANCE := 0.02

var _arena: BehaviourArena


func before_test() -> void:
	_arena = auto_free(BehaviourArena.new())
	add_child(_arena)
	_arena.build()
	await _arena.settle()


func after_test() -> void:
	AudioDrain.stop_all(_arena)


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


# Every node of `root` whose script lists configuration warnings, with the warnings it lists.
func _warnings_of(root: Node) -> Array[String]:
	var found: Array[String] = []
	for node: Node in [root] + root.find_children("*", "", true, false):
		if node.has_method(&"_get_configuration_warnings"):
			for line: String in node.call(&"_get_configuration_warnings"):
				found.append("%s: %s" % [root.get_path_to(node), line])
	return found


func test_the_model_slots_variant_is_pinned_empty() -> void:
	var slot: CharacterModel = auto_free(CharacterModel.new())
	var pins := {&"variant": null, &"body_layers": 1 << 1}
	assert_array(ExportPins.differences(slot, pins)).is_empty()
	assert_array(ExportPins.wrong_values(slot, pins)).is_empty()


func test_each_scene_inherits_the_ai_character_with_its_profile_set_and_faction() -> void:
	for kind: String in SCENES:
		var state := (load(SCENES[kind]) as PackedScene).get_state()
		var base := state.get_node_instance(0)
		(
			assert_str(base.resource_path if base != null else "")
			. override_failure_message("%s does not inherit ai_character.tscn" % kind)
			. is_equal("res://gameplay/ai/ai_character.tscn")
		)
		var character := auto_free((load(SCENES[kind]) as PackedScene).instantiate()) as AiCharacter
		var wanted: Array = KINDS[kind]
		assert_str(character.profile.resource_path.get_file()).is_equal(wanted[0])
		var mind := character.brain as AiBrain
		assert_str(mind.behaviour.resource_path.get_file()).is_equal(wanted[1])
		assert_str(String(character.profile.faction)).is_equal(String(wanted[2]))


func test_each_scene_opens_with_no_warning_and_no_empty_slot() -> void:
	for kind: String in SCENES:
		var character := (load(SCENES[kind]) as PackedScene).instantiate() as AiCharacter
		_arena.add_child(character)
		await _ticks(2)
		(
			assert_array(_warnings_of(character))
			. override_failure_message("%s warns: %s" % [kind, _warnings_of(character)])
			. is_empty()
		)
		for slot: StringName in [
			&"profile",
			&"debug_label",
			&"senses",
			&"navigator",
			&"task_runner",
			&"brain",
			&"controller"
		]:
			(
				assert_object(character.get(slot))
				. override_failure_message("%s has no %s" % [kind, slot])
				. is_not_null()
			)
		assert_object((character.brain as AiBrain).behaviour).is_not_null()
		character.queue_free()


func test_each_kind_wears_its_mannequin_and_the_armed_ones_hold_the_pistol_in_the_hand() -> void:
	for kind: String in SCENES:
		var character := _arena.add_kind(
			SCENES[kind], Vector3(float(SCENES.keys().find(kind)) * 3.0 - 4.0, 0, 4.0)
		)
		await _ticks(3)
		var wanted: Array = KINDS[kind]
		var rig := character.model.rig()
		(
			assert_str(rig.scene_file_path.get_file())
			. override_failure_message("%s wears %s" % [kind, rig.scene_file_path])
			. is_equal(wanted[3])
		)
		assert_int(_rigs_under(character.model)).is_equal(1)
		var armed: bool = wanted[4]
		(
			assert_bool(character.loadout.held_slot() >= 0)
			. override_failure_message("%s holds slot %d" % [kind, character.loadout.held_slot()])
			. is_equal(armed)
		)
		if armed:
			assert_float(await _seat_gap(character)).is_less(SEAT_TOLERANCE)


func test_a_variant_male_keeps_the_pistol_in_his_hand_after_a_pool_parks_him_and_he_comes_back(
) -> void:
	var character := _arena.add_kind(SCENES["grunt"], Vector3(0, 0, 2))
	await _ticks(3)
	_arena.remove_child(character)
	await _ticks(2)
	_arena.add_child(character)
	character.teleport(Vector3(2, 0, 2), 0.0)
	character.ai_controller().walk_direction = Vector3.RIGHT
	await _ticks(30)
	assert_float(await _seat_gap(character)).is_less(SEAT_TOLERANCE)
	var seat := character.model.get_node("PistolHeld") as BoneAttachment3D
	var bound := 0
	for connection in character.model.skeleton().get_signal_connection_list(&"skeleton_updated"):
		if (connection["callable"] as Callable).get_object() == seat:
			bound += 1
	assert_int(bound).is_equal(1)
	character.queue_free()


func test_the_variant_set_while_running_replaces_the_model_at_once() -> void:
	var character := _arena.add_kind(SCENES["ally"], Vector3(0, 0, -3))
	await _ticks(2)
	character.model.variant = load(CharacterBodies.MALE)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_str(character.model.rig().scene_file_path.get_file()).is_equal("form_male.glb")
	assert_int(_rigs_under(character.model)).is_equal(1)
	await _ticks(3)
	assert_float(await _seat_gap(character)).is_less(SEAT_TOLERANCE)


func test_each_profile_edited_while_running_applies_at_the_next_think() -> void:
	# A target straight behind is outside every shipped cone, whatever way a character looks round;
	# with the cone widened live to nearly all round, the character sees it at its next thinks.
	_arena.add_director()
	for kind: String in SCENES:
		var at := Vector3(float(SCENES.keys().find(kind)) * 6.0 - 9.0, 0, -4.0)
		var character := _arena.add_kind(SCENES[kind], at, 0.0)
		var hostile := &"player" if String(KINDS[kind][2]) == "enemy" else &"enemy"
		var target := _arena.add_target("Seen%s" % kind, at + Vector3(0, 0, -7.0), hostile)
		await _ticks(60)
		var senses := character.senses as AiSenses
		(
			assert_bool(senses.beliefs.knows(target))
			. override_failure_message("%s saw a target behind it" % kind)
			. is_false()
		)
		character.profile.half_angle = 179.0
		await _ticks(60)
		(
			assert_bool(senses.beliefs.knows(target))
			. override_failure_message("%s did not take the wider cone" % kind)
			. is_true()
		)
		character.queue_free()
		target.queue_free()
		await _ticks(2)


func _rigs_under(slot: CharacterModel) -> int:
	var rigs := 0
	for child in slot.get_children():
		if child is Node3D and not child.find_children("*", "Skeleton3D", true, false).is_empty():
			rigs += 1
	return rigs


# The largest distance between the pistol's seat and the right hand over `ticks` ticks, the hand
# read in the skeleton's own update (the hold's modifiers move it after the clip, and the seat
# follows their result).
func _seat_gap(character: AiCharacter, ticks := 20) -> float:
	var skeleton := character.model.skeleton()
	var hand := skeleton.find_bone(&"hand_r")
	var seat := character.model.get_node("PistolHeld") as Node3D
	var seen := [skeleton.get_bone_global_pose(hand)]
	var copy := func() -> void: seen[0] = skeleton.get_bone_global_pose(hand)
	skeleton.skeleton_updated.connect(copy)
	var worst := 0.0
	for _tick in ticks:
		await get_tree().physics_frame
		await get_tree().process_frame
		var at: Transform3D = skeleton.global_transform * (seen[0] as Transform3D)
		worst = maxf(worst, seat.global_position.distance_to(at.origin))
	skeleton.skeleton_updated.disconnect(copy)
	return worst

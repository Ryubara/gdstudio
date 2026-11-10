# Replacing the player's model the way the editor does (delete the old one, drop a new .glb on
# `Model`) keeps the character working with nothing set by hand: the clips resolve, the pistol is
# still in the hand, the tree and the footsteps follow the new skeleton.
#
# The editor, when it deletes a node, empties every path that pointed at it: the AnimationPlayer's
# Root Node and the AnimationTree's. `_swap` does the same (recorded from the editor's own delete
# by `tools/editor_swap/`), then adds the new model as the editor does. The tests swap in the male
# mannequin, which the player scene does not hold; the female one is the default.
extends GdUnitTestSuite

const FEMALE := "res://assets/characters/mannequin/mannequin_female.glb"
const MALE := "res://assets/characters/mannequin/mannequin_male.glb"
## How far the seat may be from the bone it hangs on, in metres.
const SEAT_TOLERANCE := 0.02

var _arena: PlayArena
var _player: Player
var _slot: PlayerModel
var _animation_player: AnimationPlayer
var _tree: AnimationTree


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 25.0))
	_slot = _player.model
	_animation_player = _player.get_node("AnimationPlayer")
	_tree = _player.get_node("AnimationTree")
	await InputSim.ticks(get_tree(), 6)


func after_test() -> void:
	InputSim.release_all()


# Deletes the model and drops `scene` in its place under the slot, named `model_name`.
func _swap(scene: PackedScene, model_name: String) -> Node3D:
	_remove_rig()
	_animation_player.root_node = NodePath()
	_tree.root_node = NodePath()
	var added := scene.instantiate() as Node3D
	added.name = model_name
	_slot.add_child(added)
	added.owner = _player
	await _idle_frames()
	return added


func _remove_rig() -> void:
	var old := _slot.rig()
	_slot.remove_child(old)
	old.free()


# The slot looks again on the next idle frame; give it two.
func _idle_frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _unresolved_tracks() -> Array[String]:
	var missing: Array[String] = []
	var root := _animation_player.get_node_or_null(_animation_player.root_node)
	if root == null:
		missing.append("root_node %s points at nothing" % _animation_player.root_node)
		return missing
	for clip in CharacterClips.ALL:
		var animation := _animation_player.get_animation(clip)
		for track in animation.get_track_count():
			var path := animation.track_get_path(track)
			var node := root.get_node_or_null(NodePath(path.get_concatenated_names()))
			var skeleton := node as Skeleton3D
			if node == null:
				missing.append("%s: %s" % [clip, path])
			elif skeleton != null and skeleton.find_bone(path.get_concatenated_subnames()) < 0:
				missing.append("%s: no bone %s" % [clip, path.get_concatenated_subnames()])
	return missing


func test_the_shipped_model_resolves_every_track() -> void:
	assert_array(_unresolved_tracks()).is_empty()
	assert_object(_slot.rig()).is_not_null()
	assert_str(String(_slot.rig().name)).is_equal("Mannequin")


func test_a_new_model_with_another_name_resolves_every_track_of_every_clip() -> void:
	var added := await _swap(load(MALE), "mannequin_male")
	assert_object(_slot.rig()).is_same(added)
	assert_array(_unresolved_tracks()).is_empty()
	assert_object(_animation_player.get_node(_animation_player.root_node)).is_same(added)


func test_either_mannequin_can_be_dropped_on_the_slot_in_turn() -> void:
	# Female (the default) to male and back: the clips resolve each time and the slot hands out
	# the model it holds.
	for path in [MALE, FEMALE, MALE]:
		var added := await _swap(load(path), String(path).get_file().get_basename())
		assert_object(_slot.rig()).is_same(added)
		assert_array(_unresolved_tracks()).is_empty()
		assert_object(_slot.skeleton()).is_same(added.get_node("Armature/Skeleton3D"))


func test_both_mannequins_have_the_same_bones_in_the_same_places_of_the_tree() -> void:
	var female := (load(FEMALE) as PackedScene).instantiate()
	var male := (load(MALE) as PackedScene).instantiate()
	add_child(female)
	add_child(male)
	var a := female.get_node("Armature/Skeleton3D") as Skeleton3D
	var b := male.get_node("Armature/Skeleton3D") as Skeleton3D
	assert_int(b.get_bone_count()).is_equal(a.get_bone_count())
	for bone in a.get_bone_count():
		assert_str(b.get_bone_name(bone)).is_equal(a.get_bone_name(bone))
		assert_int(b.get_bone_parent(bone)).is_equal(a.get_bone_parent(bone))
	female.free()
	male.free()


func test_the_tree_follows_the_new_model() -> void:
	var added := await _swap(load(MALE), "male")
	assert_str(String(_tree.anim_player)).is_equal("../AnimationPlayer")
	assert_object(_tree.get_node_or_null(_tree.root_node)).is_same(added)
	assert_object(_tree.tree_root).is_not_null()
	# The upper body's filter paths are read from the new skeleton.
	var armed := (
		(_tree.tree_root as AnimationNodeBlendTree).get_node(&"Armed") as AnimationNodeBlend2
	)
	assert_bool(armed.is_path_filtered(NodePath("Armature/Skeleton3D:hand_r"))).is_true()
	assert_bool(armed.is_path_filtered(NodePath("Armature/Skeleton3D:thigh_l"))).is_false()


func test_the_pose_moves_on_the_new_model() -> void:
	var added := await _swap(load(MALE), "male")
	var skeleton := added.get_node("Armature/Skeleton3D") as Skeleton3D
	var thigh := skeleton.find_bone(&"thigh_l")
	var rest := skeleton.get_bone_rest(thigh).basis.get_rotation_quaternion()
	InputSim.key(KEY_X, true)
	InputSim.key(KEY_W, true)
	var moved := 0.0
	for tick in 90:
		await get_tree().physics_frame
		moved = maxf(moved, skeleton.get_bone_pose_rotation(thigh).angle_to(rest))
	# A model in the rest pose (a T-pose) never leaves it; a walking leg swings tens of degrees.
	assert_float(rad_to_deg(moved)).is_greater(15.0)


# How far the pistol's seat (the `BoneAttachment3D` itself, not the pistol's own offset from it) is
# from the bone it hangs on, in metres.
func _seat_error(slot: PlayerModel) -> float:
	var skeleton := slot.skeleton()
	var seat := slot.get_node("PistolHeld") as BoneAttachment3D
	var hand := (
		skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(&"hand_r"))
	)
	return seat.global_position.distance_to(hand.origin)


func test_the_pistol_is_still_seated_on_the_hand_of_the_new_model() -> void:
	var added := await _swap(load(MALE), "male")
	var skeleton := added.get_node("Armature/Skeleton3D") as Skeleton3D
	var seat := _slot.get_node("PistolHeld") as BoneAttachment3D
	assert_bool(seat.use_external_skeleton).is_true()
	assert_object(seat.get_node(seat.get_external_skeleton())).is_same(skeleton)
	await InputSim.ticks(get_tree(), 4)
	assert_float(_seat_error(_slot)).is_less(SEAT_TOLERANCE)
	var pistol := seat.get_node("Pistol") as Node3D
	assert_float(pistol.global_position.distance_to(seat.global_position)).is_less(0.35)
	var muzzle := _player.weapon.muzzle
	assert_bool(is_instance_valid(muzzle) and muzzle.is_inside_tree()).is_true()


func test_the_pistol_follows_the_hand_through_a_walk_after_a_swap_to_the_same_name() -> void:
	# The new skeleton has the old one's path, so only the connection tells the seat is stale.
	await _swap(load(MALE), "Mannequin")
	assert_float(await _walk_and_measure(_slot)).is_less(SEAT_TOLERANCE)


# The same swap in `main.tscn`, where the player stands in the level under the camera, and the
# bug lay: the pistol stayed where the old hand last was, so the test walks the character and
# compares the seat with the hand in every frame.
func test_the_pistol_follows_the_hand_through_a_walk_after_a_swap_in_the_main_scene() -> void:
	var scene := scene_runner("res://main.tscn").scene()
	var player := scene.get_node("PlayerRig/Player") as Player
	var slot := player.model
	await InputSim.ticks(get_tree(), 10)
	var old := slot.rig()
	slot.remove_child(old)
	old.free()
	player.get_node("AnimationPlayer").root_node = NodePath()
	player.get_node("AnimationTree").root_node = NodePath()
	var added := (load(MALE) as PackedScene).instantiate() as Node3D
	added.name = "male"
	slot.add_child(added)
	added.owner = player
	await _idle_frames()
	assert_object(slot.rig()).is_same(added)
	assert_float(await _walk_and_measure(slot)).is_less(SEAT_TOLERANCE)


# Crouch-walks the player of `slot` for a second and a half and returns the largest distance the
# pistol's seat was from the hand in any frame once the pose had updated. It also checks that the
# hand really moved, which a seat left behind would not follow.
func _walk_and_measure(slot: PlayerModel) -> float:
	var skeleton := slot.skeleton()
	var hand := skeleton.find_bone(&"hand_r")
	InputSim.key(KEY_X, true)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 3)
	var worst := 0.0
	var low := Vector3(INF, INF, INF)
	var high := -low
	for tick in 90:
		await get_tree().physics_frame
		worst = maxf(worst, _seat_error(slot))
		var at := (skeleton.global_transform * skeleton.get_bone_global_pose(hand)).origin
		var in_model := slot.to_local(at)
		low = low.min(in_model)
		high = high.max(in_model)
	(
		assert_float((high - low).length())
		. override_failure_message(
			"the hand did not move, so the test would pass with a seat left behind"
		)
		. is_greater(0.05)
	)
	return worst


func test_the_footsteps_follow_the_new_skeleton() -> void:
	var steps := _player.get_node("Footsteps") as Footsteps
	var added := await _swap(load(MALE), "male")
	assert_object(steps.model.skeleton()).is_same(added.get_node("Armature/Skeleton3D"))
	var heard := []
	steps.stepped.connect(func(foot: StringName, _crouched: bool) -> void: heard.append(foot))
	InputSim.key(KEY_X, true)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 40)
	heard.clear()
	await InputSim.ticks(get_tree(), 3 * Engine.physics_ticks_per_second)
	assert_int(heard.size()).is_greater_equal(2)


func test_a_model_without_the_rigs_armature_gets_one_warning_and_no_model_another() -> void:
	var animation := _player.get_node("Animation") as PlayerAnimation
	assert_array(animation._get_configuration_warnings()).is_empty()
	assert_array(_slot._get_configuration_warnings()).is_empty()
	_remove_rig()
	var odd := Node3D.new()
	odd.name = "Odd"
	odd.add_child(Skeleton3D.new())
	_slot.add_child(odd)
	await _idle_frames()
	assert_array(animation._get_configuration_warnings()).has_size(1)
	assert_array(_slot._get_configuration_warnings()).is_empty()
	_slot.remove_child(odd)
	odd.free()
	await _idle_frames()
	assert_array(_slot._get_configuration_warnings()).has_size(1)
	assert_object(_slot.rig()).is_null()


func test_the_player_still_turns_the_slot_to_its_heading() -> void:
	await _swap(load(MALE), "male")
	InputSim.key(KEY_D, true)
	await InputSim.ticks(get_tree(), 30)
	assert_float(absf(wrapf(_slot.rotation.y - _player.facing, -PI, PI))).is_less(0.2)


func test_nothing_between_the_player_and_the_model_has_a_unique_name() -> void:
	# The AnimationTree's root is written as a path with the unique name in it (`%Model/...`), and
	# the helper player the editor makes when the tree is selected cannot resolve it: every clip
	# then warns for every bone. A plain relative path resolves.
	var path := String(_tree.get_path_to(_slot.rig(), true))
	assert_bool(path.contains("%")).override_failure_message(path).is_false()
	assert_str(String(_tree.root_node)).is_equal(path)


func test_only_two_lines_of_the_player_scene_name_the_mannequin() -> void:
	# The animation player's Root Node and the pistol's seat name it, and the slot rewrites both
	# when the model is replaced. Nothing else may: a path into a model is lost with the model.
	var text := FileAccess.get_file_as_string("res://gameplay/player/player.tscn")
	var header := '[node name="Model" type="Node3D" parent="."]\nscript'
	assert_bool(text.contains(header)).is_true()
	var named: Array[String] = []
	for line in text.split("\n"):
		if line.contains("Mannequin/") or line.contains('Mannequin")'):
			named.append(line)
	assert_array(named).has_size(2)

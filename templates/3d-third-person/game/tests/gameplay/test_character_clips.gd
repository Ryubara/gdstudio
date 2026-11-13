# Every clip of the Universal Animation Library 1 and 2, of the prone, melee and rifle clips and
# of our own is reachable by name, and plays on the mannequin.
extends GdUnitTestSuite

var _player: Player


func before_test() -> void:
	_player = auto_free(load("res://gameplay/player/player.tscn").instantiate())
	_player.start_at_spawn = false
	add_child(_player)


func test_every_listed_clip_exists_and_every_clip_is_listed() -> void:
	var animation_player: AnimationPlayer = _player.get_node("AnimationPlayer")
	for clip in CharacterClips.ALL:
		(
			assert_bool(animation_player.has_animation(clip))
			. override_failure_message("no clip %s" % clip)
			. is_true()
		)
	var in_libraries := 0
	for library_name in animation_player.get_animation_library_list():
		var library := animation_player.get_animation_library(library_name)
		in_libraries += library.get_animation_list().size()
	assert_int(in_libraries).is_equal(CharacterClips.ALL.size())
	assert_int(CharacterClips.ALL.size()).is_equal(138)


func test_every_constant_names_a_listed_clip() -> void:
	var map: Dictionary = (CharacterClips as GDScript).get_script_constant_map()
	for key: String in map:
		var value: Variant = map[key]
		if value is StringName and String(value).contains("/"):
			assert_bool(CharacterClips.ALL.has(value)).override_failure_message(key).is_true()


func test_every_track_of_every_clip_drives_a_bone_of_the_mannequin() -> void:
	var animation_player: AnimationPlayer = _player.get_node("AnimationPlayer")
	var root := animation_player.get_node(animation_player.root_node)
	for clip in CharacterClips.ALL:
		var animation := animation_player.get_animation(clip)
		for track in animation.get_track_count():
			var path := animation.track_get_path(track)
			var node := root.get_node_or_null(NodePath(path.get_concatenated_names()))
			assert_object(node).override_failure_message("%s: %s" % [clip, path]).is_not_null()
			var skeleton := node as Skeleton3D
			if skeleton != null:
				var bone := String(path.get_concatenated_subnames())
				(
					assert_int(skeleton.find_bone(bone))
					. override_failure_message("%s: no bone %s" % [clip, bone])
					. is_greater_equal(0)
				)


func test_the_clips_the_player_animation_uses_are_in_the_libraries() -> void:
	var animation: CharacterAnimation = _player.get_node("Animation")
	var player: AnimationPlayer = _player.get_node("AnimationPlayer")
	for clip in [
		animation.idle_clip,
		animation.walk_clip,
		animation.run_clip,
		animation.sprint_clip,
		animation.jump_clip,
		animation.air_clip,
		animation.land_clip,
		animation.push_clip,
		animation.interact_clip,
		animation.hit_clip,
	]:
		assert_bool(player.has_animation(clip)).override_failure_message(clip).is_true()


func test_the_looping_clips_loop_and_the_one_shots_do_not() -> void:
	var player: AnimationPlayer = _player.get_node("AnimationPlayer")
	for clip in [CharacterClips.IDLE, CharacterClips.WALK, CharacterClips.RUN, CharacterClips.AIR]:
		assert_int(player.get_animation(clip).loop_mode).is_equal(Animation.LOOP_LINEAR)
	for clip in [CharacterClips.JUMP_START, CharacterClips.LAND, CharacterClips.HIT]:
		assert_int(player.get_animation(clip).loop_mode).is_equal(Animation.LOOP_NONE)

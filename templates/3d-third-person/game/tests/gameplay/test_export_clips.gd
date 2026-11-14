# The export leaves the Universal Animation Library clips nothing names out of the pack
# (`ClipExport` of `gds_game`, with the libraries and the catalogue set in `project.godot`): the
# clips it keeps are every library clip the player's tree, `CharacterAnimation`'s clip settings,
# the weapon and item definitions and the scripts' `CharacterClips` constants name, so the web
# build plays every one, and a stand-in set in a scene is kept with them. The editor keeps the
# full libraries. CI's `tools/export_check/export_clips_check.gd` reads the exported pack itself.
extends GdUnitTestSuite

const STAND_IN_SCENE := "user://test_export_clips_stand_in.tscn"

var _player: Player
var _kept: PackedStringArray


# One player and one read of the project for the suite: no case changes either.
func before() -> void:
	_kept = played()
	_player = load("res://gameplay/player/player.tscn").instantiate()
	_player.start_at_spawn = false
	add_child(_player)


func after() -> void:
	_player.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STAND_IN_SCENE))


## The clips the export keeps, read from the project as the export reads it.
static func played(extra: PackedStringArray = []) -> PackedStringArray:
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	var files := ClipReferences.project_files(
		str(presets.get_value("preset.0", "exclude_filter", ""))
	)
	files.append_array(extra)
	var names: Array[StringName] = []
	names.assign(ClipReferences.libraries().keys())
	return ClipReferences.named_in(files, names, ClipReferences.catalogue())


func _is_pruned(clip: StringName) -> bool:
	return ClipReferences.libraries().has(StringName(String(clip).get_slice("/", 0)))


func _assert_kept(clip: StringName, where: String) -> void:
	if not _is_pruned(clip):
		return
	(
		assert_bool(_kept.has(clip))
		. override_failure_message("%s: %s is left out" % [where, clip])
		. is_true()
	)


func test_the_project_prunes_both_libraries() -> void:
	assert_array(ClipReferences.libraries().keys()).contains_exactly_in_any_order(
		[&"ual1", &"ual2"]
	)
	assert_object(ClipReferences.catalogue()).is_equal(CharacterClips)


func test_every_clip_of_the_tree_is_kept() -> void:
	var animation: CharacterAnimation = _player.get_node("Animation")
	var clips: Array[StringName] = []
	_walk(animation.tree.tree_root, clips)
	assert_int(clips.size()).is_greater(20)
	var player: AnimationPlayer = _player.get_node("AnimationPlayer")
	for clip in clips:
		_assert_kept(clip, "the tree")
		assert_bool(player.has_animation(clip)).override_failure_message(String(clip)).is_true()


func test_every_clip_setting_of_the_character_is_kept() -> void:
	var animation: CharacterAnimation = _player.get_node("Animation")
	var seen := 0
	for property in animation.get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE and property.type == TYPE_STRING_NAME:
			var value: StringName = animation.get(property.name)
			if String(value).contains("/"):
				seen += 1
				_assert_kept(value, property.name)
	assert_int(seen).is_greater(15)


func test_every_clip_of_a_definition_is_kept() -> void:
	var seen := 0
	for path in ClipReferences.project_files("tests/*, tools/*, addons/*"):
		if path.get_extension() != "tres":
			continue
		var resource := load(path)
		for property in resource.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE:
				for clip in _clip_names(resource.get(property.name)):
					seen += 1
					_assert_kept(clip, "%s %s" % [path, property.name])
	assert_int(seen).is_greater(5)


func test_every_kept_clip_is_in_its_library() -> void:
	var player: AnimationPlayer = _player.get_node("AnimationPlayer")
	for clip in _kept:
		assert_bool(player.has_animation(clip)).override_failure_message(clip).is_true()


func test_the_pruned_libraries_hold_the_kept_clips_and_nothing_else() -> void:
	var libraries := ClipReferences.libraries()
	var total := 0
	for library_name in libraries:
		var full: AnimationLibrary = load(libraries[library_name])
		var out := ClipReferences.pruned(full, library_name, _kept)
		var names: PackedStringArray = []
		for clip in out.get_animation_list():
			names.append("%s/%s" % [library_name, clip])
		var wanted: PackedStringArray = []
		for clip in _kept:
			if clip.begins_with("%s/" % library_name):
				wanted.append(clip)
		assert_array(names).contains_exactly_in_any_order(wanted)
		assert_int(full.get_animation_list().size()).is_equal(43)
		total += names.size()
	# The template plays a fraction of the 86: the rest leave the pack.
	assert_int(total).is_less(43)


func test_a_stand_in_is_left_out_until_a_scene_sets_it() -> void:
	var stand_in := CharacterClips.stand_in(CharacterClips.LAND)
	assert_bool(_kept.has(stand_in)).is_false()
	var scene := FileAccess.open(STAND_IN_SCENE, FileAccess.WRITE)
	scene.store_string(
		'[gd_scene format=3]\n\n[node name="Animation" type="Node"]\nland_clip = &"%s"\n' % stand_in
	)
	scene.close()
	assert_bool(played([STAND_IN_SCENE]).has(stand_in)).is_true()


func test_a_commented_name_keeps_nothing() -> void:
	var source := 'var a := &"ual1/Idle" # "ual1/Dance"\n# CharacterClips.DANCE "ual2/Slide"\n'
	assert_str(ClipReferences.without_comments(source)).is_equal('var a := &"ual1/Idle" \n\n')


func _walk(node: AnimationNode, out: Array[StringName]) -> void:
	if node is AnimationNodeAnimation:
		# A clip node the tree fills when it plays (an action, a gait's transition) is empty.
		if not (node as AnimationNodeAnimation).animation.is_empty():
			out.append((node as AnimationNodeAnimation).animation)
	elif node is AnimationNodeBlendTree:
		var blend := node as AnimationNodeBlendTree
		for child in blend.get_node_list():
			if child != &"output":
				_walk(blend.get_node(child), out)
	elif node is AnimationNodeStateMachine:
		var machine := node as AnimationNodeStateMachine
		for child in machine.get_node_list():
			_walk(machine.get_node(child), out)
	elif node is AnimationNodeBlendSpace1D:
		var space := node as AnimationNodeBlendSpace1D
		for i in space.get_blend_point_count():
			_walk(space.get_blend_point_node(i), out)
	elif node is AnimationNodeBlendSpace2D:
		var space_2d := node as AnimationNodeBlendSpace2D
		for i in space_2d.get_blend_point_count():
			_walk(space_2d.get_blend_point_node(i), out)


func _clip_names(value: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if value is StringName or value is String:
		if String(value).contains("/") and not String(value).begins_with("res://"):
			out.append(StringName(value))
	elif value is Array:
		for item: Variant in value:
			out.append_array(_clip_names(item))
	elif value is Dictionary:
		for key: Variant in value:
			out.append_array(_clip_names(key))
			out.append_array(_clip_names(value[key]))
	return out

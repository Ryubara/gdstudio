## Reads an exported pack and checks the clips it carries: each Universal Animation Library in the
## pack holds exactly the clips the game names (`ClipReferences`, as `ClipExport` read them at the
## export), and a player loaded from the pack finds every clip its animation tree plays. Prints
## each library's clip count and the pack's size, and exits 1 on a missing or extra clip.
##
## Run it headless from a game made from the template, after the web export (CI does):
## `<godot> --headless --path game -s res://tools/export_check/export_clips_check.gd --
## ../build/web/index.pck`
## It lives in tools/, which the export leaves out.
extends SceneTree

const PLAYER := "res://gameplay/player/player.tscn"

var _failures := 0
var _player: Node
var _frames := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var pack: String = args[0] if not args.is_empty() else "../build/web/index.pck"
	if pack.is_relative_path():
		pack = ProjectSettings.globalize_path("res://").path_join(pack).simplify_path()
	var wanted := _named()
	if not FileAccess.file_exists(pack) or not ProjectSettings.load_resource_pack(pack, true):
		_fail("no pack at %s" % pack)
		quit(1)
		return
	print("pack %s: %d bytes" % [pack.get_file(), FileAccess.get_size(pack)])
	var libraries := ClipReferences.libraries()
	for library_name in libraries:
		var library := (
			ResourceLoader.load(libraries[library_name], "", ResourceLoader.CACHE_MODE_IGNORE)
			as AnimationLibrary
		)
		if library == null:
			_fail("the pack has no library %s" % library_name)
			continue
		var held: PackedStringArray = []
		for clip in library.get_animation_list():
			held.append("%s/%s" % [library_name, clip])
		var want: PackedStringArray = []
		for clip in wanted:
			if clip.begins_with("%s/" % library_name):
				want.append(clip)
		print("%s: %d clips in the pack, %d named" % [library_name, held.size(), want.size()])
		for clip in want:
			if not held.has(clip):
				_fail("%s is named and not in the pack" % clip)
		for clip in held:
			if not want.has(clip):
				_fail("%s is in the pack and named nowhere" % clip)
	var scene := (
		ResourceLoader.load(PLAYER, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	)
	_player = scene.instantiate()
	_player.set("start_at_spawn", false)
	get_root().add_child(_player)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	var animation: CharacterAnimation = _player.get_node("Animation")
	var player: AnimationPlayer = _player.get_node("AnimationPlayer")
	var clips: Array[StringName] = []
	_walk(animation.tree.tree_root, clips)
	for clip in clips:
		if not player.has_animation(clip):
			_fail("the tree plays %s and the pack's player has no such clip" % clip)
	var settings := 0
	for property in animation.get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE and property.type == TYPE_STRING_NAME:
			var clip: StringName = animation.get(property.name)
			if String(clip).contains("/"):
				settings += 1
				if not player.has_animation(clip):
					_fail("%s is %s and the pack's player has no such clip" % [property.name, clip])
	print("the tree plays %d clips, the clip settings name %d" % [clips.size(), settings])
	print("export clips: %s" % ("ok" if _failures == 0 else "%d failures" % _failures))
	_player.free()
	quit(1 if _failures > 0 else 0)
	return true


func _named() -> PackedStringArray:
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	var files := ClipReferences.project_files(
		str(presets.get_value("preset.0", "exclude_filter", ""))
	)
	var names: Array[StringName] = []
	names.assign(ClipReferences.libraries().keys())
	return ClipReferences.named_in(files, names, ClipReferences.catalogue())


func _fail(why: String) -> void:
	_failures += 1
	printerr("export clips: %s" % why)


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

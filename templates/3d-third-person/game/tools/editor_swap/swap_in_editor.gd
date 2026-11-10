@tool
extends EditorPlugin
## Replaces the player's model the way a person does in the editor, and checks that the character
## still works. It needs the editor, so no GdUnit test can run it: add
## `res://tools/editor_swap/plugin.cfg` to `editor_plugins/enabled` in `project.godot` for the run
## and take it out after (an `override.cfg` does not enable an editor plugin in 4.7.2), then run
## `godot --headless --editor --path game`, or the same through `gds godot` with a window for the
## screenshots (`SWAP_SHOT_DIR`).
##
## It opens `player.tscn`, selects the model, presses Delete in the Scene dock and confirms,
## selects `Model` and has the dock instance the other mannequin on it: `mannequin_male.glb`, or
## `mannequin_female.glb` when `SWAP_MODEL=female` (the node is named after the file, not
## `Mannequin`), then selects the AnimationTree and the AnimationPlayer. It saves the scene to see
## what is written and puts the file back.
##
## It prints one `SWAP` line for each check and quits with 1 if one failed. The editor's own
## warnings (`couldn't resolve track`, `invalid root_node`) go to the output: count them there.
## With `SWAP_SHOT_DIR` set it saves the editor's window before the swap, after it and with the
## tree selected.

const SCENE := "res://gameplay/player/player.tscn"
const FOLDER := "res://assets/characters/mannequin/"

var _failed := false
var _model_path := FOLDER + "mannequin_%s.glb" % _which()
var _node_name := StringName(_model_path.get_file().get_basename())


func _enter_tree() -> void:
	_run.call_deferred()


func _which() -> String:
	return "female" if OS.get_environment("SWAP_MODEL") == "female" else "male"


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _check(ok: bool, what: String) -> void:
	print("SWAP ", "ok   " if ok else "FAIL ", what)
	_failed = _failed or not ok


# Saves the editor's window when SWAP_SHOT_DIR names a folder.
func _shot(shot_name: String) -> void:
	var folder := OS.get_environment("SWAP_SHOT_DIR")
	if folder != "":
		var image := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
		image.save_png(folder.path_join(shot_name + ".png"))


func _dock() -> Node:
	return EditorInterface.get_base_control().find_children("*", "SceneTreeDock", true, false)[0]


func _select(node: Node) -> void:
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(node)
	EditorInterface.edit_node(node)


# The tracks of every clip that the AnimationPlayer's root does not resolve.
func _unresolved(animation_player: AnimationPlayer) -> int:
	var root := animation_player.get_node_or_null(animation_player.root_node)
	if root == null:
		return -1
	var missing := 0
	for library_name in animation_player.get_animation_library_list():
		var library := animation_player.get_animation_library(library_name)
		for clip in library.get_animation_list():
			var animation := library.get_animation(clip)
			for track in animation.get_track_count():
				var path := animation.track_get_path(track)
				var node := root.get_node_or_null(NodePath(path.get_concatenated_names()))
				if node == null:
					missing += 1
				elif node is Skeleton3D:
					var bone := path.get_concatenated_subnames()
					missing += 1 if (node as Skeleton3D).find_bone(bone) < 0 else 0
	return missing


func _delete_selected() -> void:
	var dock := _dock()
	dock.find_children("*", "Tree", true, false)[0].grab_focus()
	var key := InputEventKey.new()
	key.keycode = KEY_DELETE
	key.physical_keycode = KEY_DELETE
	key.pressed = true
	dock.get_viewport().push_input(key)
	await _frames(10)
	for dialog in dock.find_children("*", "ConfirmationDialog", true, false):
		if dialog.visible:
			dialog.emit_signal("confirmed")
	await _frames(10)


func _run() -> void:
	await _frames(240)
	EditorInterface.open_scene_from_path(SCENE)
	await _frames(90)
	var root := EditorInterface.get_edited_scene_root()
	var slot := root.get_node("Model") as PlayerModel
	var animation_player := root.get_node("AnimationPlayer") as AnimationPlayer
	var tree := root.get_node("AnimationTree") as AnimationTree
	_check(_unresolved(animation_player) == 0, "before: every track resolves")
	EditorInterface.set_main_screen_editor("3D")
	_select(slot)
	await _frames(60)
	_shot("before")
	print("SWAP model ", _model_path)

	_select(slot.get_node("Mannequin"))
	await _frames(10)
	await _delete_selected()
	_check(slot.rig() == null, "the model is deleted")
	_check(
		animation_player.root_node.is_empty(), "the editor emptied the AnimationPlayer's Root Node"
	)

	_select(slot)
	await _frames(5)
	_dock().call("instantiate", _model_path)
	await _frames(20)
	var rig := slot.rig()
	_check(rig != null and rig.name == _node_name, "the new model is `%s`" % _node_name)
	_check(_unresolved(animation_player) == 0, "after: every track resolves")
	_check(
		rig != null and animation_player.get_node_or_null(animation_player.root_node) == rig,
		"the Root Node is the new model"
	)
	var seat := slot.get_node("PistolHeld") as BoneAttachment3D
	_check(
		seat.get_node_or_null(seat.get_external_skeleton()) == slot.skeleton(),
		"the pistol is seated on the new skeleton"
	)
	_check(
		tree.get_node_or_null(tree.root_node) == rig, "the AnimationTree's root is the new model"
	)
	_check(tree.tree_root != null and not tree.anim_player.is_empty(), "the tree is built")
	_select(slot)
	await _frames(60)
	_shot("swapped_" + _which())

	# What the maintainer did next: select the tree (which builds the cache of every clip).
	_select(tree)
	await _frames(120)
	_select(animation_player)
	await _frames(60)
	_select(tree)
	await _frames(30)
	# Saving the scene must write no tree, no player path and no root for the tree.
	var before_save := FileAccess.get_file_as_string(SCENE)
	EditorInterface.save_scene()
	await _frames(30)
	var saved := FileAccess.get_file_as_string(SCENE)
	for generated in ["tree_root", "anim_player", "AnimationNode"]:
		_check(not saved.contains(generated), "the saved scene holds no `%s`" % generated)
	_check(
		saved.contains('root_node = NodePath("../Model/%s")' % _node_name),
		"the saved Root Node names the new model"
	)
	FileAccess.open(SCENE, FileAccess.WRITE).store_string(before_save)
	_show_output()
	await _frames(30)
	_shot("tree_selected")
	print("SWAP ", "FAILED" if _failed else "DONE")
	get_tree().quit(1 if _failed else 0)


# Opens the Output panel at the bottom, as a click on its tab does.
func _show_output() -> void:
	for bar in EditorInterface.get_base_control().find_children("*", "TabBar", true, false):
		for index in (bar as TabBar).tab_count:
			if (bar as TabBar).get_tab_title(index).strip_edges() == "Output":
				(bar as TabBar).current_tab = index

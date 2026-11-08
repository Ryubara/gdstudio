# The player's AnimationTree is built in code (PlayerAnimation), and the editor shows it too: the
# script is a `@tool` script, so opening the player scene builds the tree and the node has no
# warning. The built tree must never be written into a scene file.
extends GdUnitTestSuite

const PLAYER_SCENE := "res://gameplay/player/player.tscn"
const SCENES := [
	"res://gameplay/player/player.tscn",
	"res://main.tscn",
	"res://world/prototype/prototype_level.tscn",
]


func test_the_script_is_a_tool_script_so_the_editor_builds_the_tree() -> void:
	var source := FileAccess.get_file_as_string("res://gameplay/player/player_animation.gd")
	assert_bool(source.begins_with("@tool")).is_true()


func test_the_tree_has_its_root_and_animation_player_once_the_scene_is_ready() -> void:
	var player: Player = auto_free(load(PLAYER_SCENE).instantiate())
	player.start_at_spawn = false
	add_child(player)
	var tree: AnimationTree = player.get_node("AnimationTree")
	# The editor warns about exactly these: no root, no player, or a path to nothing.
	assert_object(tree.tree_root).is_not_null()
	assert_bool(tree.anim_player.is_empty()).is_false()
	assert_object(tree.get_node(tree.anim_player)).is_instanceof(AnimationPlayer)


func test_no_scene_file_holds_the_generated_tree() -> void:
	for path: String in SCENES:
		var text := FileAccess.get_file_as_string(path)
		assert_bool(text.is_empty()).override_failure_message("cannot read %s" % path).is_false()
		for forbidden in ["tree_root", "AnimationNode", "anim_player"]:
			(
				assert_bool(text.contains(forbidden))
				. override_failure_message(
					"%s holds %s: a built tree was saved" % [path, forbidden]
				)
				. is_false()
			)


func test_the_player_scene_marks_the_model_editable_so_the_export_keeps_what_hangs_on_it() -> void:
	# The pistol hangs on the mannequin's skeleton: a node added inside an instanced scene that is
	# not marked editable is there in the editor and in a test, and missing from the web export.
	var text := FileAccess.get_file_as_string(PLAYER_SCENE)
	assert_bool(text.contains('[editable path="Model"]')).is_true()
	assert_bool(text.contains('parent="Model/Armature/Skeleton3D"')).is_true()

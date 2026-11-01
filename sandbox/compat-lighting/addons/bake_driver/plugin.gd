@tool
extends EditorPlugin
## Spike only. LightmapGI.bake() is not exposed to scripts, so this plugin drives the editor's own
## "Bake Lightmaps" button: it builds the night scene, saves it as res://bakes/bake_<name>.tscn, selects
## the LightmapGI node, presses the button, prints a BAKE line and quits the editor.
##
## Run: godot --editor --path sandbox/compat-lighting -- --bake=low [--bounces=3] [--texel=1.0] [--name=low]
## The bake lands in res://bakes/bake_<name>.lmbake, next to the scene.

const QUALITIES := {
	"low": LightmapGI.BAKE_QUALITY_LOW,
	"medium": LightmapGI.BAKE_QUALITY_MEDIUM,
	"high": LightmapGI.BAKE_QUALITY_HIGH,
	"ultra": LightmapGI.BAKE_QUALITY_ULTRA,
}

var _quality := ""
var _bounces := 3
var _texel := 1.0
var _name := ""


func _enter_tree() -> void:
	_parse_args()
	if _quality != "":
		_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	var world := NightScene.build(6, true)
	var gi := LightmapGI.new()
	gi.name = "LightmapGI"
	gi.quality = QUALITIES[_quality]
	gi.bounces = _bounces
	gi.texel_scale = _texel
	# Default environment_mode is the scene's sky, which floods the bake with a bright blue fill.
	gi.environment_mode = LightmapGI.ENVIRONMENT_MODE_CUSTOM_COLOR
	gi.environment_custom_color = Color(0.012, 0.016, 0.035)
	gi.environment_custom_energy = 1.0
	# With no light_data the button opens a file dialog; a saved placeholder makes it bake in place.
	var lmbake := "res://bakes/bake_%s.lmbake" % _name
	ResourceSaver.save(LightmapGIData.new(), lmbake)
	gi.light_data = load(lmbake)
	world.add_child(gi)
	_set_owners(world, world)
	var packed := PackedScene.new()
	packed.pack(world)
	var scene_path := "res://bakes/bake_%s.tscn" % _name
	ResourceSaver.save(packed, scene_path)
	world.free()
	EditorInterface.open_scene_from_path(scene_path)
	await get_tree().create_timer(2.0).timeout

	var edited := EditorInterface.get_edited_scene_root()
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(edited.get_node("LightmapGI"))
	await get_tree().create_timer(1.0).timeout
	var button := _find_button(EditorInterface.get_base_control(), "Bake Lightmaps")
	if button == null:
		push_error("BAKE no 'Bake Lightmaps' button found")
		get_tree().quit(2)
		return
	var started := Time.get_ticks_msec()
	button.pressed.emit()
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	var size_kb := 0.0
	var file := FileAccess.open(lmbake, FileAccess.READ)
	if file != null:
		size_kb = file.get_length() / 1024.0
	print("BAKE ", JSON.stringify({
		"name": _name, "quality": _quality, "bounces": _bounces, "texel_scale": _texel,
		"seconds": snappedf(seconds, 0.1), "file_kb": snappedf(size_kb, 1.0), "exists": file != null,
	}))
	get_tree().quit()


func _set_owners(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_set_owners(child, owner_node)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		var value := pair[1] if pair.size() > 1 else ""
		match pair[0]:
			"bake":
				_quality = value
				if _name == "":
					_name = value
			"bounces": _bounces = int(value)
			"texel": _texel = float(value)
			"name": _name = value

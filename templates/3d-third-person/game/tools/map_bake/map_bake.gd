@tool
extends EditorPlugin
## Bakes what only the editor can make for a map scene, the way a person does it by hand: the
## `ProtoBlock` meshes with their lightmap UV2, each `NavigationRegion3D`'s mesh and the
## `LightmapGI`. It is a tool, never enabled in a game: add `res://tools/map_bake/plugin.cfg` to
## `editor_plugins/enabled` in `project.godot` for the run and take it out again (an
## `override.cfg` does not enable an editor plugin: the editor read none from one in 4.7.2), then
## run the Forward+ editor with a window (a lightmap only bakes on a RenderingDevice; the headless
## editor bakes the meshes and the navigation and fails the lightmap):
##
##     gds godot -- --editor --rendering-method forward_plus --path game
##
## `MAP_BAKE_SCENES` names the scenes, comma-separated (default: the prototype level and its two
## sections). For each scene it opens it, makes again every block whose saved mesh does not match
## its size (or has none), bakes every navigation region (the mesh is saved to its own file
## when it has one), bakes the lightmap with the map's sun, saves the scene and prints a `BAKE`
## line (`MAP_BAKE_LIGHTMAPS=0` leaves the lightmaps as they are, for a headless run). A section
## has no sun of its own (the map's lights it), so a scene with no
## `DirectionalLight3D` gets `world/lighting/daylight.tscn` for the length of the bake: its light
## then matches the map's. It quits with 1 when something failed.

const DEFAULT_SCENES := [
	"res://world/prototype/prototype_level.tscn",
	"res://world/prototype/ai_section/ai_section.tscn",
	"res://world/prototype/pathing_section/pathing_section.tscn",
]
const DAYLIGHT := "res://world/lighting/daylight.tscn"

var _failed := false


func _enter_tree() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _scenes() -> Array:
	var named := OS.get_environment("MAP_BAKE_SCENES")
	if named.is_empty():
		return DEFAULT_SCENES
	return Array(named.split(",", false))


func _run() -> void:
	await _frames(240)
	for path: String in _scenes():
		await _bake_scene(path.strip_edges())
	print("BAKE done failed=", _failed)
	get_tree().quit(1 if _failed else 0)


func _bake_scene(path: String) -> void:
	print("BAKE open ", path)
	EditorInterface.open_scene_from_path(path)
	await _frames(60)
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != path:
		print("BAKE FAIL could not open ", path)
		_failed = true
		return
	var remade := 0
	for block: ProtoBlock in root.find_children("*", "ProtoBlock", true, false):
		if not mesh_matches(block):
			block.size = block.size  # The setter makes the mesh and its UV2 again.
			remade += 1
	await _frames(5)
	var regions := 0
	for region: NavigationRegion3D in root.find_children("*", "NavigationRegion3D", true, false):
		# The same parse and bake the game and the tests run, so the saved mesh matches theirs.
		var navigation_mesh := region.navigation_mesh
		var source := NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(navigation_mesh, source, region)
		NavigationServer3D.bake_from_source_geometry_data(navigation_mesh, source)
		if navigation_mesh != null and navigation_mesh.resource_path.begins_with("res://"):
			ResourceSaver.save(navigation_mesh)
		regions += 1
		print(
			"BAKE navigation ",
			root.get_path_to(region),
			" polygons=",
			navigation_mesh.get_polygon_count() if navigation_mesh != null else -1
		)
	var lightmaps := root.find_children("*", "LightmapGI", true, false)
	if OS.get_environment("MAP_BAKE_LIGHTMAPS") != "0":
		for lightmap: LightmapGI in lightmaps:
			await _bake_lightmap(root, lightmap, path)
	EditorInterface.mark_scene_as_unsaved()
	EditorInterface.save_scene()
	await _frames(10)
	print(
		"BAKE scene ",
		path,
		" blocks_remade=",
		remade,
		" regions=",
		regions,
		" lightmaps=",
		lightmaps.size()
	)


func _bake_lightmap(root: Node, lightmap: LightmapGI, path: String) -> void:
	if lightmap.light_data == null:
		var data_path := path.get_basename() + ".lmbake"
		ResourceSaver.save(LightmapGIData.new(), data_path)
		lightmap.light_data = load(data_path)
	var sun: Node = null
	if root.find_children("*", "DirectionalLight3D", true, false).is_empty():
		sun = (load(DAYLIGHT) as PackedScene).instantiate()
		root.add_child(sun)
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(lightmap)
	EditorInterface.edit_node(lightmap)
	await _frames(30)
	var button := _find_button(EditorInterface.get_base_control(), "Bake Lightmaps")
	var atlas := path.get_basename() + ".exr"
	var before := FileAccess.get_modified_time(atlas) if FileAccess.file_exists(atlas) else 0
	if button == null:
		print("BAKE FAIL no 'Bake Lightmaps' button for ", path)
		_failed = true
	else:
		var started := Time.get_ticks_msec()
		button.pressed.emit()
		await _frames(30)
		var baked := FileAccess.file_exists(atlas) and FileAccess.get_modified_time(atlas) > before
		print(
			"BAKE lightmap ",
			lightmap.light_data.resource_path,
			" seconds=",
			(Time.get_ticks_msec() - started) / 1000.0,
			" atlas_written=",
			baked
		)
		if not baked:
			print("BAKE FAIL the lightmap atlas ", atlas, " was not written")
			_failed = true
	if sun != null:
		root.remove_child(sun)
		sun.free()


## True when a block's saved mesh has the block's size (a block resized in a text editor keeps its
## old mesh until the editor makes it again).
static func mesh_matches(block: ProtoBlock) -> bool:
	if block.mesh == null:
		return false
	var expected := block.size
	if block.kind == ProtoBlock.Kind.CYLINDER:
		expected = Vector3(block.size.x, block.size.y, block.size.x)
	return block.mesh.get_aabb().size.is_equal_approx(expected)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null

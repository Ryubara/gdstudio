@tool
class_name ClipExport
extends EditorExportPlugin
## Leaves the clips nothing names out of a game's large animation libraries in every export: the
## pack holds each library of `ClipReferences.libraries()` with only the clips that the exported
## scripts, scenes and resources name (`ClipReferences.named_in`). The editor and the suites keep
## the full files, so a stand-in or any other clip is one inspector change away; the export after
## that change keeps it. A project that names no library is exported as it was. The `gds_game`
## editor plugin adds it.

var _keep: PackedStringArray = []
var _libraries: Dictionary[String, StringName] = {}


func _get_name() -> String:
	return "ClipExport"


func _begin_customize_resources(
	_platform: EditorExportPlatform, _features: PackedStringArray
) -> bool:
	_keep.clear()
	_libraries.clear()
	var libraries := ClipReferences.libraries()
	if libraries.is_empty():
		return false
	var names: Array[StringName] = []
	for library_name in libraries:
		names.append(library_name)
		_libraries[libraries[library_name]] = library_name
		var imported := _imported_path(libraries[library_name])
		if not imported.is_empty():
			_libraries[imported] = library_name
	var preset := get_export_preset()
	var files := preset.get_files_to_export() if preset != null else PackedStringArray()
	if files.is_empty():
		files = ClipReferences.project_files(preset.get_exclude_filter() if preset != null else "")
	_keep = ClipReferences.named_in(files, names, ClipReferences.catalogue())
	return true


# The export caches what it customized under this hash: a new clip list exports the libraries again.
func _get_customization_configuration_hash() -> int:
	return configuration_hash(_keep, _libraries)


func _customize_resource(resource: Resource, path: String) -> Resource:
	return customized(resource, path, _libraries, _keep)


## The hash of a clip list and the libraries it prunes.
static func configuration_hash(
	keep: PackedStringArray, libraries: Dictionary[String, StringName]
) -> int:
	return ("%s|%s" % [",".join(keep), str(libraries)]).hash()


## The copy of `resource` the export carries in its place: a library of `libraries` (by its file
## or its imported resource's path) with the clips of `keep` only, null for any other resource.
static func customized(
	resource: Resource,
	path: String,
	libraries: Dictionary[String, StringName],
	keep: PackedStringArray
) -> Resource:
	var library := resource as AnimationLibrary
	if library == null:
		return null
	var library_name: StringName = libraries.get(path, libraries.get(library.resource_path, &""))
	if library_name.is_empty():
		return null
	var out := ClipReferences.pruned(library, library_name, keep)
	print(
		(
			"ClipExport: %s keeps %d of %d clips"
			% [library_name, out.get_animation_list().size(), library.get_animation_list().size()]
		)
	)
	return out


func _begin_customize_scenes(_platform: EditorExportPlatform, _features: PackedStringArray) -> bool:
	return false


func _customize_scene(_scene: Node, _path: String) -> Node:
	return null


# The imported resource a source file's `.import` points at (`path=` under `[remap]`).
static func _imported_path(source: String) -> String:
	var config := ConfigFile.new()
	if config.load(source + ".import") != OK:
		return ""
	return str(config.get_value("remap", "path", ""))

class_name ClipReferences
extends RefCounted
## Which clips of a game's large animation libraries the game names, so an export can leave the
## rest out (`ClipExport`). A clip is named when a script, scene or resource the export carries
## holds its name as a string (`&"ual1/Pistol_Idle"` in a weapon's `.tres`, an inspector override
## in a `.tscn`) or a script names a constant of the game's clip catalogue that holds it
## (`CharacterClips.HIT`). The catalogue's own lists (its `ALL`, its stand-ins) name every clip and
## are not read: a stand-in is kept only when a scene, resource or script sets it.
##
## The project settings say what is pruned: `gds_game/clip_export/libraries` maps each library's
## name on the `AnimationPlayer` to its file (`{"ual1": "res://.../ual1.glb"}`; empty: nothing is
## pruned), `gds_game/clip_export/catalogue` is the catalogue script, and
## `gds_game/clip_export/keep` lists clips a game reaches only by a name it builds at run time.

const LIBRARIES_SETTING := "gds_game/clip_export/libraries"
const CATALOGUE_SETTING := "gds_game/clip_export/catalogue"
const KEEP_SETTING := "gds_game/clip_export/keep"
## The files read for names: scripts and text scenes and resources.
const READ: PackedStringArray = ["gd", "tscn", "tres"]


## The pruned libraries, by their name on the `AnimationPlayer`, each with its file.
static func libraries() -> Dictionary[StringName, String]:
	var out: Dictionary[StringName, String] = {}
	var setting: Variant = ProjectSettings.get_setting(LIBRARIES_SETTING, {})
	if setting is Dictionary:
		for library_name: Variant in setting:
			out[StringName(str(library_name))] = str(setting[library_name])
	return out


## The catalogue script, null when the project names none or it does not load.
static func catalogue() -> Script:
	var path := str(ProjectSettings.get_setting(CATALOGUE_SETTING, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Script


## The clips (`library/Clip`) of the libraries in `library_names` that `files` name, with the
## project's `keep` list, sorted. `catalogue` may be null.
static func named_in(
	files: PackedStringArray, library_names: Array[StringName], catalogue_script: Script
) -> PackedStringArray:
	var found: Dictionary[String, bool] = {}
	for clip: Variant in ProjectSettings.get_setting(KEEP_SETTING, PackedStringArray()):
		found[str(clip)] = true
	if library_names.is_empty():
		return PackedStringArray()
	var names: PackedStringArray = []
	for library_name in library_names:
		names.append(_escaped(String(library_name)))
	var literal := RegEx.create_from_string('"((?:%s)/[^"\\\\\\n]+)"' % "|".join(names))
	var constants := _clip_constants(catalogue_script, library_names)
	var reference: RegEx = null
	var catalogue_path := ""
	if catalogue_script != null and not catalogue_script.get_global_name().is_empty():
		catalogue_path = catalogue_script.resource_path
		reference = RegEx.create_from_string(
			"\\b%s\\.([A-Z_][A-Z0-9_]*)\\b" % _escaped(catalogue_script.get_global_name())
		)
	for path in files:
		if not READ.has(path.get_extension()) or path == catalogue_path:
			continue
		var text := FileAccess.get_file_as_string(path)
		if path.get_extension() == "gd":
			text = without_comments(text)
		for hit in literal.search_all(text):
			found[hit.get_string(1)] = true
		if reference != null:
			for hit in reference.search_all(text):
				var clip: String = constants.get(hit.get_string(1), "")
				if not clip.is_empty():
					found[clip] = true
	var out: PackedStringArray = []
	for clip in found:
		out.append(clip)
	out.sort()
	return out


## The scripts, scenes and resources under `root` that an export with `exclude_filter` (an export
## preset's comma-separated globs, `tests/*`) carries, for a run outside the editor.
static func project_files(exclude_filter: String, root := "res://") -> PackedStringArray:
	var globs: PackedStringArray = []
	for glob in exclude_filter.split(",", false):
		globs.append(glob.strip_edges())
	var out: PackedStringArray = []
	_walk(root, root, globs, out)
	out.sort()
	return out


## A copy of `library` (played as `library_name`) holding only the clips of `keep` it has.
static func pruned(
	library: AnimationLibrary, library_name: StringName, keep: PackedStringArray
) -> AnimationLibrary:
	var out := AnimationLibrary.new()
	for clip in library.get_animation_list():
		if keep.has("%s/%s" % [library_name, clip]):
			out.add_animation(clip, library.get_animation(clip))
	return out


## `source` with every `#` comment of GDScript left out (a `#` inside a string stays).
static func without_comments(source: String) -> String:
	var lines := source.split("\n")
	for i in lines.size():
		var line := lines[i]
		var quote := ""
		var at := 0
		while at < line.length():
			var c := line[at]
			if not quote.is_empty():
				if c == "\\":
					at += 1
				elif c == quote:
					quote = ""
			elif c == '"' or c == "'":
				quote = c
			elif c == "#":
				lines[i] = line.substr(0, at)
				break
			at += 1
	return "\n".join(lines)


static func _clip_constants(
	catalogue_script: Script, library_names: Array[StringName]
) -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	if catalogue_script == null:
		return out
	var map := catalogue_script.get_script_constant_map()
	for key: String in map:
		var value: Variant = map[key]
		if not (value is StringName or value is String):
			continue
		var clip := str(value)
		if library_names.has(StringName(clip.get_slice("/", 0))) and clip.contains("/"):
			out[key] = clip
	return out


static func _walk(
	root: String, folder: String, globs: PackedStringArray, out: PackedStringArray
) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			_walk(root, folder.path_join(sub), globs, out)
	for file in dir.get_files():
		var path := folder.path_join(file)
		if READ.has(file.get_extension()) and not _excluded(path.trim_prefix(root), globs):
			out.append(path)


static func _excluded(relative: String, globs: PackedStringArray) -> bool:
	for glob in globs:
		if relative.match(glob):
			return true
	return false


static func _escaped(text: String) -> String:
	var out := ""
	for c in text:
		out += "\\" + c if "\\^$.|?*+()[]{}".contains(c) else c
	return out

# `ClipReferences` and `ClipExport` of `gds_game` on their own, with files the test writes: a
# library clip is kept when a scene, a resource or a script names it, or a script names a catalogue
# constant that holds it; the catalogue's own lists, a comment, another library and an unlisted
# clip keep nothing; the export hands back a copy of a listed library with the kept clips only and
# leaves every other resource alone. A game's suite checks its own libraries and pack
# (3D Third Person's `test_export_clips.gd`).
extends GdUnitTestSuite

const FOLDER := "user://test_clip_export"
const CATALOGUE := "class_name ClipCatalogueOfTheTest\nextends RefCounted\n\n"
const LIBRARIES: Array[StringName] = [&"lib_a", &"lib_b"]

var _catalogue: Script


func before() -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER)
	_write(
		"catalogue.gd",
		(
			CATALOGUE
			+ 'const HIT := &"lib_a/Hit"\nconst DANCE := &"lib_a/Dance"\nconst OWN := &"own/Walk"\n'
			+ 'const ALL: Array[StringName] = [&"lib_a/Hit", &"lib_a/Dance", &"lib_b/Wave"]\n'
		)
	)
	_catalogue = load(FOLDER.path_join("catalogue.gd"))


func after() -> void:
	for file in DirAccess.get_files_at(FOLDER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FOLDER.path_join(file)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FOLDER))
	ProjectSettings.set_setting(ClipReferences.KEEP_SETTING, null)
	ProjectSettings.set_setting(ClipReferences.LIBRARIES_SETTING, null)


func _write(file: String, text: String) -> String:
	var path := FOLDER.path_join(file)
	var out := FileAccess.open(path, FileAccess.WRITE)
	out.store_string(text)
	out.close()
	return path


func _library(clips: Array[String]) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	for clip in clips:
		library.add_animation(clip, Animation.new())
	return library


func test_a_name_in_a_scene_a_resource_or_a_script_keeps_its_clip() -> void:
	var files: PackedStringArray = [
		_write("weapon.tres", '[gd_resource format=3]\n\n[resource]\ngrip_clip = &"lib_a/Grip"\n'),
		_write(
			"body.tscn",
			'[gd_scene format=3]\n\n[node name="A" type="Node"]\nclip = &"lib_b/Wave"\n'
		),
		_write(
			"state.gd",
			'extends Node\nvar clip := ClipCatalogueOfTheTest.HIT\nvar b := ["#", "lib_b/Jump"]\n'
		),
	]
	var kept := ClipReferences.named_in(files, LIBRARIES, _catalogue)
	assert_array(kept).contains_exactly(["lib_a/Grip", "lib_a/Hit", "lib_b/Jump", "lib_b/Wave"])


func test_the_catalogue_s_lists_a_comment_and_another_library_keep_nothing() -> void:
	var files: PackedStringArray = [
		FOLDER.path_join("catalogue.gd"),
		_write(
			"quiet.gd",
			(
				'extends Node\n## Play `lib_a/Dance` with "lib_a/Dance".\n'
				+ "var own := ClipCatalogueOfTheTest.OWN # ClipCatalogueOfTheTest.DANCE\n"
				+ 'var other := &"lib_c/Run"\n'
			)
		),
		_write("notes.json", '{"replaces": "lib_a/Idle"}'),
	]
	assert_array(ClipReferences.named_in(files, LIBRARIES, _catalogue)).is_empty()


func test_the_keep_setting_keeps_a_clip_named_at_run_time() -> void:
	ProjectSettings.set_setting(ClipReferences.KEEP_SETTING, PackedStringArray(["lib_b/Sit"]))
	assert_array(ClipReferences.named_in(PackedStringArray(), LIBRARIES, null)).contains_exactly(
		["lib_b/Sit"]
	)
	ProjectSettings.set_setting(ClipReferences.KEEP_SETTING, null)


func test_the_libraries_setting_maps_names_to_files() -> void:
	assert_dict(ClipReferences.libraries()).is_empty()
	ProjectSettings.set_setting(ClipReferences.LIBRARIES_SETTING, {"lib_a": "res://a.glb"})
	assert_dict(ClipReferences.libraries()).is_equal({&"lib_a": "res://a.glb"})
	ProjectSettings.set_setting(ClipReferences.LIBRARIES_SETTING, null)


func test_project_files_leave_the_excluded_folders_out() -> void:
	var files := ClipReferences.project_files("tests/*, tools/*")
	assert_bool(files.has("res://addons/gds_game/clip_export/clip_references.gd")).is_true()
	for path in files:
		assert_bool(path.begins_with("res://tests/")).override_failure_message(path).is_false()


func test_pruned_keeps_the_listed_clips_of_its_library_only() -> void:
	var library := _library(["Hit", "Dance", "Wave"])
	var out := ClipReferences.pruned(
		library, &"lib_a", PackedStringArray(["lib_a/Hit", "lib_b/Dance"])
	)
	assert_array(out.get_animation_list()).contains_exactly([&"Hit"])
	assert_object(out.get_animation(&"Hit")).is_same(library.get_animation(&"Hit"))
	assert_int(library.get_animation_list().size()).is_equal(3)


func test_the_export_prunes_a_listed_library_and_leaves_the_rest() -> void:
	var keep := PackedStringArray(["lib_a/Hit"])
	var by_path: Dictionary[String, StringName] = {"res://a.glb": &"lib_a"}
	var library := _library(["Hit", "Dance"])
	var out := ClipExport.customized(library, "res://a.glb", by_path, keep) as AnimationLibrary
	assert_array(out.get_animation_list()).contains_exactly([&"Hit"])
	assert_object(ClipExport.customized(library, "res://other.glb", by_path, keep)).is_null()
	assert_object(ClipExport.customized(Animation.new(), "res://a.glb", by_path, keep)).is_null()
	var hash_before := ClipExport.configuration_hash(keep, by_path)
	keep.append("lib_a/Dance")
	assert_int(ClipExport.configuration_hash(keep, by_path)).is_not_equal(hash_before)

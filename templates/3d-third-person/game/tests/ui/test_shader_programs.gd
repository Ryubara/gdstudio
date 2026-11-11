# The GL programs the web build links before the game draws (`MenuScene.shader_programs`, read by
# `ShaderPrelink`): the list is there, of this Godot and format, and every program names shaders it
# holds. A list of another Godot is skipped whole in the browser, so a new pinned Godot fails here
# until the list is recorded again (`tools/web_smoke/shader_programs.py --write`).
extends GdUnitTestSuite

# The template's recorded list holds 157 programs (kit issue #1164); far fewer means a run that
# stopped early wrote it.
const LEAST_PROGRAMS := 100


func _list() -> Dictionary:
	var scene := (load("res://ui/menus/menu_scene.tscn") as PackedScene).instantiate() as MenuScene
	var path := scene.shader_programs
	scene.free()
	assert_bool(FileAccess.file_exists(path)).is_true()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_bool(data is Dictionary).is_true()
	return data if data is Dictionary else {}


func test_the_list_is_of_this_godot_and_format() -> void:
	var data := _list()
	assert_str(ShaderPrelink.why_not(data)).is_empty()


func test_every_program_names_shaders_the_list_holds() -> void:
	var data := _list()
	var shaders: Array = data.get("shaders", [])
	var programs: Array = data.get("programs", [])
	assert_int(programs.size()).is_greater_equal(LEAST_PROGRAMS)
	for program: Array in programs:
		var stages: Array = program[0]
		assert_int(stages.size()).is_equal(2)
		for index: float in stages:
			assert_int(int(index)).is_between(0, shaders.size() - 1)

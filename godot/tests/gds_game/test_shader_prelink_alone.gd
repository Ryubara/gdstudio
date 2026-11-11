# On the clock: `ShaderPrelink.wait` gives up after real seconds, as a stuck page needs.
# `ShaderPrelink` of `gds_game` on its own, with a page of the test's (the browser's side is
# measured by the template's `tools/web_smoke/shader_programs.py`): a list of this Godot is handed
# to the page once and is done when the page says so; a list of another Godot, of another format,
# a missing file or a run off the web hands nothing and is done at once; `wait` ends at its
# timeout when the page never finishes.
extends GdUnitTestSuite

const LIST := "user://test_shader_prelink.json"

var calls: Array[String] = []
var page_state := {"done": false, "total": 4, "left": 4}


func before_test() -> void:
	ShaderPrelink.reset()
	calls.clear()
	page_state = {"done": false, "total": 4, "left": 4}


func after() -> void:
	ShaderPrelink.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LIST))


func _page(code: String) -> Variant:
	calls.append(code)
	for key: String in page_state:
		if code == "window.gdsPrelink.%s" % key:
			return page_state[key]
	return null


func _write(godot: String, format: int = ShaderPrelink.FORMAT) -> void:
	var data := {
		"format": format,
		"godot": godot,
		"shaders": [[35633, ["void main() {}"]], [35632, ["void main() {}"]]],
		"programs": [[[0, 1], [], null]],
	}
	var file := FileAccess.open(LIST, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func test_a_list_of_this_godot_goes_to_the_page_once_and_waits_for_it() -> void:
	_write(ShaderPrelink.engine_version())
	ShaderPrelink.page = _page
	assert_bool(ShaderPrelink.start(LIST)).is_true()
	assert_str(ShaderPrelink.skipped).is_empty()
	assert_str(calls[1]).is_equal(ShaderPrelink.PAGE_SCRIPT)
	assert_str(calls[2]).starts_with("window.gdsPrelink.start({")
	assert_bool(ShaderPrelink.is_done()).is_false()
	page_state.left = 1
	assert_float(ShaderPrelink.progress()).is_equal_approx(0.75, 0.001)
	var handed := calls.size()
	assert_bool(ShaderPrelink.start(LIST)).is_true()
	assert_int(calls.size()).is_equal(handed)
	page_state.done = true
	assert_bool(ShaderPrelink.is_done()).is_true()
	assert_float(ShaderPrelink.progress()).is_equal(1.0)


func test_a_list_of_another_godot_or_format_is_not_handed() -> void:
	_write("3.6-stable (official)")
	ShaderPrelink.page = _page
	assert_bool(ShaderPrelink.start(LIST)).is_false()
	assert_str(ShaderPrelink.skipped).contains("3.6")
	assert_bool(ShaderPrelink.is_done()).is_true()
	assert_bool(calls.has(ShaderPrelink.PAGE_SCRIPT)).is_false()
	ShaderPrelink.reset()
	_write(ShaderPrelink.engine_version(), ShaderPrelink.FORMAT + 1)
	ShaderPrelink.page = _page
	assert_bool(ShaderPrelink.start(LIST)).is_false()
	assert_str(ShaderPrelink.skipped).is_equal("another format")


func test_no_file_and_no_browser_do_nothing() -> void:
	ShaderPrelink.page = _page
	assert_bool(ShaderPrelink.start("user://no_such_list.json")).is_false()
	assert_str(ShaderPrelink.skipped).is_equal("no list")
	ShaderPrelink.reset()
	_write(ShaderPrelink.engine_version())
	assert_bool(ShaderPrelink.start(LIST)).is_false()
	assert_str(ShaderPrelink.skipped).is_equal("not a browser")
	assert_bool(ShaderPrelink.is_done()).is_true()
	assert_float(ShaderPrelink.progress()).is_equal(1.0)


func test_wait_ends_at_its_timeout_when_the_page_never_finishes() -> void:
	_write(ShaderPrelink.engine_version())
	ShaderPrelink.page = _page
	ShaderPrelink.start(LIST)
	var began := Time.get_ticks_msec()
	await ShaderPrelink.wait(get_tree(), 0.1)
	assert_bool(ShaderPrelink.is_done()).is_false()
	assert_int(Time.get_ticks_msec() - began).is_between(90, 2000)


func test_wait_ends_when_the_page_is_done() -> void:
	_write(ShaderPrelink.engine_version())
	ShaderPrelink.page = _page
	ShaderPrelink.start(LIST)
	get_tree().create_timer(0.05).timeout.connect(func() -> void: page_state.done = true)
	await ShaderPrelink.wait(get_tree(), 5.0)
	assert_bool(ShaderPrelink.is_done()).is_true()

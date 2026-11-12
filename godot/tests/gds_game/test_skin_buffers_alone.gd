# `SkinBuffers` of `gds_game` on its own (the browser's side is measured by 3D Third Person's
# `tools/bench/mannequin_draw_bench.py`): the page script goes first in the head, once however many
# export passes write it, and a page with no head is left alone; the script only changes empty
# dynamic array buffers, on a Direct3D renderer, and can be turned off.
extends GdUnitTestSuite

const PAGE := "<html><head><meta charset='utf-8'><script>engine()</script></head></html>"


func test_the_script_goes_first_in_the_head() -> void:
	var page := SkinBuffers.with_page_script(PAGE)
	assert_int(page.find(SkinBuffers.PAGE_MARK)).is_greater(page.find("<head>"))
	assert_int(page.find(SkinBuffers.PAGE_MARK)).is_less(page.find("engine()"))
	assert_int(page.find(SkinBuffers.PAGE_MARK)).is_less(page.find("<meta"))


func test_a_second_pass_writes_it_once() -> void:
	var page := SkinBuffers.with_page_script(SkinBuffers.with_page_script(PAGE))
	assert_int(page.count(SkinBuffers.PAGE_MARK)).is_equal(1)


func test_a_page_with_no_head_is_left_alone() -> void:
	assert_str(SkinBuffers.with_page_script("<body></body>")).is_equal("<body></body>")


func test_the_script_changes_only_empty_dynamic_array_buffers_on_direct3d() -> void:
	var script := SkinBuffers.PAGE_SCRIPT
	assert_str(script).contains("target === 0x8892")
	assert_str(script).contains("usage === 0x88E8")
	assert_str(script).contains("typeof size === 'number'")
	assert_str(script).contains("usage = 0x88E4")
	assert_str(script).contains("indexOf('Direct3D')")
	assert_str(script).contains("!window.gdsSkinBuffersOff")


func test_the_export_writes_the_page_once() -> void:
	var html := "user://test_skin_buffers_page/index.html"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(html.get_base_dir()))
	var file := FileAccess.open(html, FileAccess.WRITE)
	file.store_string(PAGE)
	file.close()
	assert_str(SkinBuffersExport.serve(html)).is_empty()
	assert_str(SkinBuffersExport.serve(html)).is_empty()
	assert_int(FileAccess.get_file_as_string(html).count(SkinBuffers.PAGE_MARK)).is_equal(1)
	assert_str(SkinBuffersExport.serve("user://no_such_page/index.html")).starts_with("no page")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(html))

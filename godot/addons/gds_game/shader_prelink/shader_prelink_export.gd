@tool
class_name ShaderPrelinkExport
extends EditorExportPlugin
## Has a web export start its GL program list from the page, before the engine boots: copies the
## list (`ShaderPrelink.list_path()`) beside `index.html` and writes the page's start into its head
## (`ShaderPrelink.with_page_start`). A project without a list, a list of another Godot or format,
## or another platform's export is left as it was. The `gds_game` editor plugin adds it.

var _html := ""


func _get_name() -> String:
	return "ShaderPrelink"


func _export_begin(features: PackedStringArray, _is_debug: bool, path: String, _flags: int) -> void:
	_html = path if features.has("web") else ""


# The web export has written `index.html` by now: Godot ends an export's plugins after its files.
func _export_end() -> void:
	if _html.is_empty():
		return
	var html_path := _html
	_html = ""
	var why := serve(ShaderPrelink.list_path(), html_path)
	if not why.is_empty():
		print("ShaderPrelink: the page does not start the list (%s)" % why)


## Copies the list at `list` beside the page at `html_path` and writes the page's start into it.
## Answers why it did not, empty when it did.
static func serve(list: String, html_path: String) -> String:
	if not FileAccess.file_exists(list):
		return "no list at %s" % list
	var text := FileAccess.get_file_as_string(list)
	var why := ShaderPrelink.why_not(JSON.parse_string(text))
	if not why.is_empty():
		push_warning("ShaderPrelink: %s is not served beside the page (%s)" % [list, why])
		return why
	var html := FileAccess.get_file_as_string(html_path)
	if html.is_empty():
		return "no page at %s" % html_path
	var name := list.get_file()
	var out := FileAccess.open(html_path.get_base_dir().path_join(name), FileAccess.WRITE)
	if out == null:
		return "cannot write %s beside the page" % name
	out.store_string(text)
	out.close()
	var started := ShaderPrelink.with_page_start(html, name)
	if started == html:
		return "" if html.contains(ShaderPrelink.PAGE_MARK) else "the page has no head"
	var page := FileAccess.open(html_path, FileAccess.WRITE)
	if page == null:
		return "cannot write %s" % html_path
	page.store_string(started)
	page.close()
	return ""

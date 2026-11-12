@tool
class_name SkinBuffersExport
extends EditorExportPlugin
## Writes `SkinBuffers.PAGE_SCRIPT` into a web export's `index.html`, first in its head, so the page
## wraps `bufferData` before the engine makes its context. Another platform's export is left as it
## was. The `gds_game` editor plugin adds it.

var _html := ""


func _get_name() -> String:
	return "SkinBuffers"


func _export_begin(features: PackedStringArray, _is_debug: bool, path: String, _flags: int) -> void:
	_html = path if features.has("web") else ""


# The web export has written `index.html` by now: Godot ends an export's plugins after its files.
func _export_end() -> void:
	if _html.is_empty():
		return
	var why := serve(_html)
	_html = ""
	if not why.is_empty():
		print("SkinBuffers: the page does not have the script (%s)" % why)


## Writes the script into the page at `html_path`. Answers why it did not, empty when it did or the
## page already had it.
static func serve(html_path: String) -> String:
	var html := FileAccess.get_file_as_string(html_path)
	if html.is_empty():
		return "no page at %s" % html_path
	var served := SkinBuffers.with_page_script(html)
	if served == html:
		return "" if html.contains(SkinBuffers.PAGE_MARK) else "the page has no head"
	var page := FileAccess.open(html_path, FileAccess.WRITE)
	if page == null:
		return "cannot write %s" % html_path
	page.store_string(served)
	page.close()
	return ""

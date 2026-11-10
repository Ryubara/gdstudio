class_name MenuProbe
extends Node
## For browser tests of the menu scene: when the page is opened with `?probe`, a few times a second
## this writes the menu fields (`UiProbeFields`) to `window.gdprobe` with `menu` set, so a script
## that drives the page can tell which screen is up and where its focused button is. It does
## nothing off the web or without `?probe`.

## Seconds between two writes.
const PERIOD := 0.1

var _object: JavaScriptObject
var _since := 0.0


func _ready() -> void:
	set_process(false)
	if not OS.has_feature("web"):
		return
	if not JavaScriptBridge.eval("new URLSearchParams(window.location.search).has('probe')"):
		return
	_object = JavaScriptBridge.create_object("Object")
	JavaScriptBridge.get_interface("window").gdprobe = _object
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func _process(delta: float) -> void:
	_since += delta
	if _since < PERIOD:
		return
	_since = 0.0
	_object.menu = true
	_object.ready = true
	var view := get_viewport().get_visible_rect().size
	_object.canvas_w = view.x
	_object.canvas_h = view.y
	UiProbeFields.write(_object, get_viewport())

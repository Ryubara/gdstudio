class_name WebProbe
extends Node
## For browser tests of the web build: when the page is opened with `?probe`, a few times a
## second this writes `ready` and the frames drawn to `window.gdprobe`, so a script that drives
## the page (the canvas is one picture, with nothing to read) can tell the game is running. The
## kit's web boot check waits for it (`tools/web_smoke/boot_check.py`). It does nothing off the
## web or without `?probe`, so a player's page pays for no bridge calls. A game that has more to
## say replaces this script (3D Third Person does) and keeps `ready`.

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
	set_process(true)


func _process(delta: float) -> void:
	_since += delta
	if _since < PERIOD:
		return
	_since = 0.0
	_object.ready = true
	_object.frames = Engine.get_frames_drawn()

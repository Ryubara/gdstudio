class_name LoadingScreen
extends UIScreen
## Reads a scene in the background and switches to it. Push it with the scene's path as the
## `scene` param: `UIRouter.replace(LOADING, UITransition.Kind.FADE, {"scene": "res://main.tscn"})`.
## A progress bar shows how far the read is; when it ends the scene becomes the current one and the
## router's screens leave with the fade. A scene that cannot be read shows a message and a way back.
## In a browser it also waits for the GL programs the menu scene had the page link
## (`ShaderPrelink`), at most `ShaderPrelink.TIMEOUT` seconds, and the bar counts them too.

## Seconds the screen stays up at least, so a fast read does not flash it.
@export_range(0.0, 3.0, 0.1, "suffix:s") var least_time := 0.4

var _path := ""
var _elapsed := 0.0
var _failed := false

@onready var _bar: HSlider = %Bar
@onready var _message: Label = %Message
@onready var _back: Button = %BackButton


func _ready() -> void:
	super._ready()
	allow_back = false
	_back.hide()
	_back.pressed.connect(_on_back)
	_path = str(params.get("scene", ""))
	# A path that is not there is a failure here, not a request: asking the loader for one prints
	# engine errors and leaves an object behind at exit.
	if _path.is_empty() or not ResourceLoader.exists(_path):
		_fail()
	elif ResourceLoader.load_threaded_request(_path) != OK:
		_fail()


func _process(delta: float) -> void:
	if _failed or _path.is_empty():
		return
	_elapsed += delta
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(_path, progress)
	if (
		status == ResourceLoader.THREAD_LOAD_FAILED
		or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
	):
		_fail()
		return
	var read := float(progress[0]) if not progress.is_empty() else 0.0
	var linked := ShaderPrelink.is_done() or _elapsed >= ShaderPrelink.TIMEOUT
	_bar.value = (read + (1.0 if linked else ShaderPrelink.progress())) * 50.0
	if status == ResourceLoader.THREAD_LOAD_LOADED and _elapsed >= least_time and linked:
		_enter()


func _enter() -> void:
	set_process(false)
	_bar.value = 100.0
	var scene := ResourceLoader.load_threaded_get(_path) as PackedScene
	if scene == null:
		_fail()
		return
	get_tree().change_scene_to_packed(scene)
	UIRouter.clear(UITransition.Kind.FADE)


func _fail() -> void:
	_failed = true
	set_process(false)
	_message.text = "Could not load the game."
	_back.show()
	allow_back = true
	_back.grab_focus()


func _on_back() -> void:
	UIRouter.replace("res://ui/menus/main_menu.tscn")

class_name WebProbe
extends Node
## For browser tests of the web build: when the page is opened with `?probe`, a few times a
## second this writes the player's state, the camera's angles and the touch layer's places to
## `window.gdprobe`, so a script that drives the page (the canvas is one picture, with nothing
## to read) can tell what happened. It does nothing off the web or without `?probe`, so a
## player's page pays for no bridge calls.

## Seconds between two writes.
const PERIOD := 0.1

@export_group("Nodes")
## The player read.
@export var player: Player
## The camera rig whose angles are read.
@export var camera_rig: PlayerCamera
## The touch layer whose places are read.
@export var touch: TouchControls

var _object: JavaScriptObject
var _since := 0.0
var _jumps := 0


func _ready() -> void:
	set_process(false)
	if not OS.has_feature("web") or player == null:
		return
	if not JavaScriptBridge.eval("new URLSearchParams(window.location.search).has('probe')"):
		return
	_object = JavaScriptBridge.create_object("Object")
	JavaScriptBridge.get_interface("window").gdprobe = _object
	player.jumped.connect(func() -> void: _jumps += 1)
	set_process(true)


func _process(delta: float) -> void:
	_since += delta
	if _since < PERIOD:
		return
	_since = 0.0
	var spot := player.global_position
	_object.ready = true
	_object.x = spot.x
	_object.y = spot.y
	_object.z = spot.z
	_object.speed = player.ground_speed()
	_object.state = int(player.state)
	_object.jumps = _jumps
	_object.on_floor = player.is_on_floor()
	if camera_rig != null:
		_object.yaw = camera_rig.yaw
		_object.pitch = camera_rig.pitch
	if touch != null:
		var view := get_viewport().get_visible_rect().size
		_object.canvas_w = view.x
		_object.canvas_h = view.y
		_object.touch_shown = touch.is_shown()
		_object.stick_x = touch.stick_vector().x
		_object.stick_y = touch.stick_vector().y
		var home := touch.stick_home()
		_object.home_x = home.x
		_object.home_y = home.y
		for index in touch.button_count():
			var centre := touch.button_center(index)
			_object.set("button%d_x" % index, centre.x)
			_object.set("button%d_y" % index, centre.y)
		_object.button_size = touch.button_size_of(0) if touch.button_count() > 0 else 0.0

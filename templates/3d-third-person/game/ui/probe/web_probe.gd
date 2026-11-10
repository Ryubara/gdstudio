class_name WebProbe
extends Node
## For browser tests of the web build: when the page is opened with `?probe`, a few times a
## second this writes the player's state, the camera's angles and the touch layer's places to
## `window.gdprobe`, so a script that drives the page (the canvas is one picture, with nothing
## to read) can tell what happened. It does nothing off the web or without `?probe`, so a
## player's page pays for no bridge calls.
##
## No scene holds a probe: the player rig calls `attach()` when it starts, and the probe is made
## only on a page opened with `?probe`.

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
var _shots := 0


## True on a web page opened with `?probe`.
static func asked() -> bool:
	return (
		OS.has_feature("web")
		and bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).has('probe')"))
	)


## Makes a probe under `parent` that reads these nodes, when the page asked for one; null
## otherwise (nothing is made off the web or without `?probe`).
static func attach(
	parent: Node, body: Player, rig: PlayerCamera, touch_layer: TouchControls
) -> WebProbe:
	if not asked():
		return null
	var probe := WebProbe.new()
	probe.name = &"WebProbe"
	probe.player = body
	probe.camera_rig = rig
	probe.touch = touch_layer
	parent.add_child(probe)
	return probe


func _ready() -> void:
	set_process(false)
	# The menus pause the tree: the probe keeps writing, so a test can read that it is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not asked() or player == null:
		return
	_object = JavaScriptBridge.create_object("Object")
	JavaScriptBridge.get_interface("window").gdprobe = _object
	player.jumped.connect(func() -> void: _jumps += 1)
	if player.weapon != null:
		player.weapon.fired.connect(func(_shot: Projectile) -> void: _shots += 1)
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
	_object.shots = _shots
	_object.crouching = player.crouching
	_object.aiming = player.aiming
	_object.aim_amount = player.aim_amount
	_object.fire_held = Input.is_action_pressed(&"fire")
	UiProbeFields.write(_object, get_viewport())
	var pause_button := get_node_or_null("../MenuLayer/PauseButton") as Control
	if pause_button != null:
		var middle := pause_button.get_global_transform() * (pause_button.size * 0.5)
		_object.pause_x = middle.x
		_object.pause_y = middle.y
		_object.pause_shown = pause_button.is_visible_in_tree()
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

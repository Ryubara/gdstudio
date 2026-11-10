## Runs the character forward while the camera turns, then zooms the minimap in and out with its
## input actions and opens the full-screen map, for a clip of the minimap.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/minimap_tour.tscn --seconds 12`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## Camera turn speed in degrees a second.
const TURN_SPEED := 35.0

var _time := 0.0
var _sent := {}

@onready var _rig: PlayerCamera = $Main/PlayerCamera


func _physics_process(delta: float) -> void:
	_time += delta
	if _time < 7.0:
		Input.action_press(&"move_forward", 1.0)
		_rig.orbit(Vector2(-TURN_SPEED * delta, 0.0))
	else:
		Input.action_release(&"move_forward")
	_tap(&"map_zoom_in", 3.0)
	_tap(&"map_zoom_in", 3.6)
	_tap(&"map_zoom_out", 5.0)
	_tap(&"map_zoom_out", 5.4)
	_tap(&"map", 8.0)
	_tap(&"map", 11.0)


func _tap(action: StringName, at: float) -> void:
	var key := "%s%s" % [action, at]
	if _time >= at and not _sent.has(key):
		_sent[key] = true
		_send(action, true)
	elif _time >= at + 0.15 and _sent.get(key, false):
		_sent[key] = false
		_send(action, false)


# Sends the action as an input event, as a key press would.
func _send(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)

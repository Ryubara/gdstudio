class_name AfterFrameReader
extends Node
## Calls `read` once after each frame has been worked out for drawing, before the next physics
## tick: where the engine draws a node then is its `get_global_transform_interpolated()` (physics
## interpolation's second pass, at the frame's end, has sent it to the renderer). A frame's own
## `_process`, `skeleton_updated` or `process_frame` come before that pass, and the next physics
## tick reads the plain transform, so a test that reads there sees what is placed, not what is
## drawn (gdstudio #1473). How: `ask()` in the frame queues an input event no game action uses;
## the engine hands buffered input out at the start of the next loop, before the tick, also in a
## headless run. Free it with `auto_free`.

const _MARK := 117

## What is called after the frame, with no arguments.
var read: Callable


## Asks for one call after this frame (call it while the frame is worked out, for example from
## `skeleton_updated`).
func ask() -> void:
	var event := InputEventMIDI.new()
	event.controller_number = _MARK
	Input.parse_input_event(event)


func _input(event: InputEvent) -> void:
	var midi := event as InputEventMIDI
	if midi != null and midi.controller_number == _MARK and read.is_valid():
		get_viewport().set_input_as_handled()
		read.call()

## Captures the level from a few angles: one view every `FRAMES_PER_VIEW` frames, then quits.
##
## Run it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/level_tour.tscn --seconds 3.5`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const FRAMES_PER_VIEW := 5
## Each view is where the camera stands and the point it looks at, in metres.
const VIEWS: Array[Array] = [
	[Vector3(21.0, 12.0, 21.0), Vector3(-2.0, 1.0, -3.0)],
	[Vector3(0.0, 1.7, 20.0), Vector3(0.0, 1.5, -20.0)],
	[Vector3(-22.0, 2.0, 22.0), Vector3(20.0, 1.0, -20.0)],
]

var _frame := 0

@onready var _camera: Camera3D = $Camera


func _ready() -> void:
	_show_view_for(0)


func _process(_delta: float) -> void:
	# The frame written is the one the last call set up, so the view is chosen a frame ahead.
	_frame += 1
	_show_view_for(_frame)


func _show_view_for(frame: int) -> void:
	var index := frame / FRAMES_PER_VIEW
	if index >= VIEWS.size():
		get_tree().quit()
		return
	_camera.position = VIEWS[index][0]
	_camera.look_at(VIEWS[index][1])

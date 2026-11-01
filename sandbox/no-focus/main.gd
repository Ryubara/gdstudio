extends ColorRect
## Shows a solid, bright colour that changes each frame, and reports how the window was set up.

var _frames: int = 0


func _ready() -> void:
	var w := get_window()
	print("PROBE mode=", w.mode, " flags_no_focus=", w.unfocusable, " pos=", w.position, " size=", w.size,
		" focused=", w.has_focus(), " driver=", DisplayServer.get_name())


func _process(_delta: float) -> void:
	_frames += 1
	color = Color.from_hsv(fmod(_frames * 0.07, 1.0), 0.8, 0.9)
	if _frames % 20 == 0:
		print("PROBE frame ", _frames, " t=", Time.get_ticks_msec(), " focused=", get_window().has_focus())

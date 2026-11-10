@tool
class_name MenuFit
extends Control
## Lays a menu out for the screen it is on. The project stretches a 1920 x 1080 design to any
## window, so on a phone held sideways (844 x 390 points) one unit is a third of a point and a
## 52-unit button is 19 points: too small for a finger. On a phone this control is `phone_factor`
## times smaller than its parent and drawn that many times bigger, so its children lay out on a
## canvas half as tall and a button is a finger's size. On any other screen it is the parent's size.
##
## Put a menu's content under one MenuFit that fills the screen. It sets its own size and scale; do
## not anchor it.

## Whether the window is a phone's: its shorter side in pixels is under this.
@export_range(200, 1200, 1, "suffix:px") var phone_short_side := 500
## The shorter side up to which a touch screen counts as a phone's too: a web page on a phone has a
## canvas of twice its size in points.
@export_range(200, 2400, 1, "suffix:px") var touch_short_side := 1000
## How much bigger a phone draws the menu.
@export_range(1.0, 4.0, 0.1) var phone_factor := 2.0:
	set(value):
		phone_factor = value
		_fit()
## Overrides the detection: 0 decides by the screen, 1 never scales, 2 always scales (for a capture
## that shows the phone layout on a desktop window).
@export_enum("Detect", "Never", "Always") var force := 0:
	set(value):
		force = value
		_fit()


func _ready() -> void:
	var parent_control := get_parent_control()
	if parent_control != null:
		parent_control.resized.connect(_fit)
	if not Engine.is_editor_hint():
		get_window().size_changed.connect(_fit)
	_fit()


## The factor the menu is drawn at on this screen: `phone_factor` or 1.
func factor() -> float:
	if force == 1:
		return 1.0
	if force == 2:
		return phone_factor
	var window := get_window()
	if window == null or Engine.is_editor_hint():
		return 1.0
	var short_side := mini(window.size.x, window.size.y)
	var phone := short_side < phone_short_side
	phone = phone or (DisplayServer.is_touchscreen_available() and short_side < touch_short_side)
	return phone_factor if phone else 1.0


func _fit() -> void:
	var parent_control := get_parent_control()
	if parent_control == null:
		return
	var scale_by := factor()
	scale = Vector2.ONE * scale_by
	position = Vector2.ZERO
	size = parent_control.size / scale_by

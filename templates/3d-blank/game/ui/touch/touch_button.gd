@tool
class_name TouchButton
extends Control
## One round button of the touch layer: a node you place in the 2D editor (drag it, size it,
## anchor it), which presses an input action while a finger is on it. `TouchControls` finds
## every `TouchButton` under its `buttons_root`; the scene holds the look (a fill, a ring and a
## word), so restyle it there.

## How solid the fill is while nothing touches it.
const IDLE_FILL := 0.35
## How solid the fill is while a finger is on it.
const HELD_FILL := 0.9

## The input action it presses (`jump`, `interact`...).
@export var action: StringName = &"jump"
## The word on the button.
@export var label := "Jump":
	set(value):
		label = value
		_show_label()

## True while a finger is on it (the fill gets solid). `TouchControls` sets it.
var held := false:
	set(value):
		held = value
		_show_held()


func _ready() -> void:
	_show_label()
	_show_held()


## The button's middle in canvas pixels.
func center() -> Vector2:
	return get_global_rect().get_center()


## How far from the middle a finger still counts as on the button, in canvas pixels: a little
## past the edge, so a thumb that lands on the rim still presses.
func reach() -> float:
	return maxf(size.x, size.y) * 0.58


func _show_label() -> void:
	var text := get_node_or_null("%Label") as Label
	if text != null:
		text.text = label


func _show_held() -> void:
	var fill := get_node_or_null("%Fill") as Control
	if fill != null:
		fill.self_modulate.a = HELD_FILL if held else IDLE_FILL

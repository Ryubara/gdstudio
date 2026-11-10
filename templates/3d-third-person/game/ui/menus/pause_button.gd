class_name PauseButton
extends UIButton
## The way into the pause menu on a touch screen, which has no Esc key: a small button in the
## corner that shows while the touch controls do and opens the pause menu through the host.
## Put it in a `CanvasLayer` of the game scene; it takes its theme from the tokens because it is not
## under the router's stage.

@export_group("Nodes")
## The host that opens the pause menu.
@export var host: ScreenHost
## The touch layer whose visibility the button follows. Empty shows the button on any touch screen.
@export var touch: TouchControls
@export_group("Showing")
## Shows the button always, for a game that wants one on a computer too.
@export var always_shown := false


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	theme = UIThemeBuilder.build(UITokens.active())
	pressed.connect(_on_pressed)
	if touch != null:
		touch.shown_changed.connect(_on_touch_shown)
	_refresh()


## Shows or hides the button by the rules above.
func _refresh() -> void:
	if always_shown:
		show()
	elif touch != null:
		visible = touch.is_shown()
	else:
		visible = DisplayServer.is_touchscreen_available()


func _on_touch_shown(_shown: bool) -> void:
	_refresh()


func _on_pressed() -> void:
	if host != null:
		host.open_pause()

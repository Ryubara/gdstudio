@tool
class_name TouchControls
extends CanvasLayer
## Phone controls that press the game's own input actions, so gameplay code does not fork: a
## floating stick on the left (it appears where the thumb lands) that presses the four move
## actions, a drag zone on the right that turns the view (`look_turned`), and round buttons that
## press an action each. Pushing the stick out to its ring presses the sprint action.
##
## Everything you see is a node of `touch_controls.tscn`, so open the scene and arrange it in the
## 2D editor: move `TouchStick` to change where the stick waits, drag the `TouchButton` nodes (add
## one by instancing `touch_button.tscn` under `Buttons`), resize the two zones that decide which
## finger does what, restyle any part. The script reads their places and never draws. The editor
## shows the controls even when `show_mode` hides them in the game.
##
## It shows only on a touch screen: when the device has one, or at the first touch. A key or a
## pad button hides it again, and a mouse never does (a browser sends a finger as mouse motion
## too). While it shows, the engine's mouse emulation from touch is off, or every touch would
## also click.
##
## Each finger does one job, decided where it lands, and its own position is read (never the
## `relative` of a drag, which is wrong with two fingers down in a browser). The view turns a
## share of what was dragged every drawn frame, not once per finger sample.

## The look finger dragged: turn the camera by `degrees` (x to the right, y down).
signal look_turned(degrees: Vector2)
## The layer appeared or went away.
signal shown_changed(shown: bool)

enum ShowMode {
	AUTO,  ## Only on a touch screen: at its first touch.
	ALWAYS,  ## Always (to try it on a computer).
	NEVER,  ## Never.
}

@export_group("When it shows")
## Auto shows it on a touch screen only; the other two force it.
@export var show_mode: ShowMode = ShowMode.AUTO
## Also shows the two zones (where a finger moves the character and where it turns the view) in
## the game. The editor always shows them.
@export var show_zones := false:
	set(value):
		show_zones = value
		_show_zones()

@export_group("Stick")
## The action the left stick presses pushed left.
@export var move_left: StringName = &"move_left"
## The action the left stick presses pushed right.
@export var move_right: StringName = &"move_right"
## The action the left stick presses pushed up.
@export var move_forward: StringName = &"move_forward"
## The action the left stick presses pushed down.
@export var move_back: StringName = &"move_back"
## Pressed while the stick is out at its ring. Empty keeps the ring off.
@export var sprint_action: StringName = &"sprint":
	set(value):
		sprint_action = value
		_size_stick()
## How far the thumb goes for a full push.
@export_range(60.0, 320.0, 1.0, "suffix:px") var stick_radius := 150.0:
	set(value):
		stick_radius = value
		_size_stick()
## The share of the radius that is ignored around the middle.
@export_range(0.0, 0.8, 0.01) var deadzone := 0.15
## Past this share of the radius the sprint action is pressed.
@export_range(0.5, 1.0, 0.01) var sprint_ring := 0.92:
	set(value):
		sprint_ring = value
		_size_stick()

@export_group("Look")
## Degrees the view turns for a drag of one pixel (a pixel of the 1080-high canvas).
@export_range(0.01, 1.0, 0.01, "suffix:deg/px") var look_sensitivity := 0.1
## How closely the view follows a drag: higher follows sooner. Zero turns it at once.
@export_range(0.0, 80.0, 1.0, "suffix:1/s") var look_smoothing := 30.0
## A finger on a button also turns the view when it drags, so the thumb that jumps can still
## look.
@export var buttons_also_look := true

@export_group("Look of the controls")
## How solid the controls are drawn.
@export_range(0.1, 1.0, 0.01) var opacity := 0.5:
	set(value):
		opacity = value
		_show_opacity()
## The room kept between the controls and the screen edge, on top of the device's safe area.
@export_range(0.0, 240.0, 1.0, "suffix:px") var margin := 70.0:
	set(value):
		margin = value
		_fit_to_screen()

@export_group("Parts")
## The box the stick and the buttons sit in: the screen less the device's safe area and `margin`.
@export var safe_area: Control:
	set(value):
		safe_area = value
		update_configuration_warnings()
## The stick: the node is where it waits, its children are the rings and the knob.
@export var stick: TouchStick:
	set(value):
		stick = value
		update_configuration_warnings()
## The node whose `TouchButton` children are the buttons.
@export var buttons_root: Control:
	set(value):
		buttons_root = value
		update_configuration_warnings()
## A finger that lands inside this box and not on a button works the stick.
@export var move_zone: Control:
	set(value):
		move_zone = value
		update_configuration_warnings()
## A finger that lands inside this box and not on a button turns the view.
@export var look_zone: Control:
	set(value):
		look_zone = value
		update_configuration_warnings()

var _shown := false
var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_at := Vector2.ZERO
var _stick_push := Vector2.ZERO
var _look_fingers: Dictionary[int, Vector2] = {}
var _button_fingers: Dictionary[int, int] = {}
var _pending_look := Vector2.ZERO
var _pressed: Dictionary[StringName, float] = {}


func _ready() -> void:
	_fit_to_screen()
	_size_stick()
	_show_opacity()
	_show_zones()
	if Engine.is_editor_hint():
		return
	get_viewport().size_changed.connect(_fit_to_screen)
	var first := show_mode == ShowMode.ALWAYS
	first = first or (show_mode == ShowMode.AUTO and DisplayServer.is_touchscreen_available())
	_set_shown(first, true)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	_release_all()
	if _shown:
		Input.emulate_mouse_from_touch = true


func _process(delta: float) -> void:
	if _shown and not Engine.is_editor_hint():
		_turn_view(delta)


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if show_mode == ShowMode.AUTO and touch.pressed and not _shown:
			_set_shown(true)
		if _shown:
			if touch.pressed:
				_finger_down(touch.index, touch.position)
			else:
				_finger_up(touch.index)
	elif event is InputEventScreenDrag and _shown:
		var drag := event as InputEventScreenDrag
		_finger_moved(drag.index, drag.position)
	elif show_mode == ShowMode.AUTO and _shown and _is_other_device(event):
		_set_shown(false)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var parts := {
		"safe_area": safe_area,
		"stick": stick,
		"buttons_root": buttons_root,
		"move_zone": move_zone,
		"look_zone": look_zone,
	}
	for part_name: String in parts:
		if parts[part_name] == null:
			warnings.append("Set `%s` in the Parts group: the controls need that node." % part_name)
	return warnings


## True while the controls are on screen.
func is_shown() -> bool:
	return _shown


## The stick's push, each axis from -1 to 1 (x right, y down), deadzone taken out.
func stick_vector() -> Vector2:
	return _stick_push


## How many buttons there are: the `TouchButton` children of `buttons_root`.
func button_count() -> int:
	return _buttons().size()


## Where button `index` is, in canvas pixels: its centre.
func button_center(index: int) -> Vector2:
	return _buttons()[index].center()


## How wide button `index` is, in canvas pixels.
func button_size_of(index: int) -> float:
	return maxf(_buttons()[index].size.x, _buttons()[index].size.y)


## Where a stick rests, drawn faintly, until a thumb lands: canvas pixels.
func stick_home() -> Vector2:
	return stick.home() if stick != null else Vector2.ZERO


## The part of the canvas the controls keep to: the whole canvas less the device's safe area.
func safe_rect() -> Rect2:
	var view := get_viewport().get_visible_rect()
	var screen := Vector2(DisplayServer.screen_get_size())
	var window := Vector2(DisplayServer.window_get_size())
	if screen.x <= 0.0 or screen.y <= 0.0 or window.distance_to(screen) > 2.0:
		return view
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if safe.size.x <= 0.0:
		return view
	var view_scale := view.size / screen
	var left := maxf(safe.position.x, 0.0) * view_scale.x
	var top := maxf(safe.position.y, 0.0) * view_scale.y
	var right := maxf(screen.x - safe.end.x, 0.0) * view_scale.x
	var bottom := maxf(screen.y - safe.end.y, 0.0) * view_scale.y
	return Rect2(
		view.position + Vector2(left, top), view.size - Vector2(left + right, top + bottom)
	)


func _buttons() -> Array[TouchButton]:
	var found: Array[TouchButton] = []
	if buttons_root != null:
		for child in buttons_root.get_children():
			if child is TouchButton:
				found.append(child as TouchButton)
	return found


# Puts the safe area's edges inside the device's safe area, `margin` in from it.
func _fit_to_screen() -> void:
	if safe_area == null or not is_inside_tree():
		return
	var view := get_viewport().get_visible_rect()
	var inner := safe_rect() if not Engine.is_editor_hint() else view
	safe_area.offset_left = inner.position.x - view.position.x + margin
	safe_area.offset_top = inner.position.y - view.position.y + margin
	safe_area.offset_right = inner.end.x - view.end.x - margin
	safe_area.offset_bottom = inner.end.y - view.end.y - margin


func _size_stick() -> void:
	if stick != null:
		stick.configure(stick_radius, sprint_ring if sprint_action != &"" else 0.0)


func _show_opacity() -> void:
	if safe_area != null:
		safe_area.modulate.a = opacity


func _show_zones() -> void:
	var visible_zones := Engine.is_editor_hint() or show_zones
	for zone in [move_zone, look_zone]:
		if zone != null:
			(zone as Control).visible = visible_zones


func _is_other_device(event: InputEvent) -> bool:
	if event is InputEventKey:
		return (event as InputEventKey).pressed
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	return false


func _set_shown(value: bool, force := false) -> void:
	if value == _shown and not force:
		return
	_shown = value
	if not value:
		_release_all()
	Input.emulate_mouse_from_touch = not value
	visible = value
	shown_changed.emit(value)


func _finger_down(index: int, at: Vector2) -> void:
	var button := _button_at(at)
	if button >= 0:
		_button_fingers[index] = button
		_buttons()[button].held = true
		_press(_buttons()[button].action, 1.0)
		if buttons_also_look:
			_look_fingers[index] = at
		return
	if _in_zone(move_zone, at, true):
		if _stick_finger < 0:
			_stick_finger = index
			_stick_origin = at
			_stick_at = at
			_apply_stick()
	elif _in_zone(look_zone, at, false):
		_look_fingers[index] = at


# True when `at` is inside `zone`. A scene with no zone falls back to the left half of the
# screen for the stick and the right half for the look.
func _in_zone(zone: Control, at: Vector2, left_half: bool) -> bool:
	if zone != null:
		return zone.get_global_rect().has_point(at)
	var view := get_viewport().get_visible_rect()
	var on_left := at.x < view.position.x + view.size.x * 0.5
	return on_left == left_half


func _finger_moved(index: int, at: Vector2) -> void:
	if index == _stick_finger:
		_stick_at = at
		_apply_stick()
	if _look_fingers.has(index):
		_pending_look += (at - _look_fingers[index]) * look_sensitivity
		_look_fingers[index] = at


func _finger_up(index: int) -> void:
	if index == _stick_finger:
		_stick_finger = -1
		_apply_stick()
	if _button_fingers.has(index):
		var button := _buttons()[_button_fingers[index]]
		button.held = false
		_press(button.action, 0.0)
		_button_fingers.erase(index)
	_look_fingers.erase(index)


func _button_at(at: Vector2) -> int:
	var buttons := _buttons()
	for index in buttons.size():
		if at.distance_to(buttons[index].center()) <= buttons[index].reach():
			return index
	return -1


func _apply_stick() -> void:
	var push := Vector2.ZERO
	var sprint := false
	if _stick_finger >= 0:
		var stick_offset := (_stick_at - _stick_origin) / stick_radius
		var length := minf(stick_offset.length(), 1.0)
		sprint = length >= sprint_ring
		if length > deadzone:
			push = stick_offset.normalized() * ((length - deadzone) / (1.0 - deadzone))
	_stick_push = push
	_press(move_right, maxf(push.x, 0.0))
	_press(move_left, maxf(-push.x, 0.0))
	_press(move_back, maxf(push.y, 0.0))
	_press(move_forward, maxf(-push.y, 0.0))
	if sprint_action != &"":
		_press(sprint_action, 1.0 if sprint else 0.0)
	_show_stick()


func _show_stick() -> void:
	if stick == null:
		return
	if _stick_finger >= 0:
		stick.touch(_stick_origin, _stick_at)
	else:
		stick.rest()


func _press(action: StringName, strength: float) -> void:
	if not InputMap.has_action(action):
		return
	if strength > 0.0:
		Input.action_press(action, strength)
		_pressed[action] = strength
	elif _pressed.has(action):
		Input.action_release(action)
		_pressed.erase(action)


func _release_all() -> void:
	for action in _pressed.keys():
		Input.action_release(action)
	_pressed.clear()
	_stick_finger = -1
	_stick_push = Vector2.ZERO
	_look_fingers.clear()
	_button_fingers.clear()
	_pending_look = Vector2.ZERO
	for button in _buttons():
		button.held = false
	_show_stick()


func _turn_view(delta: float) -> void:
	if _pending_look.is_zero_approx():
		return
	var share := 1.0 if look_smoothing <= 0.0 else 1.0 - exp(-look_smoothing * delta)
	var turn := _pending_look * share
	_pending_look -= turn
	if _pending_look.length() < 0.001:
		turn += _pending_look
		_pending_look = Vector2.ZERO
	look_turned.emit(turn)

class_name TouchControls
extends CanvasLayer
## Phone controls that press the game's own input actions, so gameplay code does not fork: a
## floating stick on the left (it appears where the thumb lands) that presses the four move
## actions, a drag zone on the right that turns the view (`look_turned`), and round buttons that
## press an action each. Pushing the stick out to its ring presses the sprint action.
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

const _SLOT_ANGLES := [180.0, 197.0, 238.0, 279.0]
const _ARC_RADIUS := 1.28
const _STICK_HOME := Vector2(0.17, 0.72)
const _WHITE := Color(1.0, 1.0, 1.0)

@export_group("When it shows")
## Auto shows it on a touch screen only; the other two force it.
@export var show_mode: ShowMode = ShowMode.AUTO

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
@export var sprint_action: StringName = &"sprint"
## How far the thumb goes for a full push.
@export_range(60.0, 320.0, 1.0, "suffix:px") var stick_radius := 150.0
## The share of the radius that is ignored around the middle.
@export_range(0.0, 0.8, 0.01) var deadzone := 0.15
## Past this share of the radius the sprint action is pressed.
@export_range(0.5, 1.0, 0.01) var sprint_ring := 0.92

@export_group("Look")
## Degrees the view turns for a drag of one pixel (a pixel of the 1080-high canvas).
@export_range(0.01, 1.0, 0.01, "suffix:deg/px") var look_sensitivity := 0.1
## How closely the view follows a drag: higher follows sooner. Zero turns it at once.
@export_range(0.0, 80.0, 1.0, "suffix:1/s") var look_smoothing := 30.0
## A finger on a button also turns the view when it drags, so the thumb that jumps can still
## look.
@export var buttons_also_look := true

@export_group("Buttons")
## The buttons on the right.
@export var buttons: Array[TouchButton] = []
## How wide a button is.
@export_range(80.0, 320.0, 1.0, "suffix:px") var button_size := 170.0
## How solid the controls are drawn.
@export_range(0.1, 1.0, 0.01) var opacity := 0.5
## The room kept between the controls and the screen edge, on top of the device's safe area.
@export_range(0.0, 240.0, 1.0, "suffix:px") var margin := 70.0

var _shown := false
var _canvas: Control
var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_at := Vector2.ZERO
var _stick := Vector2.ZERO
var _look_fingers: Dictionary[int, Vector2] = {}
var _button_fingers: Dictionary[int, int] = {}
var _pending_look := Vector2.ZERO
var _pressed: Dictionary[StringName, float] = {}


func _ready() -> void:
	layer = 100
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)
	var first := show_mode == ShowMode.ALWAYS
	first = first or (show_mode == ShowMode.AUTO and DisplayServer.is_touchscreen_available())
	_set_shown(first, true)


func _exit_tree() -> void:
	_release_all()
	if _shown:
		Input.emulate_mouse_from_touch = true


func _process(delta: float) -> void:
	if not _shown:
		return
	_turn_view(delta)
	_canvas.queue_redraw()


func _input(event: InputEvent) -> void:
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


## True while the controls are on screen.
func is_shown() -> bool:
	return _shown


## The stick's push, each axis from -1 to 1 (x right, y down), deadzone taken out.
func stick_vector() -> Vector2:
	return _stick


## Where button `index` is, in canvas pixels: its centre.
func button_center(index: int) -> Vector2:
	var area := _safe_rect().grow(-margin)
	var corner := Vector2(area.end.x - button_size / 2.0, area.end.y - button_size / 2.0)
	var slot := clampi(buttons[index].slot, 0, _SLOT_ANGLES.size() - 1)
	if slot == 0:
		return corner
	var angle := deg_to_rad(_SLOT_ANGLES[slot])
	return corner + Vector2(cos(angle), sin(angle)) * button_size * _ARC_RADIUS


## Where a stick rests, drawn faintly, until a thumb lands: canvas pixels.
func stick_home() -> Vector2:
	var area := _safe_rect().grow(-margin)
	return area.position + area.size * _STICK_HOME


## The part of the canvas the controls keep to: the whole canvas less the device's safe area.
func _safe_rect() -> Rect2:
	var view := get_viewport().get_visible_rect()
	var screen := Vector2(DisplayServer.screen_get_size())
	var window := Vector2(DisplayServer.window_get_size())
	if screen.x <= 0.0 or screen.y <= 0.0 or window.distance_to(screen) > 2.0:
		return view
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if safe.size.x <= 0.0:
		return view
	var scale := view.size / screen
	var left := maxf(safe.position.x, 0.0) * scale.x
	var top := maxf(safe.position.y, 0.0) * scale.y
	var right := maxf(screen.x - safe.end.x, 0.0) * scale.x
	var bottom := maxf(screen.y - safe.end.y, 0.0) * scale.y
	return Rect2(
		view.position + Vector2(left, top), view.size - Vector2(left + right, top + bottom)
	)


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
		_press(buttons[button].action, 1.0)
		if buttons_also_look:
			_look_fingers[index] = at
		return
	var view := get_viewport().get_visible_rect()
	if at.x < view.position.x + view.size.x * 0.5:
		if _stick_finger < 0:
			_stick_finger = index
			_stick_origin = at
			_stick_at = at
			_apply_stick()
	else:
		_look_fingers[index] = at


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
		_press(buttons[_button_fingers[index]].action, 0.0)
		_button_fingers.erase(index)
	_look_fingers.erase(index)


func _button_at(at: Vector2) -> int:
	for index in buttons.size():
		if at.distance_to(button_center(index)) <= button_size * 0.58:
			return index
	return -1


func _apply_stick() -> void:
	var push := Vector2.ZERO
	var sprint := false
	if _stick_finger >= 0:
		var offset := (_stick_at - _stick_origin) / stick_radius
		var length := minf(offset.length(), 1.0)
		sprint = length >= sprint_ring
		if length > deadzone:
			push = offset.normalized() * ((length - deadzone) / (1.0 - deadzone))
	_stick = push
	_press(move_right, maxf(push.x, 0.0))
	_press(move_left, maxf(-push.x, 0.0))
	_press(move_back, maxf(push.y, 0.0))
	_press(move_forward, maxf(-push.y, 0.0))
	if sprint_action != &"":
		_press(sprint_action, 1.0 if sprint else 0.0)


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
	_stick = Vector2.ZERO
	_look_fingers.clear()
	_button_fingers.clear()
	_pending_look = Vector2.ZERO


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


func _draw_controls() -> void:
	if not _shown:
		return
	var tint := Color(_WHITE, opacity)
	var faint := Color(_WHITE, opacity * 0.45)
	var touching := _stick_finger >= 0
	var centre := _stick_origin if touching else stick_home()
	_canvas.draw_arc(centre, stick_radius, 0.0, TAU, 48, tint if touching else faint, 4.0, true)
	if sprint_action != &"":
		_canvas.draw_arc(centre, stick_radius * sprint_ring, 0.0, TAU, 48, faint, 2.0, true)
	var knob := centre
	if touching:
		knob = centre + (_stick_at - centre).limit_length(stick_radius)
	var knob_alpha := opacity * (0.8 if touching else 0.35)
	_canvas.draw_circle(knob, stick_radius * 0.36, Color(_WHITE, knob_alpha))
	var held_buttons := _button_fingers.values()
	for index in buttons.size():
		var spot := button_center(index)
		var held := held_buttons.has(index)
		_canvas.draw_circle(
			spot, button_size / 2.0, Color(_WHITE, opacity * (0.9 if held else 0.35))
		)
		_canvas.draw_arc(spot, button_size / 2.0, 0.0, TAU, 40, tint, 4.0, true)
		var font := ThemeDB.fallback_font
		var size := int(button_size * 0.22)
		var label := buttons[index].label
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var origin := spot + Vector2(-width / 2.0, size * 0.35)
		_canvas.draw_string(
			font, origin, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.08, 0.1, 0.14, 0.95)
		)

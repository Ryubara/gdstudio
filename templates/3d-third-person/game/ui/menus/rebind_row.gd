class_name RebindRow
extends UIRow
## One action of the controls page: its name, and two buttons showing what it is bound to on the
## keyboard and mouse and on a gamepad. Pressing a button waits for the next key, mouse button,
## pad button or pushed stick, and binds it (Escape cancels). The change goes through `Settings`,
## which keeps it for the next start; a control another action used is swapped over to it.
##
## The rows are made by `ControlsPage` from its list of actions: they are the one part of the
## settings screen that depends on the project's input map, not on its design.

## A row started or stopped waiting for a press.
signal listening_changed(listening: bool)

## What a button says while it waits.
const WAITING := "Press a button..."
const NOT_BOUND := "Not bound"

## The action this row binds.
var action: StringName = &""
## The actions a control may be swapped with: every row of the page.
var among: Array[StringName] = []

var _buttons: Array[UIButton] = []
var _waiting := -1


func _ready() -> void:
	super._ready()
	var holder := HBoxContainer.new()
	holder.add_theme_constant_override(&"separation", UITokens.active().space_sm)
	for device in [InputBindings.Device.KEYBOARD, InputBindings.Device.GAMEPAD]:
		var button := UIButton.new()
		button.variant = UIButton.Variant.SECONDARY
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(listen.bind(device))
		holder.add_child(button)
		_buttons.append(button)
	set_widths(0.0, UITokens.active().control_width * 1.6, false)
	set_control(holder)
	var settings := get_node_or_null("/root/Settings") as SettingsService
	if settings != null:
		settings.bindings_changed.connect(refresh)
	refresh()


func _input(event: InputEvent) -> void:
	if _waiting < 0:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			stop()
			get_viewport().set_input_as_handled()
			return
	if not InputBindings.is_bindable_press(event):
		return
	if InputBindings.device_of(event) != _waiting:
		return
	get_viewport().set_input_as_handled()
	var device := _waiting
	stop()
	_bind(event, device)


## The two buttons: keyboard and mouse first, gamepad second.
func buttons() -> Array[UIButton]:
	return _buttons


## Whether the row is waiting for a press.
func is_listening() -> bool:
	return _waiting >= 0


## Waits for the next press of `device` (`InputBindings.Device`) to bind to the action.
func listen(device: int) -> void:
	if _waiting >= 0:
		stop()
	_waiting = device
	_buttons[device].text = WAITING
	listening_changed.emit(true)


## Stops waiting and shows the binding again.
func stop() -> void:
	var was := _waiting >= 0
	_waiting = -1
	refresh()
	if was:
		listening_changed.emit(false)


## Shows what the action is bound to now.
func refresh() -> void:
	for device in _buttons.size():
		if device == _waiting:
			continue
		var events := InputBindings.events_of(action, device)
		_buttons[device].text = (
			InputBindings.label_of(events[0]) if not events.is_empty() else NOT_BOUND
		)


func _bind(event: InputEvent, device: int) -> void:
	var settings := get_node_or_null("/root/Settings") as SettingsService
	if settings != null:
		settings.rebind(action, event, among)
	else:
		InputBindings.rebind(action, InputBindings.for_map(event), among)
		refresh()
	_buttons[device].grab_focus()

class_name InputBindings
extends RefCounted
## What the controls screen needs of the `InputMap`: which device a binding is for, a name a player
## can read, and a plain-data form of an event for the settings file. A saved binding is never an
## `Object` (a file the player can edit must not make the game build one): it is a small dictionary
## that `event_from_data` checks before it makes an event.
##
## A binding is for the keyboard and mouse or for a gamepad. An action may have several of each (W
## and the up arrow); the screen rebinds the first of the device it was asked about and leaves the
## others alone.

enum Device { KEYBOARD, GAMEPAD }

## The least a stick or trigger must be pushed to count as the press that rebinds.
const AXIS_THRESHOLD := 0.6
## The largest key code a saved file may hold (Godot's keys, special keys included, fit in 25 bits).
const MAX_KEY_CODE := 1 << 25

const PAD_BUTTONS: Array[String] = [
	"A",
	"B",
	"X",
	"Y",
	"Back",
	"Guide",
	"Start",
	"Left stick press",
	"Right stick press",
	"Left bumper",
	"Right bumper",
	"D-pad up",
	"D-pad down",
	"D-pad left",
	"D-pad right",
]
const PAD_AXES: Array[String] = [
	"Left stick",
	"Left stick",
	"Right stick",
	"Right stick",
	"Left trigger",
	"Right trigger",
]
## The word for a stick pushed each way, by axis: negative first.
const AXIS_WORDS := {
	JOY_AXIS_LEFT_X: ["left", "right"],
	JOY_AXIS_LEFT_Y: ["up", "down"],
	JOY_AXIS_RIGHT_X: ["left", "right"],
	JOY_AXIS_RIGHT_Y: ["up", "down"],
}


## The device an event is for, or -1 when it is neither (a mouse move, a touch).
static func device_of(event: InputEvent) -> int:
	if event is InputEventKey or event is InputEventMouseButton:
		return Device.KEYBOARD
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return Device.GAMEPAD
	return -1


## The events of an action that belong to a device, in the order the map holds them.
static func events_of(action: StringName, device: int) -> Array[InputEvent]:
	var found: Array[InputEvent] = []
	if not InputMap.has_action(action):
		return found
	for event in InputMap.action_get_events(action):
		if device_of(event) == device:
			found.append(event)
	return found


## Whether two events are the same control: the same key, mouse button, pad button, or stick or
## trigger direction (what a player would call one button).
static func same_control(a: InputEvent, b: InputEvent) -> bool:
	if a == null or b == null or device_of(a) != device_of(b):
		return false
	return to_data(a) == to_data(b)


## Replaces the events of `action` for one device with `events`, keeping the other device's.
static func set_events(action: StringName, device: int, events: Array[InputEvent]) -> void:
	if not InputMap.has_action(action):
		return
	var keep: Array[InputEvent] = []
	for event in InputMap.action_get_events(action):
		if device_of(event) != device:
			keep.append(event)
	InputMap.action_erase_events(action)
	for event in keep:
		InputMap.action_add_event(action, event)
	for event in events:
		InputMap.action_add_event(action, event)


## Makes `event` the first binding of `action` for its device. When another action in `among`
## already uses that control, it takes the binding that `action` gave up, so no control is left
## doing two things. Returns the action that was swapped, or an empty name.
static func rebind(action: StringName, event: InputEvent, among: Array[StringName]) -> StringName:
	var device := device_of(event)
	if device < 0 or not InputMap.has_action(action):
		return &""
	var mine := events_of(action, device)
	var given_up: InputEvent = mine[0] if not mine.is_empty() else null
	var swapped := &""
	for other in among:
		if other == action:
			continue
		var theirs := events_of(other, device)
		for i in theirs.size():
			if same_control(theirs[i], event):
				if given_up != null:
					theirs[i] = given_up
				else:
					theirs.remove_at(i)
				set_events(other, device, theirs)
				swapped = other
				break
	var next: Array[InputEvent] = [event]
	for i in range(1, mine.size()):
		if not same_control(mine[i], event):
			next.append(mine[i])
	set_events(action, device, next)
	return swapped


## A short word for an event: "W", "Left mouse button", "A", "Right trigger".
static func label_of(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.physical_keycode != KEY_NONE:
			return key.as_text_physical_keycode()
		return OS.get_keycode_string(key.keycode)
	if event is InputEventMouseButton:
		return _mouse_label((event as InputEventMouseButton).button_index)
	if event is InputEventJoypadButton:
		var index := (event as InputEventJoypadButton).button_index
		if index >= 0 and index < PAD_BUTTONS.size():
			return PAD_BUTTONS[index]
		return "Button %d" % index
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		var axis := motion.axis
		var base := PAD_AXES[axis] if axis >= 0 and axis < PAD_AXES.size() else "Axis %d" % axis
		if not AXIS_WORDS.has(axis):
			return base
		var words: Array = AXIS_WORDS[axis]
		return "%s %s" % [base, words[1 if motion.axis_value > 0.0 else 0]]
	return ""


## The event as plain data for the settings file.
static func to_data(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.physical_keycode != KEY_NONE:
			return {"type": "key", "code": int(key.physical_keycode), "physical": true}
		return {"type": "key", "code": int(key.keycode), "physical": false}
	if event is InputEventMouseButton:
		return {"type": "mouse", "button": int((event as InputEventMouseButton).button_index)}
	if event is InputEventJoypadButton:
		return {"type": "pad_button", "button": int((event as InputEventJoypadButton).button_index)}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return {
			"type": "pad_axis",
			"axis": int(motion.axis),
			"direction": 1 if motion.axis_value > 0.0 else -1,
		}
	return {}


## An event from `to_data`'s form, or null when the data is not one (a hand-edited file).
static func event_from_data(data: Variant) -> InputEvent:
	if not data is Dictionary:
		return null
	var record: Dictionary = data
	match record.get("type", ""):
		"key":
			return _key_from(record)
		"mouse":
			var button: Variant = record.get("button")
			if not _is_whole(button):
				return null
			if int(button) < MOUSE_BUTTON_LEFT or int(button) > MOUSE_BUTTON_XBUTTON2:
				return null
			var click := InputEventMouseButton.new()
			click.button_index = int(button) as MouseButton
			return click
		"pad_button":
			var index: Variant = record.get("button")
			if not _is_whole(index) or int(index) < 0 or int(index) >= JOY_BUTTON_SDL_MAX:
				return null
			var press := InputEventJoypadButton.new()
			press.button_index = int(index) as JoyButton
			return press
		"pad_axis":
			var axis: Variant = record.get("axis")
			if not _is_whole(axis) or int(axis) < 0 or int(axis) >= JOY_AXIS_SDL_MAX:
				return null
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(axis) as JoyAxis
			var direction: Variant = record.get("direction", 1)
			motion.axis_value = -1.0 if _is_whole(direction) and int(direction) < 0 else 1.0
			return motion
	return null


## Whether a pressed event is one the controls screen can bind: a key (not Escape, which cancels),
## a mouse button, a pad button, or a stick or trigger pushed past `AXIS_THRESHOLD`. A held key
## repeating is not a press.
static func is_bindable_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.pressed and not key.echo and key.physical_keycode != KEY_ESCAPE
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		return click.pressed and click.button_index <= MOUSE_BUTTON_XBUTTON2
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	if event is InputEventJoypadMotion:
		return absf((event as InputEventJoypadMotion).axis_value) >= AXIS_THRESHOLD
	return false


## A copy of the event the map can hold: it answers every device, whichever pad pressed it, and
## keeps nothing of the press itself.
static func for_map(event: InputEvent) -> InputEvent:
	var copy := event.duplicate() as InputEvent
	copy.device = -1
	if copy is InputEventJoypadMotion:
		var motion := copy as InputEventJoypadMotion
		motion.axis_value = signf(motion.axis_value)
	elif copy is InputEventKey:
		var key := copy as InputEventKey
		key.pressed = false
		key.echo = false
	elif copy is InputEventMouseButton:
		var click := copy as InputEventMouseButton
		click.pressed = false
		click.position = Vector2.ZERO
		click.global_position = Vector2.ZERO
		click.button_mask = 0 as MouseButtonMask
	elif copy is InputEventJoypadButton:
		(copy as InputEventJoypadButton).pressed = false
	return copy


static func _key_from(record: Dictionary) -> InputEvent:
	var code: Variant = record.get("code")
	if not _is_whole(code) or int(code) <= 0 or int(code) >= MAX_KEY_CODE:
		return null
	var key := InputEventKey.new()
	if record.get("physical", true):
		key.physical_keycode = int(code) as Key
	else:
		key.keycode = int(code) as Key
	return key


static func _mouse_label(index: int) -> String:
	match index:
		MOUSE_BUTTON_LEFT:
			return "Left mouse button"
		MOUSE_BUTTON_RIGHT:
			return "Right mouse button"
		MOUSE_BUTTON_MIDDLE:
			return "Middle mouse button"
		MOUSE_BUTTON_WHEEL_UP:
			return "Mouse wheel up"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "Mouse wheel down"
	return "Mouse button %d" % index


## Whether a value from a file is a whole number a ConfigFile can hold (a float 3.0 counts).
static func _is_whole(value: Variant) -> bool:
	match typeof(value):
		TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(value) and value == floorf(value)
	return false

class_name ControlsPage
extends VBoxContainer
## The controls page of the settings screen: below its fixed rows (mouse sensitivity, invert) it
## adds a `RebindRow` for each action in `actions`. Add an action to the list and its row appears;
## an action the project does not have is skipped.

## A row started or stopped waiting for a press (the screen must not go back meanwhile).
signal listening_changed(listening: bool)

## The actions a player may rebind, in the order shown. Titles are the action names made readable.
@export var actions: Array[StringName] = [
	&"move_forward",
	&"move_back",
	&"move_left",
	&"move_right",
	&"jump",
	&"sprint",
	&"walk",
	&"crouch",
	&"prone",
	&"interact",
	&"lean_left",
	&"lean_right",
	&"aim",
	&"fire",
	&"reload",
	&"next_weapon",
	&"previous_weapon",
	&"toggle_unarmed",
	&"melee",
	&"weapon_1",
	&"weapon_2",
	&"hotbar_1",
	&"hotbar_2",
	&"hotbar_3",
	&"hotbar_4",
	&"shoulder_swap",
	&"inventory",
	&"pause",
]

var _rows: Array[RebindRow] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var shown: Array[StringName] = []
	for action in actions:
		if InputMap.has_action(action):
			shown.append(action)
	for action in shown:
		var row := RebindRow.new()
		row.action = action
		row.among = shown
		row.title = String(action).capitalize()
		row.listening_changed.connect(listening_changed.emit)
		add_child(row)
		_rows.append(row)


## The rebinding rows, in order.
func rebind_rows() -> Array[RebindRow]:
	return _rows


## Whether any row is waiting for a press.
func is_listening() -> bool:
	for row in _rows:
		if row.is_listening():
			return true
	return false


## Stops any row that is waiting.
func stop_listening() -> void:
	for row in _rows:
		if row.is_listening():
			row.stop()

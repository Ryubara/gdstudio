class_name PeekInput
extends RefCounted
## The peek lean's buttons as the command's held bits (gdstudio #1400), for `PlayerInput`: Q and
## E (`lean_left`, `lean_right`), a touch control's press of the same actions, and on a pad the
## d-pad's left and right while aim is held (`lean_left_pad`, `lean_right_pad`, bound beside the
## weapon switch: the d-pad switches weapons only while the aim is down). Held or toggled, by the
## player's Settings > Controls (`SETTING`), else by the player's `PeekTuning.input_mode`. A toggled
## lean stands up when the body may not lean (a sprint, a slide, lying down, a jump, a death).

## The player's option: on, a press leans and the next stands up.
const SETTING := &"controls/lean_toggle"

## The side the command asks to lean: -1 left, 1 right, 0 neither.
var side := 0
## True on a tick whose lean comes from the pad's d-pad (aim held): its weapon presses are not
## switches then.
var pad_leaning := false


## Reads the buttons for this tick. `from` is a node in the tree (for the settings autoload).
func step(player: Player, enabled: bool, from: Node) -> void:
	var toggle := toggles(player, from)
	pad_leaning = false
	if not enabled:
		if not toggle:
			side = 0
		return
	var aim := Input.is_action_pressed(&"aim")
	var pad_left := aim and _down(&"lean_left_pad")
	var pad_right := aim and _down(&"lean_right_pad")
	pad_leaning = pad_left or pad_right
	if toggle:
		if _pressed(&"lean_left") or (aim and _pressed(&"lean_left_pad")):
			side = 0 if side == -1 else -1
		if _pressed(&"lean_right") or (aim and _pressed(&"lean_right_pad")):
			side = 0 if side == 1 else 1
		if side != 0 and player != null and not _may_lean(player):
			side = 0
	else:
		var left := _down(&"lean_left") or pad_left
		var right := _down(&"lean_right") or pad_right
		side = 0 if left == right else (-1 if left else 1)


## True when a press toggles the lean: the player's option, else the tuning's mode.
static func toggles(player: Player, from: Node) -> bool:
	var settings := (
		from.get_node_or_null(^"/root/Settings") if from != null and from.is_inside_tree() else null
	)
	if settings != null and settings.has_method(&"get_value"):
		var value: Variant = settings.call(&"get_value", SETTING)
		if value is bool:
			return value
	var tuning := player.peek_tuning if player != null else null
	return tuning != null and tuning.input_mode == PeekTuning.InputMode.TOGGLE


# A body that may not lean now stands a toggled lean up (the step would end it anyway), as does a
# press of sprint.
func _may_lean(player: Player) -> bool:
	if Input.is_action_just_pressed(&"sprint"):
		return false
	return player.peek_motion.allowed(player) or not player.is_inside_tree()


static func _down(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)


static func _pressed(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)

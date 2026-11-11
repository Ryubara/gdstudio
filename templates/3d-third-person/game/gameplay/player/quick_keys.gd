class_name QuickKeys
extends RefCounted
## The number keys of the HUD's places: `weapon_1`, `weapon_2` take the first and second weapon of
## the loadout's round in hand, `hotbar_1` to `hotbar_N` use the hotbar's places (keys 1 and 2,
## then 3 on; a touch screen presses the same actions from the HUD's places). The actions are the
## project's, so a game rebinds or adds them in the Input Map; one the project lacks is passed over.
##
## `PlayerInput` asks it once a command for the places pressed since the last one. A press is the
## action going down between two commands (a key, a touch place's `Input.action_press`), or a press
## seen as an event while the action is up again (down and up in one frame): never both.

## The action of weapon place `n` (from 1).
const WEAPON_ACTION := "weapon_%d"
## The action of hotbar place `n` (from 1).
const HOTBAR_ACTION := "hotbar_%d"
## The most places of each kind that are looked for.
const MOST_PLACES := 12
## No loadout slot (-1 is the empty hands).
const NO_SLOT := -2

var _down: Dictionary[StringName, bool] = {}
var _latched: Dictionary[StringName, bool] = {}


## The action of weapon place `place` (from 0).
static func weapon_action(place: int) -> StringName:
	return StringName(WEAPON_ACTION % (place + 1))


## The action of hotbar place `place` (from 0).
static func hotbar_action(place: int) -> StringName:
	return StringName(HOTBAR_ACTION % (place + 1))


## The loadout slot weapon place `place` shows and takes in hand: the place-th of the loadout's
## round (its filled slots, then the empty hands), or `NO_SLOT` past its end.
static func weapon_slot_at(loadout: WeaponLoadout, place: int) -> int:
	if loadout == null:
		return NO_SLOT
	var order := WeaponChooser.round_of(loadout)
	return order[place] if place >= 0 and place < order.size() else NO_SLOT


## Notes an event's press of any place's action (call it from `_unhandled_input`).
func latch(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventJoypadButton):
		return
	for format in [WEAPON_ACTION, HOTBAR_ACTION]:
		for place in MOST_PLACES:
			var action := StringName(format % (place + 1))
			if not InputMap.has_action(action):
				break
			if event.is_action_pressed(action):
				_latched[action] = true


## The places of `format` (`WEAPON_ACTION` or `HOTBAR_ACTION`) pressed since the last call, from
## 0. Call it once a command for each format, even while the input is off, so a key held then is
## no press later.
func pressed(format: String) -> Array[int]:
	var found: Array[int] = []
	for place in MOST_PLACES:
		var action := StringName(format % (place + 1))
		if not InputMap.has_action(action):
			break
		var down := Input.is_action_pressed(action)
		var went_down: bool = down and not _down.get(action, false)
		if went_down or (bool(_latched.get(action, false)) and not down):
			found.append(place)
		_down[action] = down
		_latched.erase(action)
	return found

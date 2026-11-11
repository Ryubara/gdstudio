@tool
class_name HudWeaponSlots
extends HudSlotRow
## The weapon slots: numbered places that show the weapons the player carries, each with the key
## that takes it in hand (`weapon_1`, `weapon_2`: 1 and 2). Place `n` is the `n`-th weapon of the
## loadout's round (its filled slots, then the empty hands: the pistol and the fists today), the
## one in hand (or on its way there, however the switch was asked for) is lit, and a place with no
## weapon is its key alone. No rounds here: the ammo card is their one home.
##
## It reads the player's `loadout` and its signals and never writes: the keys are `PlayerInput`'s
## (`QuickKeys`), which switch by the same weapon presses a player makes, so online the lit place
## follows the loadout the server's word keeps.

@export_group("Places")
## How many weapon places show.
@export_range(1, 9, 1) var place_count := 2:
	set(value):
		place_count = value
		if Engine.is_editor_hint() and is_node_ready():
			_show_in_editor()
		else:
			update()

var _loadout: WeaponLoadout
var _input: PlayerInput


## The loadout slot place `place` shows (`QuickKeys.NO_SLOT` for none).
func slot_at(place: int) -> int:
	return QuickKeys.weapon_slot_at(_loadout, place)


## The place lit now (-1: none).
func lit_place() -> int:
	for place in _cells.size():
		if _cells[place].state == HudSlot.State.LIT:
			return place
	return -1


func _on_bound(node: Node) -> void:
	_loadout = node.get(&"loadout") as WeaponLoadout
	_input = node.get(&"controller") as PlayerInput
	for signal_name: StringName in [
		&"weapon_changed", &"switch_started", &"switch_finished", &"slots_changed"
	]:
		refresh_on(_loadout, signal_name)


func _let_go() -> void:
	super()
	_loadout = null
	_input = null


func _has_data() -> bool:
	return (
		_bound != null
		and _loadout != null
		and is_instance_valid(_loadout)
		and not WeaponChooser.round_of(_loadout).is_empty()
	)


func _place_count() -> int:
	return place_count


func _fill_place(cell: HudSlot, place: int) -> void:
	var slot := slot_at(place)
	if slot == QuickKeys.NO_SLOT:
		cell.show_place(key_text(place), null, "", HudSlot.State.EMPTY)
		return
	var definition: WeaponDef = (
		_loadout.unarmed if slot == WeaponLoadout.UNARMED else _loadout.slots[slot]
	)
	var state := HudSlot.State.LIT if slot == _chosen() else HudSlot.State.IDLE
	cell.show_place(key_text(place), definition.icon, "", state)
	cell.tooltip_text = definition.display_name


# The slot in hand, or the one a request or a switch is heading for.
func _chosen() -> int:
	if _input != null and _input.weapon_request() != PlayerInput.NO_REQUEST:
		return _input.weapon_request()
	return _loadout.target_slot()

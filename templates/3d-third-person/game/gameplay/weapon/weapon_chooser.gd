class_name WeaponChooser
extends RefCounted
## Which weapon press takes a `WeaponLoadout` one step toward a chosen slot, so a screen that picks
## a weapon (the inventory) sends nothing new: its controller presses `next_weapon`,
## `previous_weapon` or `toggle_unarmed` once a tick, as a player would, until the loadout is
## heading for the slot. The loadout's round (its slots in order, then the empty hands) is read
## from the loadout each time, so a weapon added at run time is reached too.

## No press: the loadout is already heading for the slot, or the slot cannot be reached.
const NONE := -1
## The presses, as indexes of `PlayerInput.WEAPON_ACTIONS`.
const NEXT := 1
const PREVIOUS := 2
const UNARMED := 3


## The press that moves `loadout` one step toward `slot` (`WeaponLoadout.UNARMED` for the empty
## hands), or `NONE`.
static func press_toward(loadout: WeaponLoadout, slot: int) -> int:
	if loadout == null:
		return NONE
	var from := loadout.target_slot()
	if from == slot or not can_reach(loadout, slot):
		return NONE
	if slot == WeaponLoadout.UNARMED:
		return UNARMED
	var order := round_of(loadout)
	var at := order.find(from)
	var to := order.find(slot)
	if at < 0:
		return NEXT
	var forward := posmod(to - at, order.size())
	var backward := posmod(at - to, order.size())
	return NEXT if forward <= backward else PREVIOUS


## Whether `slot` holds a weapon the loadout can switch to.
static func can_reach(loadout: WeaponLoadout, slot: int) -> bool:
	if slot == WeaponLoadout.UNARMED:
		return loadout.unarmed != null
	return slot >= 0 and slot < loadout.slots.size() and loadout.slots[slot] != null


## The loadout's round: its filled slots in order, then the empty hands when it has them (the
## order `next()` goes through).
static func round_of(loadout: WeaponLoadout) -> Array[int]:
	var order: Array[int] = []
	for index in loadout.slots.size():
		if loadout.slots[index] != null:
			order.append(index)
	if loadout.unarmed != null:
		order.append(WeaponLoadout.UNARMED)
	return order

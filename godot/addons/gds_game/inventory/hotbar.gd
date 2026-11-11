@tool
class_name Hotbar
extends Node
## A row of quick-access places, each naming a kind of item from the owner's `Inventory`: using a
## place uses one of that item (its `ItemDef.use_effect`, on `user`) and takes it out of the bag
## when the item is `consumed_on_use`. A place names the kind, not a bag slot, so moving stacks in
## the bag never changes the hotbar; a place whose item has run out keeps it (count 0) until it is
## assigned again or cleared.
##
## It is plain data and signals, beside the `Inventory` it reads: a HUD and an inventory screen
## draw it (both redraw on `changed`, which also follows the bag's counts) and call `assign`,
## `clear` and `use`. What presses a place (a number key, a tap on the HUD) is the game's.
##
## Networking: the bag is not sent over a network yet, so neither is this. On a peer whose bag is
## not its own word (an online client), `authoritative` is off and `use` is refused: the server
## would own the use, as it owns the health it changes.

## A place was assigned, cleared, or the count of an item it names changed.
signal changed
## `item` was used from `place`.
signal used(place: int, item: ItemDef)
## Using `place` was refused: it is empty, its item ran out, cannot be used now (a bandage at full
## health) or this peer is not `authoritative`.
signal use_refused(place: int, item: ItemDef)

@export_group("Places")
## How many places the row has. Fewer than before keeps the first ones.
@export_range(1, 12, 1, "or_greater") var place_count := 4:
	set(value):
		place_count = maxi(value, 1)
		_items.resize(place_count)
		if is_node_ready():
			changed.emit()
## What the places hold at the start, in order (an empty entry leaves its place empty).
@export var start_items: Array[ItemDef] = []

@export_group("Nodes")
## The bag the places count from and take out of. Empty: the first `Inventory` beside this node.
@export var inventory: Inventory
## Who an item is used on (its effect's `user`). Empty: the parent (the character).
@export var user: Node

@export_group("Network")
## Off: `use` is refused (an online client, where the server owns the bag and the health).
@export var authoritative := true

var _items: Array[ItemDef] = []


func _init() -> void:
	_items.resize(place_count)


func _ready() -> void:
	if inventory == null and get_parent() != null:
		for sibling in get_parent().get_children():
			if sibling is Inventory:
				inventory = sibling
				break
	if user == null:
		user = get_parent()
	for place in mini(start_items.size(), place_count):
		_items[place] = start_items[place]
	if inventory != null and not Engine.is_editor_hint():
		inventory.changed.connect(changed.emit)


## The `Hotbar` of `node`: `node` itself, or its first child that is one. Null when it has none.
static func of(node: Object) -> Hotbar:
	if node is Hotbar:
		return node
	var parent := node as Node
	if parent == null:
		return null
	for child in parent.get_children():
		if child is Hotbar:
			return child
	return null


## The item `place` names, or null (empty or out of range).
func item_at(place: int) -> ItemDef:
	return _items[place] if place >= 0 and place < _items.size() else null


## How many of `place`'s item the bag holds (0 for an empty place).
func count_at(place: int) -> int:
	var item := item_at(place)
	return inventory.count_of(item) if item != null and inventory != null else 0


## The place that names `item`, or -1.
func place_of(item: ItemDef) -> int:
	return _items.find(item) if item != null else -1


## Puts `item` in `place` (null clears it). An item sits in one place: a place that named it
## already is cleared. True when anything changed.
func assign(place: int, item: ItemDef) -> bool:
	if place < 0 or place >= _items.size() or _items[place] == item:
		return false
	var before := place_of(item)
	if before >= 0:
		_items[before] = null
	_items[place] = item
	changed.emit()
	return true


## Empties `place`. True when it held something.
func clear(place: int) -> bool:
	return assign(place, null) if item_at(place) != null else false


## Whether using `place` would do something now.
func can_use(place: int) -> bool:
	var item := item_at(place)
	if not authoritative or item == null or not item.is_usable() or count_at(place) <= 0:
		return false
	return item.use_effect.can_apply(user)


## Uses one of `place`'s item: its effect acts on `user` and, when the item is consumed on use,
## one comes out of the bag. True when it was used; `use_refused` otherwise.
func use(place: int) -> bool:
	var item := item_at(place)
	if not can_use(place) or not item.use_effect.apply(user):
		use_refused.emit(place, item)
		return false
	if item.consumed_on_use:
		inventory.remove(_last_slot_of(item), 1)
	used.emit(place, item)
	return true


# The last bag slot holding `item`: a use takes from the last stack and leaves the first ones full.
func _last_slot_of(item: ItemDef) -> int:
	for slot in range(inventory.slot_count - 1, -1, -1):
		if inventory.item_at(slot) == item:
			return slot
	return -1

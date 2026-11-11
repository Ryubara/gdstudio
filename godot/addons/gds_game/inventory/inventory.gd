class_name Inventory
extends Node
## A character's bag: `slot_count` numbered slots, each empty or holding a stack of one kind of item
## (an `ItemDef`, up to its `max_stack`). Items are added (filling the stacks of the same kind
## first, then the first empty slots), moved (onto an empty slot, onto a stack of the same kind to
## fill it, or onto another kind to swap), taken out and dropped into the world in front of the
## owner.
##
## It fills itself from pickups: the `collector`'s `collect_signal` (a `Character`'s
## `item_collected(item_id, amount, total)`) adds the `catalog` item whose `id` is the pickup's
## `item_id`; an id the catalog does not list is left to whatever else counts it (ammunition, a
## coin counter).
##
## It is plain data and signals: a screen draws it and calls `move`, `drop` and `remove`, and the
## game reads `count_of`. Nothing of it is sent over a network yet: in an online game the server
## would own it and a screen's move would be a request.

## Something in the bag changed (any slot). A screen redraws on it.
signal changed
## One slot changed.
signal slot_changed(slot: int)
## `count` of `item` went into the bag.
signal item_added(item: ItemDef, count: int)
## `count` of `item` left the bag by `drop`; `dropped` is what was placed in the world (or null).
signal item_dropped(item: ItemDef, count: int, dropped: Node)
## `count` of `item` did not fit and was not taken.
signal overflowed(item: ItemDef, count: int)

@export_group("Slots")
## How many slots the bag has. Fewer than before keeps the first ones and moves what was in the
## rest into free slots when it can (what still does not fit is lost, with `overflowed`).
@export_range(1, 200, 1, "or_greater") var slot_count := 16:
	set(value):
		var before := slot_count
		slot_count = maxi(value, 1)
		if is_node_ready() and slot_count != before:
			_resize(before)
## What the bag holds at the start, added in order (a stack bigger than its item's `max_stack`
## fills more slots).
@export var start_items: Array[ItemStack] = []

@export_group("Pickups")
## The kinds of item this bag takes from pickups, by their `id`.
@export var catalog: Array[ItemDef] = []
## The node whose `collect_signal` fills the bag. Empty: the parent.
@export var collector: Node
## The collector's signal that says something was picked up; its first two arguments are the
## item's id and the amount (a `Character`'s `item_collected`).
@export var collect_signal: StringName = &"item_collected"

@export_group("Drop")
## Where a dropped item appears from: `drop_offset` is in this node's space (for a character, its
## `Model` slot, which turns with it). Empty: the collector, when it is a `Node3D`.
@export var drop_origin: Node3D
## Where a dropped item appears, in `drop_origin`'s space, in metres (+Z is a character model's
## front): far enough not to be taken again at once.
@export var drop_offset := Vector3(0.0, 0.6, 1.6)
## The node a dropped item is added to. Empty: the parent of the collector (beside the character).
@export var drop_parent: Node

var _items: Array[ItemDef] = []
var _counts: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	_items.resize(slot_count)
	_counts.resize(slot_count)
	for stack in start_items:
		if stack != null and stack.item != null:
			add(stack.item, stack.count)
	if Engine.is_editor_hint():
		return
	var source := collector if collector != null else get_parent()
	if source != null and source.has_signal(collect_signal):
		source.connect(collect_signal, _on_collected)


## The item in `slot`, or null for an empty slot or one out of range.
func item_at(slot: int) -> ItemDef:
	return _items[slot] if _in_range(slot) else null


## How many are in `slot` (0 when it is empty).
func count_at(slot: int) -> int:
	return _counts[slot] if _in_range(slot) else 0


## True when `slot` holds nothing.
func is_empty(slot: int) -> bool:
	return item_at(slot) == null


## How many of `item` the bag holds, over every slot.
func count_of(item: ItemDef) -> int:
	var total := 0
	for slot in slot_count:
		if _items[slot] == item:
			total += _counts[slot]
	return total


## How many of the item with `id` the bag holds.
func count_of_id(id: StringName) -> int:
	return count_of(find_in_catalog(id))


## The catalog's item with `id`, or null.
func find_in_catalog(id: StringName) -> ItemDef:
	for item in catalog:
		if item != null and item.id == id:
			return item
	return null


## The first slot holding `item`, or -1.
func find(item: ItemDef) -> int:
	return _items.find(item) if item != null else -1


## The first empty slot, or -1 when the bag is full.
func first_empty() -> int:
	return _items.find(null)


## How many more of `item` fit in the bag.
func room_for(item: ItemDef) -> int:
	if item == null:
		return 0
	var room := 0
	for slot in slot_count:
		if _items[slot] == null:
			room += item.max_stack
		elif _items[slot] == item:
			room += maxi(item.max_stack - _counts[slot], 0)
	return room


## Puts `count` of `item` in the bag: on its stacks first, then in the first empty slots. Returns
## how many did not fit (and says so with `overflowed`).
func add(item: ItemDef, count: int) -> int:
	if item == null or count <= 0:
		return maxi(count, 0)
	var left := count
	for slot in slot_count:
		if left == 0:
			break
		if _items[slot] == item and _counts[slot] < item.max_stack:
			var taken := mini(left, item.max_stack - _counts[slot])
			_counts[slot] += taken
			left -= taken
			slot_changed.emit(slot)
	for slot in slot_count:
		if left == 0:
			break
		if _items[slot] == null:
			var taken := mini(left, item.max_stack)
			_items[slot] = item
			_counts[slot] = taken
			left -= taken
			slot_changed.emit(slot)
	if left < count:
		item_added.emit(item, count - left)
		changed.emit()
	if left > 0:
		overflowed.emit(item, left)
	return left


## Takes up to `count` out of `slot` (all of it when `count` is negative). Returns how many left.
func remove(slot: int, count := -1) -> int:
	if is_empty(slot):
		return 0
	var taken := _counts[slot] if count < 0 else mini(count, _counts[slot])
	_counts[slot] -= taken
	if _counts[slot] <= 0:
		_items[slot] = null
		_counts[slot] = 0
	if taken > 0:
		slot_changed.emit(slot)
		changed.emit()
	return taken


## Moves the stack in `from` onto `to`: into an empty slot, onto a stack of the same kind (as many
## as fit; the rest stays in `from`) or in place of another kind (the two swap). True when
## anything moved.
func move(from: int, to: int) -> bool:
	if from == to or not _in_range(from) or not _in_range(to) or is_empty(from):
		return false
	var item := _items[from]
	if _items[to] == item:
		var moved := mini(_counts[from], item.max_stack - _counts[to])
		if moved <= 0:
			return false
		_counts[to] += moved
		_counts[from] -= moved
		if _counts[from] == 0:
			_items[from] = null
	else:
		var other := _items[to]
		var other_count := _counts[to]
		_items[to] = item
		_counts[to] = _counts[from]
		_items[from] = other
		_counts[from] = other_count
	slot_changed.emit(from)
	slot_changed.emit(to)
	changed.emit()
	return true


## Whether the stack in `slot` may be dropped.
func can_drop(slot: int) -> bool:
	return not is_empty(slot) and _items[slot].droppable


## Drops up to `count` from `slot` (the whole stack when negative): takes them out and places the
## item's `drop_scene` in front of `drop_origin`. Returns what was placed (null when the item has
## no drop scene, or nothing was dropped).
func drop(slot: int, count := -1) -> Node:
	if not can_drop(slot):
		return null
	var item := _items[slot]
	var taken := remove(slot, count)
	if taken <= 0:
		return null
	var placed := _place(item, taken)
	item_dropped.emit(item, taken, placed)
	return placed


## Empties every slot.
func clear() -> void:
	for slot in slot_count:
		_items[slot] = null
		_counts[slot] = 0
	changed.emit()


# Puts the item's drop scene in the world in front of the origin, carrying the item and count.
func _place(item: ItemDef, count: int) -> Node:
	if item.drop_scene == null:
		return null
	var node := item.drop_scene.instantiate()
	for pair: Array in [[&"item_id", item.id], [&"amount", count], [&"tint", item.tint]]:
		if pair[0] in node:
			node.set(pair[0], pair[1])
	var source := collector if collector != null else get_parent()
	var origin := drop_origin if drop_origin != null else source as Node3D
	var parent := drop_parent
	if parent == null:
		parent = source.get_parent() if source != null and source.get_parent() != null else self
	parent.add_child(node)
	var spatial := node as Node3D
	if spatial != null and origin != null:
		spatial.global_position = origin.global_transform * drop_offset
	return node


func _resize(before: int) -> void:
	var cut: Array[ItemDef] = []
	var cut_counts: Array[int] = []
	for slot in range(slot_count, before):
		if _items[slot] != null:
			cut.append(_items[slot])
			cut_counts.append(_counts[slot])
	_items.resize(slot_count)
	_counts.resize(slot_count)
	for index in cut.size():
		add(cut[index], cut_counts[index])
	changed.emit()


func _in_range(slot: int) -> bool:
	return slot >= 0 and slot < _items.size()


func _on_collected(item_id: StringName, amount := 1, _total := 0) -> void:
	var item := find_in_catalog(item_id)
	if item != null:
		add(item, amount)

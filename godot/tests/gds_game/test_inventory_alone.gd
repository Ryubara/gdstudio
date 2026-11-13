# `Inventory` of `gds_game` on its own: items are added onto their stacks and then into empty
# slots, a stack never passes its item's `max_stack`, what does not fit is given back, a move fills,
# merges or swaps, a drop takes the stack out and leaves the item's scene in front of the owner,
# an item that may not be dropped stays, and a collector's signal fills the bag from the catalog.
extends GdUnitTestSuite

const DROPPED := preload("res://tests/gds_game/fixtures/dropped_item.gd")


class Collector:
	extends Node3D
	signal item_collected(item_id: StringName, amount: int, total: int)


var _holder: Collector
var _bag: Inventory
var _coin: ItemDef
var _medkit: ItemDef
var _key: ItemDef


func before_test() -> void:
	_coin = _item(&"coin", 99)
	_medkit = _item(&"medkit", 5)
	_key = _item(&"key", 1)
	_key.droppable = false
	_holder = auto_free(Collector.new()) as Collector
	add_child(_holder)
	_bag = Inventory.new()
	_bag.slot_count = 6
	_bag.catalog = [_coin, _medkit, _key] as Array[ItemDef]
	_holder.add_child(_bag)


func _item(id: StringName, stack: int) -> ItemDef:
	var item := ItemDef.new()
	item.id = id
	item.display_name = String(id).capitalize()
	item.max_stack = stack
	return item


func _drop_scene() -> PackedScene:
	var node := Node3D.new()
	node.set_script(DROPPED)
	var scene := PackedScene.new()
	scene.pack(node)
	node.free()
	return scene


func test_every_export_has_its_default_pinned() -> void:
	var fresh := auto_free(Inventory.new()) as Inventory
	var pins := {
		&"slot_count": 16,
		&"start_items": [],
		&"catalog": [],
		&"collector": null,
		&"collect_signal": &"item_collected",
		&"drop_origin": null,
		&"drop_offset": Vector3(0.0, 0.6, 1.6),
		&"drop_parent": null,
	}
	assert_array(ExportPins.differences(fresh, pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, pins)).is_empty()
	var item := ItemDef.new()
	var item_pins := {
		&"id": &"",
		&"display_name": "Item",
		&"description": "",
		&"icon": null,
		&"tint": Color(0.8, 0.8, 0.8),
		&"max_stack": 1,
		&"droppable": true,
		&"drop_scene": null,
		&"use_effect": null,
		&"consumed_on_use": true,
		&"use_time": 0.0,
		&"use_apply_share": 0.75,
		&"use_clip": &"",
		&"use_sound": null,
	}
	assert_array(ExportPins.differences(item, item_pins)).is_empty()
	assert_array(ExportPins.wrong_values(item, item_pins)).is_empty()


func test_items_fill_their_stack_then_the_first_empty_slots() -> void:
	assert_int(_bag.add(_medkit, 3)).is_zero()
	assert_object(_bag.item_at(0)).is_same(_medkit)
	assert_int(_bag.count_at(0)).is_equal(3)
	assert_int(_bag.add(_medkit, 4)).is_zero()
	assert_int(_bag.count_at(0)).is_equal(5)
	assert_int(_bag.count_at(1)).is_equal(2)
	assert_int(_bag.count_of(_medkit)).is_equal(7)
	_bag.add(_key, 2)
	assert_object(_bag.item_at(2)).is_same(_key)
	assert_object(_bag.item_at(3)).is_same(_key)
	assert_int(_bag.count_at(3)).is_equal(1)
	assert_int(_bag.first_empty()).is_equal(4)


func test_what_does_not_fit_is_given_back_and_said() -> void:
	var over := []
	_bag.overflowed.connect(func(item: ItemDef, count: int) -> void: over.append([item, count]))
	assert_int(_bag.room_for(_key)).is_equal(6)
	assert_int(_bag.add(_key, 8)).is_equal(2)
	assert_int(_bag.first_empty()).is_equal(-1)
	assert_array(over).is_equal([[_key, 2]])
	assert_int(_bag.room_for(_coin)).is_zero()


func test_a_move_goes_into_an_empty_slot_merges_a_stack_or_swaps() -> void:
	_bag.add(_medkit, 4)
	_bag.add(_coin, 10)
	assert_bool(_bag.move(0, 4)).is_true()
	assert_bool(_bag.is_empty(0)).is_true()
	assert_int(_bag.count_at(4)).is_equal(4)
	# Onto another kind: the two swap.
	assert_bool(_bag.move(4, 1)).is_true()
	assert_object(_bag.item_at(1)).is_same(_medkit)
	assert_object(_bag.item_at(4)).is_same(_coin)
	assert_int(_bag.count_at(4)).is_equal(10)


func test_a_move_onto_the_same_kind_fills_that_stack_and_leaves_the_rest() -> void:
	_bag.add(_medkit, 5)
	_bag.add(_medkit, 2)
	_bag.remove(0, 1)
	# Slot 0 holds 4, slot 1 holds 2: one fits.
	assert_bool(_bag.move(1, 0)).is_true()
	assert_int(_bag.count_at(0)).is_equal(5)
	assert_int(_bag.count_at(1)).is_equal(1)
	# A full stack takes none.
	assert_bool(_bag.move(1, 0)).is_false()
	assert_int(_bag.count_at(1)).is_equal(1)
	# The whole stack fits: the slot it came from is empty.
	_bag.remove(0, 2)
	assert_bool(_bag.move(1, 0)).is_true()
	assert_int(_bag.count_at(0)).is_equal(4)
	assert_bool(_bag.is_empty(1)).is_true()


func test_a_move_from_an_empty_or_onto_itself_does_nothing() -> void:
	var changes := [0]
	_bag.changed.connect(func() -> void: changes[0] += 1)
	assert_bool(_bag.move(0, 1)).is_false()
	_bag.add(_coin, 1)
	changes[0] = 0
	assert_bool(_bag.move(0, 0)).is_false()
	assert_bool(_bag.move(0, 99)).is_false()
	assert_int(changes[0]).is_zero()


func test_remove_takes_out_part_or_all_of_a_stack() -> void:
	_bag.add(_coin, 30)
	assert_int(_bag.remove(0, 12)).is_equal(12)
	assert_int(_bag.count_at(0)).is_equal(18)
	assert_int(_bag.remove(0)).is_equal(18)
	assert_bool(_bag.is_empty(0)).is_true()
	assert_int(_bag.remove(0)).is_zero()


func test_a_drop_leaves_the_items_scene_in_front_of_the_owner_with_the_item_and_count() -> void:
	_medkit.drop_scene = _drop_scene()
	_medkit.tint = Color.RED
	_holder.position = Vector3(2.0, 0.0, 3.0)
	_holder.rotation.y = PI / 2.0
	_bag.add(_medkit, 3)
	var events := []
	_bag.item_dropped.connect(
		func(item: ItemDef, count: int, node: Node) -> void: events.append([item, count, node])
	)
	var placed := _bag.drop(0) as Node3D
	assert_object(placed).is_not_null()
	assert_bool(_bag.is_empty(0)).is_true()
	assert_object(placed.get_parent()).is_same(self)
	assert_str(String(placed.get(&"item_id"))).is_equal("medkit")
	assert_int(placed.get(&"amount")).is_equal(3)
	assert_that(placed.get(&"tint")).is_equal(Color.RED)
	# 1.6 m in front (+Z turned a quarter: +X) and 0.6 m up.
	assert_vector(placed.global_position).is_equal_approx(
		Vector3(3.6, 0.6, 3.0), Vector3.ONE * 0.001
	)
	assert_array(events).is_equal([[_medkit, 3, placed]])
	placed.free()


func test_part_of_a_stack_can_be_dropped_and_an_item_with_no_scene_is_just_gone() -> void:
	_bag.add(_medkit, 4)
	assert_object(_bag.drop(0, 1)).is_null()
	assert_int(_bag.count_at(0)).is_equal(3)


func test_an_item_that_may_not_be_dropped_stays() -> void:
	_bag.add(_key, 1)
	assert_bool(_bag.can_drop(0)).is_false()
	assert_object(_bag.drop(0)).is_null()
	assert_object(_bag.item_at(0)).is_same(_key)
	assert_bool(_bag.can_drop(3)).is_false()


func test_the_collectors_signal_adds_catalog_items_and_leaves_the_rest() -> void:
	_holder.item_collected.emit(&"coin", 3, 3)
	_holder.item_collected.emit(&"ammo_9mm", 12, 12)
	_holder.item_collected.emit(&"coin", 2, 5)
	assert_int(_bag.count_of_id(&"coin")).is_equal(5)
	assert_int(_bag.count_of_id(&"ammo_9mm")).is_zero()
	assert_int(_bag.first_empty()).is_equal(1)


func test_start_items_are_added_at_ready() -> void:
	var bag := Inventory.new()
	bag.slot_count = 4
	var stack := ItemStack.new()
	stack.item = _medkit
	stack.count = 7
	bag.start_items = [stack] as Array[ItemStack]
	_holder.add_child(bag)
	assert_int(bag.count_at(0)).is_equal(5)
	assert_int(bag.count_at(1)).is_equal(2)
	bag.free()


func test_fewer_slots_move_what_was_cut_into_free_slots() -> void:
	_bag.add(_key, 1)
	_bag.move(0, 5)
	_bag.slot_count = 3
	assert_int(_bag.count_of(_key)).is_equal(1)
	assert_object(_bag.item_at(0)).is_same(_key)
	_bag.slot_count = 8
	assert_bool(_bag.is_empty(7)).is_true()


func test_clear_empties_the_bag() -> void:
	_bag.add(_coin, 5)
	_bag.clear()
	assert_int(_bag.count_of(_coin)).is_zero()

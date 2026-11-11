# `Hotbar` of `gds_game` on its own, beside an `Inventory` and a `Health`: a place names a kind of
# item and counts it from the bag, an item sits in one place, using a place heals and takes one
# out of the bag, a bandage at full health, an item that ran out, an empty place and a peer that is
# not authoritative are refused, and the hotbar says `changed` when the bag's counts change.
extends GdUnitTestSuite

var _holder: Node
var _bag: Inventory
var _bar: Hotbar
var _health: Health
var _bandage: ItemDef
var _coin: ItemDef


func before_test() -> void:
	_bandage = ItemDef.new()
	_bandage.id = &"bandage"
	_bandage.max_stack = 5
	var heal := HealEffect.new()
	heal.amount = 25.0
	_bandage.use_effect = heal
	_coin = ItemDef.new()
	_coin.id = &"coin"
	_coin.max_stack = 99
	_holder = auto_free(Node.new()) as Node
	_health = Health.new()
	_holder.add_child(_health)
	_bag = Inventory.new()
	_bag.slot_count = 4
	_holder.add_child(_bag)
	_bar = Hotbar.new()
	_bar.start_items = [_bandage] as Array[ItemDef]
	_holder.add_child(_bar)
	add_child(_holder)
	_bag.add(_bandage, 3)


func test_every_export_has_its_default_pinned() -> void:
	var fresh := auto_free(Hotbar.new()) as Hotbar
	var pins := {
		&"place_count": 4,
		&"start_items": [],
		&"inventory": null,
		&"user": null,
		&"authoritative": true,
	}
	assert_array(ExportPins.differences(fresh, pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, pins)).is_empty()
	var effect := HealEffect.new()
	var effect_pins := {&"amount": 25.0, &"only_when_hurt": true}
	assert_array(ExportPins.differences(effect, effect_pins)).is_empty()
	assert_array(ExportPins.wrong_values(effect, effect_pins)).is_empty()
	assert_bool(ItemDef.new().is_usable()).is_false()


func test_it_finds_the_bag_beside_it_and_its_user_and_counts_from_the_bag() -> void:
	assert_object(_bar.inventory).is_same(_bag)
	assert_object(_bar.user).is_same(_holder)
	assert_object(Hotbar.of(_holder)).is_same(_bar)
	assert_object(_bar.item_at(0)).is_same(_bandage)
	assert_int(_bar.count_at(0)).is_equal(3)
	assert_object(_bar.item_at(1)).is_null()
	assert_int(_bar.count_at(1)).is_equal(0)
	assert_object(_bar.item_at(9)).is_null()


func test_an_item_sits_in_one_place_and_a_place_can_be_cleared() -> void:
	var seen := [0]
	_bar.changed.connect(func() -> void: seen[0] += 1)
	assert_bool(_bar.assign(2, _bandage)).is_true()
	assert_object(_bar.item_at(0)).is_null()
	assert_object(_bar.item_at(2)).is_same(_bandage)
	assert_int(_bar.place_of(_bandage)).is_equal(2)
	assert_bool(_bar.assign(2, _bandage)).is_false()
	assert_bool(_bar.assign(1, _coin)).is_true()
	assert_bool(_bar.clear(1)).is_true()
	assert_bool(_bar.clear(1)).is_false()
	assert_bool(_bar.assign(7, _coin)).is_false()
	assert_int(seen[0]).is_equal(3)


func test_using_a_place_heals_and_takes_one_out_of_the_bag() -> void:
	_health.value = 40.0
	var used := []
	_bar.used.connect(func(place: int, item: ItemDef) -> void: used.append([place, item]))
	assert_bool(_bar.can_use(0)).is_true()
	assert_bool(_bar.use(0)).is_true()
	assert_float(_health.value).is_equal(65.0)
	assert_int(_bag.count_of(_bandage)).is_equal(2)
	assert_int(_bar.count_at(0)).is_equal(2)
	assert_array(used).is_equal([[0, _bandage]])


func test_a_use_takes_from_the_last_stack_and_leaves_the_first_full() -> void:
	_bag.add(_bandage, 4)
	assert_int(_bag.count_at(0)).is_equal(5)
	assert_int(_bag.count_at(1)).is_equal(2)
	_health.value = 10.0
	_bar.use(0)
	assert_int(_bag.count_at(0)).is_equal(5)
	assert_int(_bag.count_at(1)).is_equal(1)


func test_a_use_is_refused_at_full_health_for_an_empty_place_and_once_it_runs_out() -> void:
	var refused := []
	_bar.use_refused.connect(func(place: int, _item: ItemDef) -> void: refused.append(place))
	assert_bool(_bar.use(0)).is_false()
	assert_int(_bag.count_of(_bandage)).is_equal(3)
	assert_bool(_bar.use(1)).is_false()
	_bar.assign(1, _coin)
	_bag.add(_coin, 1)
	assert_bool(_bar.use(1)).is_false()
	_health.value = 1.0
	for _use in 3:
		assert_bool(_bar.use(0)).is_true()
	assert_int(_bar.count_at(0)).is_equal(0)
	# The place keeps its item, dim with 0, and refuses.
	assert_object(_bar.item_at(0)).is_same(_bandage)
	assert_bool(_bar.use(0)).is_false()
	assert_array(refused).is_equal([0, 1, 1, 0])


func test_a_peer_that_is_not_authoritative_never_uses() -> void:
	_health.value = 10.0
	_bar.authoritative = false
	assert_bool(_bar.can_use(0)).is_false()
	assert_bool(_bar.use(0)).is_false()
	assert_float(_health.value).is_equal(10.0)
	assert_int(_bag.count_of(_bandage)).is_equal(3)


func test_a_heal_with_only_when_hurt_off_is_used_up_at_full_health() -> void:
	(_bandage.use_effect as HealEffect).only_when_hurt = false
	assert_bool(_bar.use(0)).is_true()
	assert_float(_health.value).is_equal(100.0)
	assert_int(_bag.count_of(_bandage)).is_equal(2)


func test_a_dead_user_is_refused() -> void:
	_health.kill()
	assert_bool(_bar.use(0)).is_false()
	assert_int(_bag.count_of(_bandage)).is_equal(3)


func test_it_says_changed_when_the_bag_changes_and_a_smaller_count_keeps_the_first_places() -> void:
	var seen := [0]
	_bar.changed.connect(func() -> void: seen[0] += 1)
	_bag.add(_bandage, 1)
	assert_int(seen[0]).is_equal(1)
	assert_int(_bar.count_at(0)).is_equal(4)
	_bar.place_count = 1
	assert_object(_bar.item_at(0)).is_same(_bandage)
	assert_int(seen[0]).is_equal(2)
	_bar.place_count = 3
	assert_object(_bar.item_at(2)).is_null()

# What the pickup and the trigger zone sense when they stand among the level's own bodies. An area
# reports every body on its mask's layers, static ones too (issue #848: the sample map's pressure
# pad was pressed from the first tick by the floor and the landing it stands on), so each body here
# sits on its layer (`PhysicsLayers`) and the areas mask only what they sense (#924): the floor and
# the walls never reach their scripts. The class test (`characters_only`, `counts`) stays behind
# the mask for a game whose layers differ. These tests put real bodies against real areas and step
# the physics.
extends GdUnitTestSuite

const PICKUP := "res://gameplay/pickup/pickup.tscn"
const ZONE := "res://gameplay/trigger_zone/trigger_zone.tscn"
const AT := Vector3(0.0, 1.0, 0.0)

var _taken: Array[Node3D] = []
var _entered: Array[Node3D] = []


# A body with a box shape at `at`, on the layer of what it is, positioned before it enters the
# tree (one made at the origin and moved afterwards is sensed at the origin for a step).
func _body(kind: Node3D, at: Vector3) -> Node3D:
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	kind.add_child(shape)
	var layer := PhysicsLayers.WORLD
	if kind is CharacterBody3D:
		layer = PhysicsLayers.CHARACTERS
	elif kind is RigidBody3D:
		layer = PhysicsLayers.PROPS
	(kind as CollisionObject3D).collision_layer = layer
	kind.position = at
	add_child(auto_free(kind))
	return kind


func _prop(at: Vector3) -> RigidBody3D:
	var crate := _body(RigidBody3D.new(), at) as RigidBody3D
	crate.gravity_scale = 0.0
	return crate


func _pickup() -> Pickup:
	var coin := load(PICKUP).instantiate() as Pickup
	coin.position = AT
	add_child(auto_free(coin))
	_taken.clear()
	_entered.clear()
	coin.collected.connect(func(who: Node3D, _id: StringName, _n: int) -> void: _taken.append(who))
	coin.body_entered.connect(func(body: Node3D) -> void: _entered.append(body))
	return coin


func _zone() -> TriggerZone:
	var zone := load(ZONE).instantiate() as TriggerZone
	zone.position = AT
	add_child(auto_free(zone))
	return zone


# The floor under the area, a block against it and a platform against it.
func _surround() -> void:
	_body(StaticBody3D.new(), AT + Vector3(0.0, -0.8, 0.0))
	_body(StaticBody3D.new(), AT + Vector3(0.6, 0.0, 0.0))
	_body(AnimatableBody3D.new(), AT + Vector3(-0.6, 0.0, 0.0))


func test_a_pickup_among_blocks_and_a_platform_is_not_taken_by_them() -> void:
	_surround()
	var coin := _pickup()
	await InputSim.ticks(get_tree(), 20)
	assert_array(coin.get_overlapping_bodies()).is_empty()
	assert_array(_taken).is_empty()
	assert_bool(coin.is_available()).is_true()


func test_a_pickup_against_a_wall_gets_no_callback_for_the_wall() -> void:
	# The wall touches the coin from the first tick; with the mask on characters the area never
	# reports it, so the script is not even asked (#924).
	_body(StaticBody3D.new(), AT + Vector3(0.5, 0.0, 0.0))
	_body(StaticBody3D.new(), AT + Vector3(0.0, -0.8, 0.0))
	var coin := _pickup()
	await InputSim.ticks(get_tree(), 20)
	assert_array(_entered).is_empty()
	var walker := _body(CharacterBody3D.new(), AT + Vector3(0.0, 0.0, 0.3))
	await InputSim.ticks(get_tree(), 10)
	assert_array(_entered).is_equal([walker])
	assert_array(_taken).is_equal([walker])
	assert_bool(coin.is_available()).is_false()


func test_a_pickup_is_not_taken_by_a_prop_but_by_a_character() -> void:
	var coin := _pickup()
	# A game whose mask also reaches props: the class test still keeps the crate from taking it.
	coin.collision_mask = PhysicsLayers.CHARACTERS | PhysicsLayers.PROPS
	var crate := _prop(AT)
	await InputSim.ticks(get_tree(), 10)
	assert_array(coin.get_overlapping_bodies()).contains([crate])
	assert_array(_taken).is_empty()
	var walker := _body(CharacterBody3D.new(), AT + Vector3(0.0, 0.0, 0.3))
	await InputSim.ticks(get_tree(), 10)
	assert_array(_taken).is_equal([walker])


func test_characters_only_off_lets_a_block_take_the_pickup() -> void:
	var coin := _pickup()
	coin.characters_only = false
	coin.collision_mask = PhysicsLayers.CHARACTERS | PhysicsLayers.WORLD
	var block := _body(StaticBody3D.new(), AT)
	await InputSim.ticks(get_tree(), 10)
	assert_array(_taken).is_equal([block])


func test_a_zone_among_blocks_stays_quiet_and_a_character_or_a_prop_presses_it() -> void:
	_surround()
	var zone := _zone()
	var events := []
	zone.activated.connect(func(_who: Node3D) -> void: events.append("on"))
	zone.deactivated.connect(func() -> void: events.append("off"))
	await InputSim.ticks(get_tree(), 20)
	assert_array(zone.get_overlapping_bodies()).is_empty()
	assert_bool(zone.is_active()).is_false()
	assert_array(events).is_empty()
	var crate := _prop(AT + Vector3(0.0, 0.0, 0.3))
	await InputSim.ticks(get_tree(), 10)
	assert_bool(zone.is_active()).is_true()
	assert_int(zone.occupant_count()).is_equal(1)
	crate.free()
	await InputSim.ticks(get_tree(), 10)
	assert_bool(zone.is_active()).is_false()
	var walker := _body(CharacterBody3D.new(), AT + Vector3(0.0, 0.0, 0.3))
	await InputSim.ticks(get_tree(), 10)
	assert_bool(zone.is_active()).is_true()
	assert_array(events).is_equal(["on", "off", "on"])
	walker.free()


func test_a_characters_only_zone_ignores_a_prop_and_any_counts_the_floor() -> void:
	_surround()
	var zone := _zone()
	zone.counts = TriggerZone.Counts.CHARACTERS
	_prop(AT + Vector3(0.0, 0.0, 0.3))
	await InputSim.ticks(get_tree(), 10)
	assert_bool(zone.is_active()).is_false()
	var other := _zone()
	other.counts = TriggerZone.Counts.ANY
	other.collision_mask |= PhysicsLayers.WORLD
	await InputSim.ticks(get_tree(), 10)
	assert_bool(other.is_active()).is_true()
	assert_int(other.occupant_count()).is_greater_equal(3)

# `TriggerZone` of `gds_game` on its own: what counts, the first in and the last out, `fire_once`
# and the group. The bodies are handed to the zone's callbacks, so no physics step is waited on; a
# game's suites test the zone's scene in a level (3D Third Person's `test_trigger_zone.gd`).
extends GdUnitTestSuite

var _zone: TriggerZone
var _on := 0
var _off := 0


func before_test() -> void:
	_on = 0
	_off = 0
	_zone = auto_free(TriggerZone.new())
	add_child(_zone)
	_zone.activated.connect(func(_who: Node3D) -> void: _on += 1)
	_zone.deactivated.connect(func() -> void: _off += 1)


func _body(node: Node3D = null) -> Node3D:
	var made: Node3D = auto_free(node if node != null else CharacterBody3D.new())
	return made


func test_the_first_body_in_and_the_last_out_signal_once_each() -> void:
	var one := _body()
	var two := _body()
	_zone._on_body_entered(one)
	_zone._on_body_entered(two)
	assert_int(_on).is_equal(1)
	assert_bool(_zone.is_active()).is_true()
	_zone._on_body_exited(one)
	assert_int(_off).is_equal(0)
	_zone._on_body_exited(two)
	assert_int(_off).is_equal(1)
	assert_bool(_zone.is_active()).is_false()


func test_the_floor_never_counts_unless_any() -> void:
	var ground: Node3D = _body(StaticBody3D.new())
	_zone._on_body_entered(ground)
	assert_int(_on).is_equal(0)
	_zone.counts = TriggerZone.Counts.ANY
	_zone._on_body_entered(ground)
	assert_int(_on).is_equal(1)


func test_a_prop_counts_only_with_props() -> void:
	var crate: Node3D = _body(RigidBody3D.new())
	_zone.counts = TriggerZone.Counts.CHARACTERS
	_zone._on_body_entered(crate)
	assert_int(_on).is_equal(0)
	_zone.counts = TriggerZone.Counts.CHARACTERS_AND_PROPS
	_zone._on_body_entered(crate)
	assert_int(_on).is_equal(1)


func test_the_group_is_a_second_condition() -> void:
	_zone.required_group = &"heroes"
	var stranger := _body()
	_zone._on_body_entered(stranger)
	assert_int(_on).is_equal(0)
	var hero := _body()
	hero.add_to_group(&"heroes")
	_zone._on_body_entered(hero)
	assert_int(_on).is_equal(1)


func test_fire_once_ignores_everything_after_the_first() -> void:
	_zone.fire_once = true
	var body := _body()
	_zone._on_body_entered(body)
	_zone._on_body_exited(body)
	_zone._on_body_entered(body)
	assert_int(_on).is_equal(1)

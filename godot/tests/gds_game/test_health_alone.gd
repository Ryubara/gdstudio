# `Health` and `HitRecord` of `gds_game` on their own: a hit takes the damage and says so, death
# is said once, invulnerable and switched off take nothing, regeneration waits its delay and does
# no work each frame while off, the flinch threshold, the value on the wire, and the pins. The
# carriers are built in code; 3D Third Person's suites shoot a character and a target through it
# (`test_hit_components.gd`).
extends GdUnitTestSuite

var _health: Health
var _said: Array[String] = []


func before_test() -> void:
	_said.clear()
	var carrier: Node3D = auto_free(Node3D.new())
	add_child(carrier)
	_health = Health.new()
	carrier.add_child(_health)
	_health.damaged.connect(
		func(amount: float, _h: HitRecord) -> void: _said.append("damaged %d" % amount)
	)
	_health.died.connect(func(_h: HitRecord) -> void: _said.append("died"))
	_health.flinched.connect(func(_h: HitRecord) -> void: _said.append("flinched"))
	_health.revived.connect(func() -> void: _said.append("revived"))
	_health.hit_taken.connect(func(_h: HitRecord) -> void: _said.append("hit"))


func _hit(amount: float) -> HitRecord:
	return HitRecord.shot(amount, &"chest", &"spine_03", Vector3.ZERO, Vector3.FORWARD, 10.0)


func test_a_hit_takes_its_damage_and_says_so_in_order() -> void:
	var changes: Array[float] = []
	_health.changed.connect(func(value: float, _max: float) -> void: changes.append(value))
	assert_float(_health.apply(_hit(30.0))).is_equal(30.0)
	assert_float(_health.value).is_equal(70.0)
	assert_float(_health.fraction()).is_equal_approx(0.7, 0.0001)
	assert_array(changes).is_equal([70.0])
	assert_array(_said).is_equal(["damaged 30", "flinched", "hit"])


func test_death_is_said_once_and_marks_the_hit_that_killed() -> void:
	_health.apply(_hit(60.0))
	var killing := _hit(60.0)
	assert_float(_health.apply(killing)).is_equal(40.0)
	assert_bool(killing.killed).is_true()
	assert_bool(_health.is_dead()).is_true()
	var after := _hit(60.0)
	assert_float(_health.apply(after)).is_equal(0.0)
	_health.kill()
	_health.value = 0.0
	assert_bool(after.killed).is_false()
	assert_int(_said.count("died")).is_equal(1)
	# A hit on the dead is still said (a lying body is pushed), and nothing else.
	assert_str(_said.back()).is_equal("hit")
	_health.reset()
	assert_float(_health.value).is_equal(100.0)
	assert_str(_said.back()).is_equal("revived")
	_health.kill()
	assert_int(_said.count("died")).is_equal(2)


func test_invulnerable_and_switched_off_take_nothing_but_the_hit_is_still_said() -> void:
	_health.invulnerable = true
	assert_float(_health.apply(_hit(500.0))).is_equal(0.0)
	_health.invulnerable = false
	_health.enabled = false
	assert_float(_health.apply(_hit(500.0))).is_equal(0.0)
	assert_float(_health.value).is_equal(100.0)
	assert_int(_said.count("hit")).is_equal(2)
	assert_int(_said.count("flinched")).is_equal(2)
	assert_int(_said.count("died")).is_equal(0)


func test_the_flinch_threshold_sets_which_hits_flinch_and_a_killing_hit_never_does() -> void:
	_health.flinch_threshold = 25.0
	_health.apply(_hit(10.0))
	assert_int(_said.count("flinched")).is_equal(0)
	_health.apply(_hit(25.0))
	assert_int(_said.count("flinched")).is_equal(1)
	_health.apply(_hit(200.0))
	assert_int(_said.count("flinched")).is_equal(1)


func test_regeneration_waits_its_delay_then_fills_at_its_rate() -> void:
	_health.regeneration_per_second = 30.0
	_health.regeneration_delay = 0.5
	assert_bool(_health.is_physics_processing()).is_false()
	_health.apply(_hit(60.0))
	assert_bool(_health.is_physics_processing()).is_true()
	for tick in 15:
		_health._physics_process(1.0 / 60.0)
	assert_float(_health.value).is_equal(40.0)
	for tick in 60:
		_health._physics_process(1.0 / 60.0)
	# 1.25 s after the hit: 0.75 s of regeneration at 30 a second.
	assert_float(_health.value).is_equal_approx(62.5, 0.6)
	for tick in 240:
		_health._physics_process(1.0 / 60.0)
	assert_float(_health.value).is_equal(100.0)
	assert_bool(_health.is_physics_processing()).is_false()


func test_no_per_frame_work_while_regeneration_is_off_or_the_carrier_is_dead() -> void:
	_health.apply(_hit(50.0))
	assert_bool(_health.is_physics_processing()).is_false()
	_health.regeneration_per_second = 5.0
	assert_bool(_health.is_physics_processing()).is_true()
	_health.kill()
	assert_bool(_health.is_physics_processing()).is_false()
	_health.reset()
	assert_bool(_health.is_physics_processing()).is_false()


func test_regeneration_runs_in_the_physics_step() -> void:
	_health.regeneration_per_second = 60.0
	_health.apply(_hit(10.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_float(_health.value).is_greater(90.0)


func test_the_value_on_the_wire_is_one_integer_rounded_up() -> void:
	_health.apply(_hit(20.4))
	assert_int(_health.wire_value()).is_equal(80)
	var peer := Health.new()
	add_child(peer)
	peer.set_wire_value(_health.wire_value())
	assert_float(peer.value).is_equal(80.0)
	peer.set_wire_value(0)
	assert_bool(peer.is_dead()).is_true()
	peer.set_wire_value(55)
	assert_bool(peer.is_dead()).is_false()
	peer.free()


func test_a_lower_maximum_lowers_the_value_and_heal_stops_at_the_maximum() -> void:
	_health.max_value = 40.0
	assert_float(_health.value).is_equal(40.0)
	_health.apply(_hit(30.0))
	assert_float(_health.heal(100.0)).is_equal(30.0)
	assert_float(_health.value).is_equal(40.0)


func test_of_finds_the_component_on_a_body_or_none() -> void:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	assert_object(Health.of(body)).is_null()
	assert_object(Health.of(null)).is_null()
	var part := Health.new()
	body.add_child(part)
	assert_object(Health.of(body)).is_same(part)
	assert_object(Health.of(part)).is_same(part)


func test_the_record_survives_the_wire() -> void:
	var record := _hit(42.0)
	var back := HitRecord.decode(record.encode())
	assert_float(back.damage).is_equal(42.0)
	assert_str(String(back.zone)).is_equal("chest")
	assert_object(HitRecord.decode(PackedByteArray([1, 2]))).is_null()


func test_the_exports_keep_their_defaults() -> void:
	var pins := {
		&"enabled": true,
		&"max_value": 100.0,
		&"invulnerable": false,
		&"regeneration_per_second": 0.0,
		&"regeneration_delay": 0.0,
		&"flinch_threshold": 0.0,
	}
	var fresh: Health = auto_free(Health.new())
	assert_array(ExportPins.differences(fresh, pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, pins)).is_empty()

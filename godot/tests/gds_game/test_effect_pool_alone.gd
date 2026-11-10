# The effect pool of `gds_game` on its own, in the kit's project: no template scene, no sound bus,
# nodes made in code. A game's suites test its own scenes on top (3D Third Person's
# `test_effect_pool.gd`).
extends GdUnitTestSuite

var _world: Node3D
var _emitter: EffectEmitter


func before_test() -> void:
	_world = auto_free(Node3D.new())
	add_child(_world)
	_emitter = EffectEmitter.new()
	_emitter.compact = false
	_emitter.warm_up_on_start = false
	_world.add_child(_emitter)


func _def(length := 0.5, instances := 4) -> EffectDef:
	var def := EffectDef.new()
	def.duration = length
	def.max_instances = instances
	return def


func test_the_level_finds_its_emitter_by_its_group() -> void:
	assert_object(EffectEmitter.find(_world)).is_same(_emitter)
	assert_object(EffectEmitter.find(null)).is_null()


func test_the_pool_never_grows_past_its_cap_and_reuses_its_slots() -> void:
	_emitter.max_effects = 3
	var def := _def()
	for step in 12:
		_emitter.play_at(def, Vector3(float(step), 0.0, 0.0))
	assert_int(_emitter.slot_count()).is_equal(3)
	_emitter.advance(1.0)
	assert_int(_emitter.active_count()).is_equal(0)
	_emitter.play_at(def, Vector3.ZERO)
	assert_int(_emitter.slot_count()).is_equal(3)


func test_an_effect_keeps_to_its_own_limit() -> void:
	_emitter.max_effects = 8
	var def := _def(0.5, 2)
	for step in 5:
		_emitter.play_at(def, Vector3.ZERO)
	assert_int(_emitter.slot_count()).is_equal(2)


func test_a_full_pool_cuts_the_oldest_effect() -> void:
	_emitter.max_effects = 2
	var first := _emitter.play_at(_def(), Vector3.ZERO)
	_emitter.advance(0.1)
	_emitter.play_at(_def(), Vector3.ZERO)
	_emitter.advance(0.1)
	assert_object(_emitter.play_at(_def(), Vector3.ONE)).is_same(first)


func test_the_web_cap_applies_when_compact() -> void:
	_emitter.compact = true
	_emitter.web_max_effects = 1
	_emitter.play_at(_def(), Vector3.ZERO)
	_emitter.play_at(_def(), Vector3.ONE)
	assert_int(_emitter.slot_count()).is_equal(1)


func test_an_emitter_switched_off_plays_nothing() -> void:
	_emitter.enabled = false
	assert_object(_emitter.play_at(_def(), Vector3.ZERO)).is_null()
	assert_int(_emitter.slot_count()).is_equal(0)


func test_an_effect_on_a_node_follows_it() -> void:
	var marker: Marker3D = auto_free(Marker3D.new())
	_world.add_child(marker)
	var slot := _emitter.play_on(_def(), marker)
	assert_object(slot.target).is_same(marker)
	assert_bool(slot.active).is_true()

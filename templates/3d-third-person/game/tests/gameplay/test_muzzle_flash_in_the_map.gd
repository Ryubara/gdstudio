# The muzzle flash in the game itself: the main scene holds an emitter, and the character's pistol
# flashes on the `Muzzle` of its model each time it fires, and a bullet impact is played by the same
# emitter.
extends GdUnitTestSuite

var _main: Node
var _emitter: EffectEmitter
var _player: Player


func before_test() -> void:
	_main = auto_free(load("res://main.tscn").instantiate())
	add_child(_main)
	_emitter = _main.get_node("World/Effects") as EffectEmitter
	_player = _main.get_node("PlayerRig/Player") as Player
	await _emitter.warmed
	await get_tree().physics_frame


func after_test() -> void:
	AudioDrain.stop_all(_main)


func _slot_of(effect: EffectDef) -> EffectSlot:
	for slot in _emitter.slots():
		if slot.effect == effect:
			return slot
	return null


func test_the_main_scene_holds_the_emitter_and_the_pistol_flashes_on_its_muzzle() -> void:
	assert_object(_emitter).is_not_null()
	assert_object(EffectEmitter.find(_player)).is_same(_emitter)
	var weapon := _player.weapon
	assert_object(weapon.muzzle_flash).is_not_null()
	assert_object(weapon.fire()).is_not_null()
	assert_int(_emitter.active_count()).is_equal(1)
	var slot := _slot_of(weapon.muzzle_flash)
	assert_vector(slot.global_position).is_equal_approx(
		weapon.muzzle.global_position, Vector3.ONE * 1e-3
	)
	assert_vector(slot.global_basis.y).is_equal_approx(
		-weapon.muzzle.global_basis.z.normalized(), Vector3.ONE * 1e-2
	)


func test_a_bullet_impact_and_the_flash_share_the_one_emitter() -> void:
	var weapon := _player.weapon
	var shot := weapon.fire()
	var floor_point := Vector3(0.0, 0.0, 0.0)
	var impacts := _main.get_node("World/Impacts") as Impacts
	var floor_body := _main.get_node("World/Level/Boundary/WallNorth/Body") as StaticBody3D
	impacts.impact(floor_body, floor_point, Vector3.UP)
	shot.queue_free()
	assert_int(_emitter.active_count()).is_equal(2)
	assert_object(_slot_of(weapon.muzzle_flash)).is_not_null()
	assert_bool(_slot_of(impacts.default_surface.effect).active).is_true()
	_emitter.advance(2.0)
	for slot in _emitter.slots():
		if slot.sound_player() != null:
			slot.sound_player().stop()
	_emitter.advance(0.01)
	assert_int(_emitter.active_count()).is_equal(0)

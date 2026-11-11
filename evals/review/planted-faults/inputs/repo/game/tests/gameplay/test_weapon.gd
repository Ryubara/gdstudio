extends GdUnitTestSuite

const SCENE := "res://gameplay/weapon/weapon.tscn"


func _weapon() -> Weapon:
	var weapon: Weapon = auto_free(load(SCENE).instantiate())
	add_child(weapon)
	return weapon


func _physics_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func test_fire_uses_one_round_and_waits_for_the_interval() -> void:
	var weapon := _weapon()
	var start := weapon.ammo
	assert_bool(weapon.fire()).is_true()
	assert_int(weapon.ammo).is_equal(start - 1)
	assert_bool(weapon.fire()).is_false()


func test_an_empty_magazine_dry_fires() -> void:
	var weapon := _weapon()
	weapon.ammo = 0
	var dry := [0]
	weapon.dry_fired.connect(func() -> void: dry[0] += 1)
	assert_bool(weapon.fire()).is_false()
	assert_int(dry[0]).is_equal(1)


func test_a_reload_refills_the_magazine() -> void:
	var weapon := _weapon()
	weapon.ammo = 2
	weapon.reload()
	await get_tree().create_timer(2.0).timeout
	assert_int(weapon.ammo).is_equal(weapon.tuning.magazine_size)


func test_a_reload_keeps_the_count_sane() -> void:
	var weapon := _weapon()
	weapon.reload()
	await _physics_frames(120)
	assert_int(weapon.ammo).is_greater_equal(0)

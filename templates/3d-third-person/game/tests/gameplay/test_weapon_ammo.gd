# A `Weapon` and its `WeaponDef` on their own: a shot spends a round, a reload puts the reserve's
# rounds in at its end, an empty magazine clicks (or reloads by itself), a second definition fires
# with its own numbers, a hitscan shot and a blow hit with no body and no camera, and a hundred
# shots make no new mesh, shape or material. Ticked by hand, so every number is a count of ticks.
extends GdUnitTestSuite

const WEAPON := "res://gameplay/weapon/weapon.tscn"
const TARGET := "res://gameplay/target/target.tscn"
const FISTS := "res://gameplay/weapon/fists.tres"
const TICK := 1.0 / 60.0

var _world: Node3D
var _weapon: Weapon
var _muzzle: Marker3D


func before_test() -> void:
	_world = auto_free(Node3D.new())
	add_child(_world)
	_weapon = load(WEAPON).instantiate() as Weapon
	_weapon.self_ticking = false
	_world.add_child(_weapon)
	_muzzle = Marker3D.new()
	_muzzle.position = Vector3(0.0, 1.0, 0.0)
	_world.add_child(_muzzle)
	_weapon.muzzle = _muzzle
	_weapon.definition = _weapon.definition.duplicate()
	await get_tree().physics_frame


func after_test() -> void:
	AudioDrain.stop_all(_world)


func _ticks(count: int) -> void:
	for _tick in count:
		_weapon.tick(TICK)


# Pulls the trigger once, after the cooldown of the shot before.
func _pull() -> Weapon.Pull:
	_ticks(ceili(_weapon.definition.shot_interval() / TICK) + 1)
	return _weapon.pull()


func _wall(at: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 4.0, 0.2)
	shape.shape = box
	wall.add_child(shape)
	wall.position = at
	_world.add_child(wall)
	return wall


func test_a_shot_spends_a_round_and_says_so() -> void:
	var told: Array[int] = []
	_weapon.ammo_changed.connect(func(ammo: int) -> void: told.append(ammo))
	assert_int(_weapon.ammo).is_equal(12)
	assert_int(_weapon.magazine_size).is_equal(12)
	assert_int(_weapon.reserve).is_equal(36)
	assert_int(_weapon.pull()).is_equal(Weapon.Pull.FIRED)
	assert_int(_weapon.ammo).is_equal(11)
	assert_int(_weapon.reserve).is_equal(36)
	assert_array(told).contains([11])


func test_a_reload_puts_the_reserves_rounds_in_at_its_end_and_not_before() -> void:
	for _shot in 5:
		_pull()
	assert_int(_weapon.ammo).is_equal(7)
	var started: Array[float] = []
	_weapon.reload_started.connect(func(seconds: float) -> void: started.append(seconds))
	var done := [0]
	_weapon.reloaded.connect(func() -> void: done[0] += 1)
	assert_bool(_weapon.reload()).is_true()
	assert_array(started).is_equal([1.6])
	assert_bool(_weapon.is_reloading()).is_true()
	# No shot while it reloads, and nothing goes in early.
	assert_int(_weapon.pull()).is_equal(Weapon.Pull.BUSY)
	_ticks(roundi(1.6 / TICK) - 2)
	assert_int(_weapon.ammo).is_equal(7)
	assert_int(done[0]).is_equal(0)
	_ticks(3)
	assert_int(done[0]).is_equal(1)
	assert_int(_weapon.ammo).is_equal(12)
	assert_int(_weapon.reserve).is_equal(31)
	# A full magazine does not reload.
	assert_bool(_weapon.reload()).is_false()


func test_a_reload_takes_only_what_the_reserve_has() -> void:
	_weapon.set_ammo(2, 4)
	assert_bool(_weapon.reload()).is_true()
	_ticks(roundi(1.6 / TICK) + 1)
	assert_int(_weapon.ammo).is_equal(6)
	assert_int(_weapon.reserve).is_equal(0)
	_pull()
	assert_bool(_weapon.reload()).is_false()


func test_an_empty_magazine_clicks_and_fires_nothing() -> void:
	_weapon.definition.auto_reload = false
	_weapon.set_ammo(1, 36)
	assert_int(_pull()).is_equal(Weapon.Pull.FIRED)
	var clicks := [0]
	_weapon.dry_fired.connect(func() -> void: clicks[0] += 1)
	var shots := [0]
	_weapon.fired.connect(func(_shot: Projectile) -> void: shots[0] += 1)
	assert_int(_pull()).is_equal(Weapon.Pull.EMPTY)
	assert_int(clicks[0]).is_equal(1)
	assert_int(shots[0]).is_equal(0)
	assert_bool((_weapon.get_node("%EmptySound") as AudioStreamPlayer3D).playing).is_true()
	# The clicks are spaced like shots: a second pull at once does nothing.
	assert_int(_weapon.pull()).is_equal(Weapon.Pull.BUSY)
	assert_bool(_weapon.can_fire()).is_false()


func test_an_empty_magazine_with_a_reserve_reloads_by_itself() -> void:
	_weapon.set_ammo(1, 36)
	_pull()
	assert_int(_weapon.ammo).is_equal(0)
	_ticks(ceili(_weapon.definition.shot_interval() / TICK) + 1)
	assert_bool(_weapon.is_reloading()).is_true()
	_ticks(roundi(1.6 / TICK) + 1)
	assert_int(_weapon.ammo).is_equal(12)
	assert_int(_weapon.reserve).is_equal(24)


func test_with_nothing_left_the_trigger_only_clicks() -> void:
	_weapon.set_ammo(0, 0)
	_ticks(20)
	assert_bool(_weapon.is_reloading()).is_false()
	assert_int(_weapon.pull()).is_equal(Weapon.Pull.EMPTY)


func test_ammunition_picked_up_stops_at_the_largest_reserve() -> void:
	_weapon.set_ammo(12, 90)
	assert_int(_weapon.add_ammo(20)).is_equal(6)
	assert_int(_weapon.reserve).is_equal(96)
	assert_int(_weapon.add_ammo(5)).is_equal(0)


func test_a_weapon_given_a_second_definition_fires_with_its_numbers() -> void:
	var quick := _weapon.definition.duplicate() as WeaponDef
	quick.display_name = "Quick"
	quick.projectile_speed = 80.0
	quick.projectile_size = 0.05
	quick.magazine_size = 3
	quick.start_reserve = 6
	quick.fire_rate = 20.0
	quick.damage = 33.0
	_weapon.definition = quick
	assert_int(_weapon.ammo).is_equal(3)
	assert_int(_weapon.reserve).is_equal(6)
	var shot := _weapon.fire()
	assert_float(shot.velocity.length()).is_equal_approx(80.0, 0.001)
	assert_float(shot.size).is_equal(0.05)
	assert_float(shot.damage).is_equal(33.0)
	assert_int(_weapon.ammo).is_equal(2)
	# Its rate: ready again after a twentieth of a second (three ticks, and one for the rounding).
	_ticks(4)
	assert_bool(_weapon.can_fire()).is_true()


func test_a_hitscan_shot_hits_what_the_ray_points_at_with_no_body_and_no_camera() -> void:
	_weapon.definition.kind = WeaponDef.Kind.HITSCAN
	var target := load(TARGET).instantiate() as Target
	target.position = Vector3(3.0, 0.0, -8.0)
	_world.add_child(target)
	await get_tree().physics_frame
	assert_object(get_viewport().get_camera_3d()).is_null()
	var hits: Array[Dictionary] = []
	_weapon.hit_scanned.connect(func(hit: Dictionary) -> void: hits.append(hit))
	var aim_from := Vector3(3.0, 1.0, 2.0)
	assert_int(_weapon.pull(aim_from, Vector3.FORWARD)).is_equal(Weapon.Pull.FIRED)
	assert_int(hits.size()).is_equal(1)
	assert_object(hits[0]["collider"]).is_same(target)
	assert_float(hits[0]["damage"]).is_equal(34.0)
	assert_bool(target.is_down()).is_true()
	assert_array(_weapon.live_projectiles()).is_empty()
	assert_int(_weapon.ammo).is_equal(11)


func test_a_blow_reaches_its_length_and_no_further() -> void:
	_weapon.definition = load(FISTS) as WeaponDef
	assert_object(_weapon.ammo).is_null()
	assert_object(_weapon.magazine_size).is_null()
	var near := load(TARGET).instantiate() as Target
	near.position = Vector3(0.0, 0.0, -0.9)
	_world.add_child(near)
	await get_tree().physics_frame
	var hits: Array[Dictionary] = []
	_weapon.hit_scanned.connect(func(hit: Dictionary) -> void: hits.append(hit))
	assert_int(_weapon.pull(Vector3(0.0, 1.0, 0.0), Vector3.FORWARD)).is_equal(Weapon.Pull.FIRED)
	assert_int(hits.size()).is_equal(1)
	assert_object(hits[0]["collider"]).is_same(near)
	near.position = Vector3(0.0, 0.0, -2.5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_int(_pull()).is_equal(Weapon.Pull.FIRED)
	assert_int(hits.size()).is_equal(1)
	# No ammunition: it never runs out.
	for _blow in 20:
		assert_int(_pull()).is_equal(Weapon.Pull.FIRED)


func test_a_hundred_shots_make_no_new_mesh_shape_or_material() -> void:
	_wall(Vector3(0.0, 1.0, -3.0))
	_weapon.definition.magazine_size = 200
	_weapon.make_ready()
	var meshes := {}
	var shapes := {}
	var paints := {}
	var bodies := {}
	for _shot in 100:
		_weapon.make_ready()
		var shot := _weapon.fire()
		var mesh_node := shot.get_node("%Mesh") as MeshInstance3D
		meshes[mesh_node.mesh.get_instance_id()] = true
		paints[mesh_node.material_override.get_instance_id()] = true
		shapes[(shot.get_node("%Shape") as CollisionShape3D).shape.get_instance_id()] = true
		bodies[shot.get_instance_id()] = true
		await get_tree().physics_frame
	assert_int(meshes.size()).is_equal(1)
	assert_int(shapes.size()).is_equal(1)
	assert_int(paints.size()).is_equal(1)
	# The pool: no more bodies than the cap, fired again and again.
	assert_int(bodies.size()).is_less_equal(_weapon.projectile_cap)


func test_a_held_trigger_never_makes_more_bodies_than_the_cap() -> void:
	_weapon.projectile_cap = 5
	_weapon.definition.magazine_size = 50
	_weapon.make_ready()
	var bodies := {}
	for _shot in 30:
		_weapon.make_ready()
		bodies[_weapon.fire().get_instance_id()] = true
	assert_int(bodies.size()).is_equal(5)
	assert_int(_weapon.live_projectiles().size()).is_equal(5)


func test_the_step_state_puts_back_the_magazine_the_reserve_and_the_reload() -> void:
	_weapon.set_ammo(4, 10)
	_weapon.reload()
	_ticks(30)
	var kept: Array = []
	_weapon.save_step_state(kept)
	_ticks(100)
	assert_int(_weapon.ammo).is_equal(12)
	_weapon.load_step_state(kept)
	assert_int(_weapon.ammo).is_equal(4)
	assert_int(_weapon.reserve).is_equal(10)
	assert_bool(_weapon.is_reloading()).is_true()
	assert_float(_weapon.reload_progress()).is_equal_approx(30.0 * TICK / 1.6, 0.001)


func test_the_reload_plays_its_steps_at_their_shares() -> void:
	_weapon.set_ammo(0, 30)
	_weapon.definition.auto_reload = false
	var sound := _weapon.get_node("%ReloadSound") as AudioStreamPlayer3D
	var heard: Array[AudioStream] = []
	_weapon.reload()
	for _tick in roundi(1.6 / TICK) + 1:
		_weapon.tick(TICK)
		if sound.playing and (heard.is_empty() or heard.back() != sound.stream):
			heard.append(sound.stream)
	assert_array(heard).is_equal(_weapon.definition.reload_sounds)

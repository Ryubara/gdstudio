# The Weapon, its WeaponDef, the Projectile and the Target as components: each export has its
# default pinned, and each number is changed on a weapon that is already set up (as the inspector
# does) and its effect is read in the next shot. The weapon gets its own copy of the pistol's
# definition, so a change here never reaches another suite.
extends GdUnitTestSuite

const WEAPON := "res://gameplay/weapon/weapon.tscn"
const TARGET := "res://gameplay/target/target.tscn"
const PROJECTILE := "res://gameplay/projectile/projectile.tscn"
const PISTOL := "res://gameplay/weapon/pistol.tres"

var _world: Node3D
var _weapon: Weapon
var _muzzle: Marker3D


func before_test() -> void:
	_world = auto_free(Node3D.new())
	add_child(_world)
	_weapon = load(WEAPON).instantiate() as Weapon
	_world.add_child(_weapon)
	_muzzle = Marker3D.new()
	_muzzle.position = Vector3(0.0, 1.0, 0.0)
	_world.add_child(_muzzle)
	_weapon.muzzle = _muzzle
	_weapon.definition = _weapon.definition.duplicate()
	await get_tree().physics_frame


func after_test() -> void:
	AudioDrain.stop_all(_world)


func _shoot() -> Projectile:
	_weapon.make_ready()
	return _weapon.fire()


func test_every_weapon_export_has_its_default_pinned() -> void:
	var pins := {
		&"definition": _weapon.definition,
		&"muzzle": _muzzle,
		&"shooter": null,
		&"no_muzzle_offset": Vector3(0.07, -0.09, -0.65),
		&"aim_mask": PhysicsLayers.SHOT_MASK,
		&"muzzle_flash_enabled": true,
		&"projectile_cap": 24,
		&"self_ticking": true,
	}
	assert_array(ExportPins.differences(_weapon, pins)).is_empty()
	assert_array(ExportPins.wrong_values(_weapon, pins)).is_empty()
	var scene := load(WEAPON).instantiate() as Weapon
	assert_str(scene.definition.resource_path).is_equal(PISTOL)
	scene.free()


func test_the_pistol_definition_holds_the_numbers_the_pistol_always_had() -> void:
	var pistol := load(PISTOL) as WeaponDef
	var pins := {
		&"display_name": "Pistol",
		&"icon": load("res://assets/ui/inventory/weapon_pistol.svg"),
		&"kind": WeaponDef.Kind.PROJECTILE,
		&"automatic": false,
		&"fire_rate": 4.0,
		&"spread": 0.0,
		&"recoil": 1.0,
		&"damage": 34.0,
		&"aim_range": 100.0,
		&"impulse": 40.0,
		&"impacts": true,
		&"magazine_size": 12,
		&"start_reserve": 36,
		&"max_reserve": 96,
		&"ammo_item": &"pistol_ammo",
		&"reload_time": 1.6,
		&"auto_reload": true,
		&"holster_time": 0.2,
		&"draw_time": 0.25,
		&"projectile_scene": pistol.projectile_scene,
		&"projectile_speed": 45.0,
		&"projectile_size": 0.14,
		&"projectile_tint": Color(1.0, 0.85, 0.35),
		&"projectile_gravity": 0.0,
		&"projectile_lifetime": 3.0,
		&"projectile_bounces": 0,
		&"projectile_bounce_keep": 0.6,
		&"category": load("res://gameplay/weapon/categories/pistol.tres"),
		&"override_melee": false,
		&"melee_reach": 1.1,
		&"melee_damage": 15.0,
		&"melee_impulse": 25.0,
		&"melee_cooldown": 0.5,
		&"melee_hit_start": 0.15,
		&"melee_hit_end": 0.25,
		&"view": NodePath("PistolHeld"),
		&"muzzle": NodePath("PistolHeld/Pistol/Pistol/Muzzle"),
		&"grip_clip": CharacterClips.PISTOL_IDLE,
		&"grip_bones": [&"hand_r"] as Array[StringName],
		&"aim_clip": CharacterClips.PISTOL_AIM,
		&"aim_up_clip": CharacterClips.PISTOL_AIM_UP,
		&"aim_down_clip": CharacterClips.PISTOL_AIM_DOWN,
		&"shoot_clips": [CharacterClips.PISTOL_SHOOT] as Array[StringName],
		&"reload_clip": CharacterClips.PISTOL_RELOAD,
		&"shot_sound": pistol.shot_sound,
		&"shot_volume_db": -22.0,
		&"empty_sound": pistol.empty_sound,
		&"reload_sounds": pistol.reload_sounds,
		&"reload_sound_at": PackedFloat32Array([0.2, 0.6, 0.85]),
		&"draw_sound": pistol.draw_sound,
		&"muzzle_flash": pistol.muzzle_flash,
		&"muzzle_flash_size": 1.0,
	}
	assert_array(ExportPins.differences(pistol, pins)).is_empty()
	assert_array(ExportPins.wrong_values(pistol, pins)).is_empty()
	assert_str(pistol.projectile_scene.resource_path).is_equal(PROJECTILE)
	assert_int(pistol.reload_sounds.size()).is_equal(3)
	assert_object(pistol.empty_sound).is_not_null()


func test_every_projectile_and_target_export_has_its_default_pinned() -> void:
	var shot := auto_free(load(PROJECTILE).instantiate()) as Projectile
	var shot_pins := {
		&"size": 0.14,
		&"tint": Color(1.0, 0.85, 0.35),
		&"gravity": 0.0,
		&"lifetime": 3.0,
		&"impulse": 40.0,
		&"damage": 34.0,
		&"bounces": 0,
		&"bounce_keep": 0.6,
		&"impact_effects": true,
	}
	assert_array(ExportPins.differences(shot, shot_pins)).is_empty()
	assert_array(ExportPins.wrong_values(shot, shot_pins)).is_empty()
	var board := auto_free(load(TARGET).instantiate()) as Target
	var board_pins := {
		&"size": 1.0,
		&"tint": Color(0.9, 0.25, 0.2),
		&"hit_tint": Color(0.95, 0.95, 0.95),
		&"drop_angle": 80.0,
		&"drop_time": 0.18,
		&"reset_time": 3.0,
	}
	assert_array(ExportPins.differences(board, board_pins)).is_empty()
	assert_array(ExportPins.wrong_values(board, board_pins)).is_empty()


func test_the_scenes_hold_their_parts_and_the_weapon_warns_only_about_a_missing_muzzle() -> void:
	var shot := auto_free(load(PROJECTILE).instantiate()) as Projectile
	assert_array(shot._get_configuration_warnings()).is_empty()
	var board := auto_free(load(TARGET).instantiate()) as Target
	assert_array(board._get_configuration_warnings()).is_empty()
	assert_array(_weapon._get_configuration_warnings()).is_empty()
	var bare := auto_free(load(WEAPON).instantiate()) as Weapon
	assert_array(bare._get_configuration_warnings()).has_size(1)


func test_the_projectile_speed_size_gravity_and_lifetime_come_from_the_weapon() -> void:
	_weapon.definition.projectile_speed = 20.0
	_weapon.definition.projectile_size = 0.3
	_weapon.definition.projectile_gravity = 9.0
	_weapon.definition.projectile_lifetime = 0.5
	var shot := _shoot()
	assert_float(shot.velocity.length()).is_equal_approx(20.0, 0.001)
	assert_float(shot.size).is_equal(0.3)
	(
		assert_float(((shot.get_node("%Shape") as CollisionShape3D).shape as SphereShape3D).radius)
		. is_equal_approx(0.15, 0.001)
	)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# It falls: the downward speed grows by gravity each tick.
	assert_float(shot.velocity.y).is_less(-0.2)
	await InputSim.ticks(get_tree(), 42)
	# Its lifetime is over: it stopped and waits, hidden, in the weapon's pool.
	assert_bool(shot.is_flying()).is_false()
	assert_bool(shot.visible).is_false()


func test_the_fire_rate_is_how_many_shots_a_second() -> void:
	_weapon.definition.fire_rate = 10.0
	_weapon.fire()
	assert_bool(_weapon.can_fire()).is_false()
	await InputSim.ticks(get_tree(), 9)
	assert_bool(_weapon.can_fire()).is_true()


func test_the_spread_turns_a_shot_off_the_aim_in_a_seeded_order() -> void:
	_weapon.definition.spread = 5.0
	var first := _shoot()
	var second := _shoot()
	var straight := -_muzzle.global_basis.z
	for shot: Projectile in [first, second]:
		var angle := rad_to_deg(shot.velocity.angle_to(straight))
		assert_float(angle).is_less(5.01)
	assert_float(first.velocity.angle_to(second.velocity)).is_greater(0.0)
	# The same order every run: a weapon made again fires the same first shot.
	var again := auto_free(load(WEAPON).instantiate()) as Weapon
	_world.add_child(again)
	again.muzzle = _muzzle
	again.definition = _weapon.definition
	var repeat := again.fire()
	assert_vector(repeat.velocity).is_equal_approx(first.velocity, Vector3.ONE * 0.001)


func test_without_a_camera_the_shot_goes_out_of_the_muzzle() -> void:
	var shot := _shoot()
	var out := -_muzzle.global_basis.z
	assert_float(shot.velocity.normalized().dot(out)).is_greater(0.999)


func test_the_impulse_pushes_a_body_it_hits_and_bounces_turn_the_shot_off_a_wall() -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 10.0, 0.5)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0.0, 1.0, -5.0)
	_world.add_child(wall)
	_weapon.definition.projectile_bounces = 1
	_weapon.definition.projectile_bounce_keep = 0.5
	var shot := _shoot()
	var hits: Array[Node] = []
	shot.impacted.connect(func(c: Node, _p: Vector3, _n: Vector3) -> void: hits.append(c))
	await InputSim.ticks(get_tree(), 24)
	# It struck the wall once, came back at half speed, and is still flying.
	assert_int(hits.size()).is_equal(1)
	assert_bool(shot.is_flying()).is_true()
	assert_float(shot.velocity.z).is_greater(0.0)
	assert_float(shot.velocity.length()).is_equal_approx(22.5, 0.5)
	await InputSim.ticks(get_tree(), 36)
	assert_int(hits.size()).is_greater_equal(1)


func test_a_target_drops_when_its_health_is_gone_and_shows_the_hit_colour() -> void:
	var board := auto_free(load(TARGET).instantiate()) as Target
	_world.add_child(board)
	var health := Health.of(board)
	assert_float(health.max_value).is_equal(1.0)
	health.max_value = 60.0
	health.reset()
	var paint := (
		(board.get_node("%Board") as MeshInstance3D).material_override as StandardMaterial3D
	)
	assert_object(paint.albedo_color).is_equal(board.tint)
	var said: Array[HitRecord] = []
	board.shot.connect(func(hit: HitRecord) -> void: said.append(hit))
	health.apply(HitRecord.shot(34.0, &"", &"", Vector3.ZERO, Vector3.FORWARD, 0.0))
	assert_bool(board.is_down()).is_false()
	health.apply(HitRecord.shot(34.0, &"", &"", Vector3.ZERO, Vector3.FORWARD, 0.0))
	assert_bool(board.is_down()).is_true()
	assert_int(said.size()).is_equal(2)
	assert_object(paint.albedo_color).is_equal(board.hit_tint)
	board.tint = Color(0.1, 0.9, 0.2)
	board.hit_tint = Color(0.0, 0.0, 1.0)
	assert_object(paint.albedo_color).is_equal(Color(0.0, 0.0, 1.0))
	board.size = 2.0
	(
		assert_float(
			((board.get_node("%Shape") as CollisionShape3D).shape as CylinderShape3D).radius
		)
		. is_equal(1.0)
	)
	assert_float((board.get_node("%Pivot") as Node3D).position.y).is_equal_approx(1.5, 0.001)


func test_a_target_that_never_resets_stays_down() -> void:
	var board := auto_free(load(TARGET).instantiate()) as Target
	_world.add_child(board)
	board.reset_time = 0.0
	board.drop_time = 0.05
	Health.of(board).apply(HitRecord.blow(1.0))
	await InputSim.ticks(get_tree(), 24)
	assert_bool(board.is_down()).is_true()
	assert_float(board.tilt()).is_equal_approx(board.drop_angle, 0.5)
	board.drop_angle = 30.0
	await InputSim.ticks(get_tree(), 18)
	assert_float(board.tilt()).is_equal_approx(30.0, 0.5)

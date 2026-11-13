# The `WeaponDef.hitscan` toggle (gdstudio #1252): a projectile weapon turned hitscan fires one
# instant ray from the aim and makes no projectile node, switches back and forth live, reaches its
# `hitscan_range` and meets only its `hitscan_mask`; on a character it hits the same body part for
# the same damage as a projectile does, and a friend's hitscan shot is refused as a friend's
# projectile is.
extends GdUnitTestSuite

const WEAPON := "res://gameplay/weapon/weapon.tscn"
const DRESSED := "res://gameplay/character/character_dressed.tscn"
const RELATIONS := "res://gameplay/ai/relations/ai_relations.tres"
const ALLY := "res://gameplay/ai/profiles/ally.tres"
const TICK := 1.0 / 60.0
## Where the character stands in front of the muzzle, and the heights of its chest and head.
const TARGET_AT := Vector3(0.0, 0.0, -6.0)
const CHEST := 1.3
const HEAD := 1.62

var _world: Node3D
var _weapon: Weapon
var _last_projectile_hit: HitRecord


func before_test() -> void:
	_world = auto_free(Node3D.new())
	add_child(_world)
	_weapon = load(WEAPON).instantiate() as Weapon
	_weapon.self_ticking = false
	_world.add_child(_weapon)
	var muzzle := Marker3D.new()
	muzzle.position = Vector3(0.0, 1.0, 0.0)
	_world.add_child(muzzle)
	_weapon.muzzle = muzzle
	_weapon.definition = _weapon.definition.duplicate()
	await get_tree().physics_frame


func after_test() -> void:
	AudioDrain.stop_all(_world)


func _wall(at: Vector3, layer := 1) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = layer
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 4.0, 0.2)
	shape.shape = box
	wall.add_child(shape)
	wall.position = at
	_world.add_child(wall)
	return wall


func _floor() -> void:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	_world.add_child(floor_body)


func _projectiles_in_tree() -> int:
	return get_tree().root.find_children("*", "Projectile", true, false).size()


func test_the_toggle_fires_a_ray_with_no_projectile_and_switches_back_live() -> void:
	var wall := _wall(Vector3(0.0, 1.0, -8.0))
	await get_tree().physics_frame
	var definition := _weapon.definition
	definition.hitscan = true
	assert_int(definition.shot_kind()).is_equal(WeaponDef.Kind.HITSCAN)
	var left: Array = []
	var hits: Array[Dictionary] = []
	_weapon.fired.connect(func(shot: Projectile) -> void: left.append(shot))
	_weapon.hit_scanned.connect(func(hit: Dictionary) -> void: hits.append(hit))
	var nodes_before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var in_tree := _projectiles_in_tree()
	for shot in 3:
		_weapon.make_ready()
		assert_int(_weapon.pull(Vector3(0.0, 1.0, 2.0), Vector3.FORWARD)).is_equal(
			Weapon.Pull.FIRED
		)
	assert_array(left).is_equal([null, null, null])
	assert_int(hits.size()).is_equal(3)
	assert_object(hits[0]["collider"]).is_same(wall)
	assert_array(_weapon.live_projectiles()).is_empty()
	assert_int(_projectiles_in_tree()).is_equal(in_tree)
	# Not a node made for a shot (the muzzle flash plays only with an EffectEmitter in the level).
	assert_float(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)).is_equal(nodes_before)
	# Off again: the next shot is a projectile, with no other change.
	definition.hitscan = false
	_weapon.make_ready()
	assert_object(_weapon.fire(Vector3(0.0, 1.0, 2.0), Vector3.FORWARD)).is_not_null()
	assert_int(_weapon.live_projectiles().size()).is_equal(1)
	definition.hitscan = true
	_weapon.make_ready()
	assert_object(_weapon.fire(Vector3(0.0, 1.0, 2.0), Vector3.FORWARD)).is_null()
	assert_int(hits.size()).is_equal(4)


func test_a_melee_weapon_stays_a_blow_with_the_toggle_on() -> void:
	var fists := load("res://gameplay/weapon/fists.tres").duplicate() as WeaponDef
	fists.hitscan = true
	assert_int(fists.shot_kind()).is_equal(WeaponDef.Kind.MELEE)
	assert_float(fists.ray_reach()).is_equal(fists.melee_reach)


func test_a_hitscan_shot_reaches_its_range_and_meets_only_its_mask() -> void:
	var wall := _wall(Vector3(0.0, 1.0, -8.0), 1)
	await get_tree().physics_frame
	var definition := _weapon.definition
	definition.hitscan = true
	var hits: Array[Dictionary] = []
	_weapon.hit_scanned.connect(func(hit: Dictionary) -> void: hits.append(hit))
	# The wall is 8 m from the muzzle: a 5 m ray stops short of it.
	definition.hitscan_range = 5.0
	_weapon.make_ready()
	_weapon.pull()
	assert_int(hits.size()).is_equal(0)
	definition.hitscan_range = 20.0
	_weapon.make_ready()
	_weapon.pull()
	assert_int(hits.size()).is_equal(1)
	assert_object(hits[0]["collider"]).is_same(wall)
	# A mask without the wall's layer goes through it.
	definition.hitscan_mask = PhysicsLayers.SHOT_MASK & ~1
	_weapon.make_ready()
	_weapon.pull()
	assert_int(hits.size()).is_equal(1)


func test_a_hitscan_shot_takes_the_part_and_damage_a_projectile_takes() -> void:
	_floor()
	var other := load(DRESSED).instantiate() as Character
	other.position = TARGET_AT
	_world.add_child(other)
	await InputSim.ticks(get_tree(), 4)
	var taken: Array[HitRecord] = []
	Health.of(other).hit_taken.connect(func(hit: HitRecord) -> void: taken.append(hit))
	var definition := _weapon.definition
	for height in [CHEST, HEAD]:
		for hitscan in [false, true]:
			Health.of(other).value = Health.of(other).max_value
			# A hit pushes the body back: each shot finds it where the first did.
			other.teleport(TARGET_AT, 0.0)
			await InputSim.ticks(get_tree(), 2)
			definition.hitscan = hitscan
			_weapon.make_ready()
			var from := Vector3(0.0, height, 0.0)
			assert_int(_weapon.pull(from, Vector3.FORWARD)).is_equal(Weapon.Pull.FIRED)
			var arrived := func() -> bool: return taken.size() >= 1
			for _tick in 30:
				if arrived.call():
					break
				await get_tree().physics_frame
			(
				assert_int(taken.size())
				. override_failure_message("height %.2f hitscan %s" % [height, hitscan])
				. is_equal(1)
			)
			if taken.is_empty():
				return
			if hitscan:
				var projectile_hit: HitRecord = _last_projectile_hit
				assert_str(String(taken[0].zone)).is_equal(String(projectile_hit.zone))
				assert_float(taken[0].damage).is_equal_approx(projectile_hit.damage, 0.001)
			else:
				_last_projectile_hit = taken[0]
			taken.clear()
			# The flinch of the hit moves the parts: the next shot waits until it is over.
			await InputSim.ticks(get_tree(), 60)


func test_a_friend_hitscan_shot_is_refused_as_a_friend_projectile_is() -> void:
	var arena := auto_free(AiArena.new()) as AiArena
	add_child(arena)
	var factions := AiFactions.new()
	factions.name = "AiFactions"
	factions.relations = load(RELATIONS) as AiRelations
	arena.add_child(factions)
	var grunt := arena.add_character(Vector3(0.0, 0.0, 0.0))
	var other := arena.add_character(Vector3(0.0, 0.0, -5.0))
	var ally := arena.add_character(Vector3(3.0, 0.0, 0.0), load(ALLY) as AiProfile)
	await InputSim.ticks(get_tree(), 4)
	var health := Health.of(other)
	var full := health.value
	var dealt := {}
	for shooter: AiCharacter in [grunt, ally]:
		var weapon := shooter.weapon
		weapon.definition = weapon.definition.duplicate()
		for hitscan in [false, true]:
			health.value = full
			weapon.definition.hitscan = hitscan
			weapon.make_ready()
			weapon.lowered = false
			var eye := shooter.global_position + Vector3.UP * CHEST
			var chest := other.global_position + Vector3.UP * CHEST
			assert_int(weapon.pull(eye, (chest - eye).normalized())).is_equal(Weapon.Pull.FIRED)
			await InputSim.ticks(get_tree(), 20)
			dealt["%s %s" % [shooter.name, hitscan]] = full - health.value
			# The hit's stun and flinch move the parts (an arm kept on the weapon can cover the
			# chest): the next shot waits until they are over (kit #1345).
			await InputSim.ticks(get_tree(), 40)
	prints("damage dealt (shooter, hitscan):", dealt)
	# The grunt's friend is unhurt by either kind of shot; the ally's lands with either.
	assert_float(dealt["%s false" % grunt.name]).is_equal(0.0)
	assert_float(dealt["%s true" % grunt.name]).is_equal(0.0)
	assert_float(dealt["%s false" % ally.name]).is_greater(0.0)
	assert_float(dealt["%s true" % ally.name]).is_equal(dealt["%s false" % ally.name])
	AudioDrain.stop_all(arena)

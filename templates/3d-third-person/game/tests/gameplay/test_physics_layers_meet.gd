# What meets what, by physics layer and nothing else (#924): a shot meets a character, a wall, a
# prop and the bones of a dead body; the character's capsule, the camera's arm and the trigger
# areas never meet a ragdoll bone, a hit zone, a shot in flight or another character.
extends GdUnitTestSuite

## The layers that movement, the camera and the areas must never meet.
const NEVER_MET := (
	PhysicsLayers.RAGDOLL
	| PhysicsLayers.HIT_ZONES
	| PhysicsLayers.PROJECTILES
	| PhysicsLayers.SENSORS
)

var _arena: PlayArena
var _hits: Array[Node] = []


func before_test() -> void:
	_arena = auto_free(ImpactShots.world(self))
	_hits.clear()
	await get_tree().physics_frame


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


# A static box of `size` centred at `at`, on `layer` and masking nothing.
func _box(at: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = at
	_arena.add_child(body)
	return body


func _on_impacted(collider: Node, _at: Vector3, _normal: Vector3) -> void:
	_hits.append(collider)


# Fires a real projectile from `from` toward `toward` and returns what it hit (null for nothing).
func _shot(from: Vector3, toward: Vector3) -> Node:
	var shot := ImpactShots.fire(_arena, from, toward)
	shot.impacted.connect(_on_impacted)
	await ImpactShots.land(get_tree(), shot)
	return _hits.back() if not _hits.is_empty() else null


func test_the_scenes_put_each_body_on_the_layer_of_what_it_is() -> void:
	var player := load("res://gameplay/player/player.tscn").instantiate() as Player
	var shot := load(ImpactShots.PROJECTILE).instantiate() as Projectile
	var prop := load("res://gameplay/physics_prop/physics_prop.tscn").instantiate() as PhysicsProp
	assert_int(player.collision_layer).is_equal(PhysicsLayers.CHARACTERS)
	assert_int(player.collision_mask).is_equal(PhysicsLayers.CHARACTER_MASK)
	assert_int(player.ragdoll_body.collision_layer).is_equal(PhysicsLayers.RAGDOLL)
	assert_int(player.ragdoll_body.collision_mask).is_equal(PhysicsLayers.RAGDOLL_MASK)
	assert_int(shot.collision_layer).is_equal(PhysicsLayers.PROJECTILES)
	assert_int(shot.collision_mask).is_equal(PhysicsLayers.SHOT_MASK)
	assert_int(prop.collision_layer).is_equal(PhysicsLayers.PROPS)
	assert_int(prop.collision_mask).is_equal(PhysicsLayers.PROP_MASK)
	for free_me: Node in [player, shot, prop]:
		free_me.free()


func test_a_shot_meets_a_character_a_wall_and_a_prop_by_layer() -> void:
	var wall := _box(Vector3(0.0, 1.5, -8.0), Vector3(6.0, 3.0, 0.5), PhysicsLayers.WORLD)
	assert_object(await _shot(Vector3(0.0, 1.5, 0.0), Vector3(0.0, 1.5, -8.0))).is_same(wall)
	var crate := _box(Vector3(2.0, 1.0, -4.0), Vector3.ONE, PhysicsLayers.PROPS)
	assert_object(await _shot(Vector3(2.0, 1.0, 0.0), Vector3(2.0, 1.0, -8.0))).is_same(crate)
	var player := _arena.add_player(Vector3(-2.0, 0.0, -4.0))
	await InputSim.ticks(get_tree(), 4)
	assert_object(await _shot(Vector3(-2.0, 1.2, 0.0), Vector3(-2.0, 1.2, -8.0))).is_same(player)


func test_a_shot_passes_what_is_not_on_its_mask() -> void:
	var wall := _box(Vector3(0.0, 1.5, -8.0), Vector3(6.0, 3.0, 0.5), PhysicsLayers.WORLD)
	_box(Vector3(0.0, 1.5, -4.0), Vector3.ONE, PhysicsLayers.SENSORS | PhysicsLayers.PROJECTILES)
	assert_object(await _shot(Vector3(0.0, 1.5, 0.0), Vector3(0.0, 1.5, -8.0))).is_same(wall)


func test_a_shot_meets_a_bone_of_a_dead_body_and_not_of_a_living_one() -> void:
	var wall := _box(Vector3(0.0, 1.0, -8.0), Vector3(6.0, 2.0, 0.5), PhysicsLayers.WORLD)
	var player := _arena.add_player(Vector3(0.0, 0.0, -4.0))
	await InputSim.ticks(get_tree(), 4)
	# Alive, the bones are not in the world: a shot from the side at hand height, past the capsule,
	# reaches the wall (the bones of a living body never stop the shooter's own shots either).
	var beside := player.global_position + Vector3(0.6, 1.0, 0.0)
	var passed: Node = await _shot(beside + Vector3(0.0, 0.0, 4.0), beside + Vector3.FORWARD * 4.0)
	assert_object(passed).is_same(wall)
	player.die()
	await InputSim.ticks(get_tree(), 150)
	var chest := player.ragdoll_body.body(&"spine_03")
	assert_object(chest).is_not_null()
	var at := chest.global_position
	var hit: Node = await _shot(at + Vector3(0.0, 3.0, 0.5), at)
	assert_object(hit).is_instanceof(PhysicalBone3D)


func test_a_living_body_that_never_died_has_no_bone_in_the_world() -> void:
	# The bones are made when the character is; until the body goes limp they must be out of the
	# world, or a shot or the aim ray stops at a living body's head (it rises past the capsule).
	var player := _arena.add_player(Vector3(0.0, 0.0, -4.0))
	await InputSim.ticks(get_tree(), 4)
	var space := _arena.get_world_3d().direct_space_state
	for bone_name: StringName in [&"Head", &"spine_03", &"hand_r", &"calf_l"]:
		var at := player.ragdoll_body.body(bone_name).global_position
		var query := PhysicsRayQueryParameters3D.create(
			at + Vector3(0.0, 0.0, 2.0), at, PhysicsLayers.SHOT_MASK, [player.get_rid()]
		)
		var found := space.intersect_ray(query)
		(
			assert_bool(found.is_empty())
			. override_failure_message(
				"%s of a living body is in the world: %s" % [bone_name, found]
			)
			. is_true()
		)


func test_the_aim_ray_finds_a_dead_body() -> void:
	var player := _arena.add_player(Vector3(0.0, 0.0, -4.0))
	await InputSim.ticks(get_tree(), 4)
	player.die()
	await InputSim.ticks(get_tree(), 150)
	var at := player.ragdoll_body.body(&"spine_03").global_position
	var weapon := load("res://gameplay/weapon/weapon.tscn").instantiate() as Weapon
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at, weapon.aim_mask)
	var found := _arena.get_world_3d().direct_space_state.intersect_ray(query)
	weapon.free()
	assert_bool(found.is_empty()).is_false()
	assert_object(found.get("collider")).is_instanceof(PhysicalBone3D)


func test_the_character_walks_through_bones_hit_zones_shots_sensors_and_characters() -> void:
	var player := _arena.add_player(Vector3(0.0, 0.0, 0.0))
	_box(Vector3(0.0, 1.0, -2.0), Vector3(4.0, 2.0, 0.4), NEVER_MET)
	# Another character's capsule (a plain body: a second `Player` would read the same keys).
	var other := CharacterBody3D.new()
	var capsule := CollisionShape3D.new()
	capsule.shape = CapsuleShape3D.new()
	capsule.position.y = 1.0
	other.add_child(capsule)
	other.collision_layer = PhysicsLayers.CHARACTERS
	other.collision_mask = PhysicsLayers.CHARACTER_MASK
	other.position = Vector3(0.0, 0.0, -4.0)
	_arena.add_child(other)
	await InputSim.ticks(get_tree(), 4)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 90)
	InputSim.key(KEY_W, false)
	# Past the box at z = -2 and through the other character at z = -4.
	assert_float(player.global_position.z).is_less(-5.0)
	assert_float(other.global_position.z).is_equal_approx(-4.0, 0.05)


func test_the_character_is_stopped_by_a_wall_and_a_prop() -> void:
	var player := _arena.add_player(Vector3(0.0, 0.0, 0.0))
	_box(Vector3(0.0, 1.0, -2.0), Vector3(4.0, 2.0, 0.4), PhysicsLayers.PROPS)
	await InputSim.ticks(get_tree(), 4)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 60)
	InputSim.key(KEY_W, false)
	assert_float(player.global_position.z).is_greater(-2.0)


func test_a_trigger_zone_and_a_pickup_never_hear_of_bones_hit_zones_shots_or_the_level() -> void:
	var zone := load("res://gameplay/trigger_zone/trigger_zone.tscn").instantiate() as TriggerZone
	zone.counts = TriggerZone.Counts.ANY
	zone.position = Vector3(0.0, 1.0, 0.0)
	_arena.add_child(zone)
	var coin := load("res://gameplay/pickup/pickup.tscn").instantiate() as Pickup
	coin.characters_only = false
	coin.position = Vector3(3.0, 1.0, 0.0)
	_arena.add_child(coin)
	var heard: Array[Node3D] = []
	zone.body_entered.connect(func(body: Node3D) -> void: heard.append(body))
	coin.body_entered.connect(func(body: Node3D) -> void: heard.append(body))
	_box(Vector3(0.0, 1.0, 0.0), Vector3.ONE * 0.5, NEVER_MET)
	_box(Vector3(3.0, 1.0, 0.0), Vector3.ONE * 0.5, NEVER_MET | PhysicsLayers.WORLD)
	await InputSim.ticks(get_tree(), 10)
	# The floor under both and the boxes inside them: none reaches the scripts.
	assert_array(heard).is_empty()
	assert_bool(zone.is_active()).is_false()
	assert_bool(coin.is_available()).is_true()


func test_the_camera_arm_is_pushed_in_by_a_wall_and_never_by_a_body_or_a_bone() -> void:
	var scene := scene_runner("res://main.tscn").scene()
	var camera := scene.get_node("PlayerRig/Camera") as Camera3D
	var head := scene.get_node("PlayerRig/Player/CameraTarget") as Node3D
	await InputSim.ticks(get_tree(), 30)
	var open_view := camera.global_position.distance_to(head.global_position)
	assert_float(open_view).is_greater(1.4)
	var away := (camera.global_position - head.global_position).normalized()
	var slab := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 8.0, 0.2)
	shape.shape = box
	slab.add_child(shape)
	slab.collision_layer = NEVER_MET | PhysicsLayers.CHARACTERS
	slab.collision_mask = 0
	scene.add_child(slab)
	slab.global_position = head.global_position + away * 0.8
	slab.look_at(head.global_position, Vector3.UP if absf(away.y) < 0.9 else Vector3.FORWARD)
	await InputSim.ticks(get_tree(), 30)
	var through := camera.global_position.distance_to(head.global_position)
	assert_float(through).is_equal_approx(open_view, 0.1)
	slab.collision_layer = PhysicsLayers.WORLD
	await InputSim.ticks(get_tree(), 30)
	assert_float(camera.global_position.distance_to(head.global_position)).is_less(0.9)
	AudioDrain.stop_all(scene)

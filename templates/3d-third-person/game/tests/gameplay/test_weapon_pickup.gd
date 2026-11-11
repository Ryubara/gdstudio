# The rifle's floating pickup through simulated input in the real physics world: walking into it
# gives the rifle with a full magazine and the pickup's rounds and brings it out; it comes back
# after its respawn time; with the rifle carried it gives only the rounds; with a full reserve it
# stays where it is; the rifle then fires automatically while the button is held; a body with no
# loadout leaves it; and the loadout's step state takes a given weapon back.
extends GdUnitTestSuite

const RIFLE_PICKUP := "res://gameplay/pickup/rifle_pickup.tscn"
const RIFLE := "res://gameplay/weapon/rifle.tres"

var _arena: PlayArena
var _player: Player
var _camera: Camera3D


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(_camera)
	_camera.make_current()
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


func _pickup(respawn: float = 20.0) -> WeaponPickup:
	var pickup := load(RIFLE_PICKUP).instantiate() as WeaponPickup
	pickup.respawn_time = respawn
	pickup.position = Vector3(0.0, 0.0, -1.6)
	_arena.add_child(pickup)
	return pickup


func _seconds(seconds: float) -> void:
	await InputSim.ticks(get_tree(), ceili(seconds * Engine.physics_ticks_per_second) + 1)


# Walks forward into the pickup and back out of it.
func _walk_through() -> void:
	InputSim.key(KEY_W, true)
	await _seconds(0.8)
	InputSim.key(KEY_W, false)
	await _seconds(0.3)
	InputSim.key(KEY_S, true)
	await _seconds(0.9)
	InputSim.key(KEY_S, false)
	await _seconds(0.3)


func _rifle_slot() -> int:
	return _player.loadout.slot_of(load(RIFLE) as WeaponDef)


func test_walking_into_the_pickup_gives_the_rifle_and_its_rounds() -> void:
	var pickup := _pickup()
	assert_int(_rifle_slot()).is_equal(-1)
	await _walk_through()
	assert_bool(pickup.is_available()).is_false()
	assert_int(_rifle_slot()).is_equal(1)
	assert_int(_player.loadout.slots.size()).is_equal(2)
	await _seconds(0.8)
	assert_str(_player.weapon.definition.display_name).is_equal("Rifle")
	assert_int(_player.weapon.ammo).is_equal(30)
	assert_int(_player.weapon.reserve).is_equal(60)
	assert_bool((_player.model.get_node("RifleHeld") as Node3D).visible).is_true()
	assert_bool((_player.model.get_node("PistolHeld") as Node3D).visible).is_false()


func test_the_pickup_comes_back_after_its_respawn_time() -> void:
	var pickup := _pickup(1.5)
	var back: Array[bool] = []
	pickup.respawned.connect(func() -> void: back.append(true))
	InputSim.key(KEY_W, true)
	await _seconds(0.8)
	InputSim.key(KEY_W, false)
	assert_bool(pickup.is_available()).is_false()
	InputSim.key(KEY_S, true)
	await _seconds(0.9)
	InputSim.key(KEY_S, false)
	assert_bool(pickup.is_available()).is_false()
	await _seconds(1.0)
	assert_int(back.size()).is_equal(1)
	assert_bool(pickup.is_available()).is_true()
	assert_bool((pickup.get_node("Glow") as Node3D).visible).is_true()


func test_with_the_rifle_carried_it_gives_only_rounds() -> void:
	var pickup := _pickup(2.8)
	await _walk_through()
	await _seconds(0.8)
	assert_bool(pickup.is_available()).is_true()
	var given: Array[int] = []
	pickup.weapon_taken.connect(
		func(_who: Node3D, _what: WeaponDef, how: WeaponLoadout.Given) -> void: given.append(how)
	)
	await _walk_through()
	assert_int(given.size()).is_equal(1)
	assert_int(given[0]).is_equal(WeaponLoadout.Given.AMMO)
	assert_int(_player.loadout.slots.size()).is_equal(2)
	assert_int(_player.weapon.reserve).is_equal(120)


func test_with_a_full_reserve_the_pickup_stays() -> void:
	var pickup := _pickup(2.8)
	await _walk_through()
	await _seconds(0.8)
	assert_bool(pickup.is_available()).is_true()
	_player.weapon.add_ammo(999)
	assert_int(_player.weapon.reserve).is_equal(180)
	await _walk_through()
	assert_bool(pickup.is_available()).is_true()
	assert_int(_player.weapon.reserve).is_equal(180)


func test_the_rifle_fires_while_the_button_is_held() -> void:
	_pickup()
	await _walk_through()
	await _seconds(0.8)
	var shots: Array[int] = []
	_player.weapon.fired.connect(func(_shot: Projectile) -> void: shots.append(1))
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await _seconds(1.0)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	await _seconds(0.1)
	# Ten a second, after the shoulder comes up: more than one shot from one press.
	assert_int(shots.size()).is_greater_equal(7)
	assert_int(_player.weapon.ammo).is_equal(30 - shots.size())


func test_a_body_with_no_loadout_leaves_it() -> void:
	var pickup := _pickup()
	var body := CharacterBody3D.new()
	body.collision_layer = 2
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	body.add_child(shape)
	body.position = Vector3(3.0, 0.8, -1.6)
	_arena.add_child(body)
	await _seconds(0.1)
	body.position = Vector3(0.0, 0.8, -1.6)
	await _seconds(0.2)
	assert_bool(pickup.is_available()).is_true()


func test_the_step_state_takes_a_given_weapon_back() -> void:
	var before_pickup := _player.state_snapshot()
	var pickup := _pickup()
	await _walk_through()
	assert_bool(pickup.is_available()).is_false()
	assert_int(_player.loadout.slots.size()).is_equal(2)
	_player.restore(before_pickup)
	assert_int(_player.loadout.slots.size()).is_equal(1)
	assert_int(_rifle_slot()).is_equal(-1)
	assert_bool((_player.model.get_node("RifleHeld") as Node3D).visible).is_false()
	assert_str(_player.weapon.definition.display_name).is_equal("Pistol")


func test_both_hands_reach_the_rifle_and_let_go_when_it_is_put_away() -> void:
	_pickup()
	await _walk_through()
	await _seconds(0.8)
	var hold := _player.model.get_node("RifleHeld") as TwoHandHold
	assert_int(hold.modifiers().size()).is_equal(5)
	for modifier in hold.modifiers():
		assert_bool(modifier.active).is_true()
	var skeleton := _player.model.skeleton()
	await skeleton.skeleton_updated
	for side: String in ["r", "l"]:
		var target := (
			hold.find_child("RightHandTarget" if side == "r" else "LeftHandTarget", true, false)
			as Node3D
		)
		var hand := (
			skeleton.global_transform
			* skeleton.get_bone_global_pose(skeleton.find_bone("hand_" + side))
		)
		assert_float(hand.origin.distance_to(target.global_position)).is_less(0.02)
	_player.loadout.select(0)
	await _seconds(0.9)
	assert_bool(hold.visible).is_false()
	for modifier in hold.modifiers():
		assert_bool(modifier.active).is_false()

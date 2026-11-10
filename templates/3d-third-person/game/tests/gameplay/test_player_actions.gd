# What the character does to the world: pushes props, uses doors, takes pickups, takes a hit and
# starts again when it falls out of the map, through simulated input in the real physics world.
extends GdUnitTestSuite

const TICKS := 60
const PROP := "res://gameplay/physics_prop/physics_prop.tscn"

var _arena: PlayArena
var _player: Player


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 0.0))
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()


func _animation() -> CharacterAnimation:
	return _player.get_node("Animation")


func test_it_pushes_a_prop_it_walks_into_and_the_animation_pushes() -> void:
	var crate := load(PROP).instantiate() as PhysicsProp
	crate.weight = 10.0
	crate.position = Vector3(0.0, 0.5, -1.2)
	_arena.add_child(crate)
	await InputSim.ticks(get_tree(), 4)
	InputSim.key(KEY_W, true)
	var pushing := false
	var animated := false
	for _tick in TICKS * 2:
		await get_tree().physics_frame
		pushing = pushing or _player.state == Player.State.PUSH
		animated = animated or _animation().body_state() == &"push"
	assert_bool(pushing).is_true()
	assert_bool(animated).is_true()
	assert_float(crate.global_position.z).is_less(-3.0)


func test_a_light_prop_is_pushed_faster_than_a_heavy_one() -> void:
	var light := load(PROP).instantiate() as PhysicsProp
	light.weight = 5.0
	light.position = Vector3(-6.0, 0.5, -1.2)
	var heavy := load(PROP).instantiate() as PhysicsProp
	heavy.weight = 200.0
	heavy.position = Vector3(6.0, 0.5, -1.2)
	_arena.add_child(light)
	_arena.add_child(heavy)
	await InputSim.ticks(get_tree(), 4)
	_player.teleport(Vector3(-6.0, 0.0, 0.0))
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 60)
	var light_moved := absf(light.global_position.z + 1.2)
	InputSim.key(KEY_W, false)
	_player.teleport(Vector3(6.0, 0.0, 0.0))
	await InputSim.ticks(get_tree(), 4)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 60)
	var heavy_moved := absf(heavy.global_position.z + 1.2)
	assert_float(light_moved).is_greater(heavy_moved * 2.0)


func test_the_interact_key_opens_the_door_in_front_and_it_stands_to_use_it() -> void:
	var door := load("res://gameplay/door/door.tscn").instantiate() as Door
	door.open_time = 0.3
	door.position = Vector3(0.0, 0.0, -1.2)
	_arena.add_child(door)
	await InputSim.ticks(get_tree(), 4)
	var used := []
	_player.interacted.connect(func(target: Node3D) -> void: used.append(target))
	InputSim.key(KEY_E, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_E, false)
	await InputSim.ticks(get_tree(), 4)
	assert_array(used).has_size(1)
	assert_object(used[0]).is_same(door)
	assert_int(_player.state).is_equal(Player.State.INTERACT)
	assert_bool(_animation().is_acting()).is_true()
	assert_str(_animation().last_action()).is_equal(String(CharacterClips.INTERACT))
	await InputSim.ticks(get_tree(), 30)
	assert_bool(door.is_open()).is_true()


func test_interact_does_nothing_when_nothing_is_in_reach() -> void:
	var used := []
	_player.interacted.connect(func(target: Node3D) -> void: used.append(target))
	InputSim.key(KEY_E, true)
	await InputSim.ticks(get_tree(), 3)
	assert_array(used).is_empty()
	assert_int(_player.state).is_not_equal(Player.State.INTERACT)


func test_a_pickup_it_touches_is_counted_and_gone() -> void:
	var coin := load("res://gameplay/pickup/pickup.tscn").instantiate() as Pickup
	coin.position = Vector3(0.0, 0.9, -1.0)
	_arena.add_child(coin)
	var got := []
	_player.item_collected.connect(
		func(id: StringName, amount: int, total: int) -> void: got.append([id, amount, total])
	)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 40)
	assert_array(got).has_size(1)
	assert_array(got[0]).is_equal([&"coin", 1, 1])
	assert_int(_player.count_of(&"coin")).is_equal(1)


func test_a_hit_stops_it_and_throws_it_back_and_the_hit_clip_plays() -> void:
	var source := Node3D.new()
	auto_free(source)
	_arena.add_child(source)
	source.position = Vector3(0.0, 0.0, -1.0)
	var hits := []
	_player.took_hit.connect(func(amount: float, from: Node3D) -> void: hits.append([amount, from]))
	_player.hit(2.0, source)
	await InputSim.ticks(get_tree(), 3)
	assert_array(hits).has_size(1)
	assert_int(_player.state).is_equal(Player.State.HIT)
	assert_float(_player.velocity.z).is_greater(1.0)
	assert_str(_animation().last_action()).is_equal(String(CharacterClips.HIT))
	await InputSim.ticks(get_tree(), 40)
	assert_int(_player.state).is_not_equal(Player.State.HIT)


func test_it_starts_again_at_its_spawn_point_when_it_falls_out_of_the_map() -> void:
	var spawn := SpawnPoint.new()
	spawn.position = Vector3(4.0, 0.0, 4.0)
	_arena.add_child(spawn)
	_player.teleport(Vector3(0.0, _player.tuning.fall_limit - 1.0, 0.0))
	await InputSim.ticks(get_tree(), 3)
	assert_vector(_player.global_position).is_equal_approx(
		Vector3(4.0, 0.0, 4.0), Vector3.ONE * 0.2
	)

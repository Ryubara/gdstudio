# `AiSpawner` across worlds and servers (kit #969, split from test_ai_spawner.gd for gdlint's 20
# public methods, kit #1279): a player in another world neither wakes it nor leads its friendlies,
# a client of a remote server spawns nothing, a map under a server spawns only when asked, and a
# map that handed its AI to a server stops spawning.
extends GdUnitTestSuite

const GRUNT := "res://gameplay/ai/characters/enemy_grunt.tscn"
const ALLY := "res://gameplay/ai/characters/ally.tscn"
const TICKS := 60

var _arena: BehaviourArena
var _director: AiDirector


func before_test() -> void:
	_arena = auto_free(BehaviourArena.new())
	add_child(_arena)
	_arena.build()
	await _arena.settle()
	_director = _arena.add_director()


# The parked characters are out of the tree, so the orphan count would name them before the
# arena (and with it each spawner, which frees them) goes.
func after_test() -> void:
	AudioDrain.stop_all(_arena)
	for spawner: AiSpawner in _arena.find_children("*", "AiSpawner", false, false):
		spawner.pool().clear()


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _marker(spot: Vector3, heading := 0.0) -> Marker3D:
	var marker := Marker3D.new()
	marker.position = spot
	marker.rotation.y = heading
	_arena.add_child(marker)
	return marker


# A spawner of `scene` set up with `changes` before it enters the tree.
func _spawner(scene := GRUNT, changes := {}) -> AiSpawner:
	var spawner := AiSpawner.new()
	spawner.scene = load(scene)
	spawner.count = 2
	spawner.respawn_delay = 1.0
	spawner.markers = [_marker(Vector3(-4, 0, 0)), _marker(Vector3(4, 0, 0), PI)]
	for key: String in changes:
		spawner.set(key, changes[key])
	_arena.add_child(spawner)
	return spawner


func test_a_player_in_another_world_neither_wakes_it_nor_leads_its_friendlies() -> void:
	# A client's player in the same process as a server's map (a test, a capture): its own world,
	# first in the group's order and within reach.
	var view: SubViewport = auto_free(SubViewport.new())
	view.own_world_3d = true
	add_child(view)
	move_child(view, 0)
	var stranger := Node3D.new()
	stranger.add_to_group(&"player")
	stranger.position = Vector3(0, 0, 2)
	view.add_child(stranger)
	var player := _arena.viewer
	player.position = Vector3(0, 0, 60)
	var spawner := _spawner(ALLY, {"wake_range": 10.0, "leader_group": &"player"})
	await _ticks(40)
	assert_bool(spawner.awake).is_false()
	assert_int(spawner.pool().made).is_equal(0)
	player.position = Vector3(0, 0, 6)
	await _ticks(40)
	assert_bool(spawner.awake).is_true()
	assert_object((spawner.alive[0].brain as AiBrain).leader).is_same(player)


func test_a_client_of_a_remote_server_spawns_nothing_and_a_server_only_when_asked() -> void:
	var tree := get_tree()
	assert_bool(AiSpawner.spawns_here(tree)).is_true()
	(
		assert_bool(
			AiSpawner.spawns_here(
				tree, true, NetArgs.new(PackedStringArray(["--connect", "ws://x"]))
			)
		)
		. is_false()
	)
	(
		assert_bool(
			AiSpawner.spawns_here(tree, false, NetArgs.new(PackedStringArray(["--server"])))
		)
		. is_false()
	)
	(
		assert_bool(AiSpawner.spawns_here(tree, true, NetArgs.new(PackedStringArray(["--server"]))))
		. is_true()
	)


func test_a_map_under_a_server_spawns_only_when_asked_and_beside_a_client_never() -> void:
	# One process holding a server's map and a client's (a test, a capture): decided by the map.
	var tree := get_tree()
	var server: NetServer = auto_free(NetServer.new())
	var server_map := Node3D.new()
	server.add_child(server_map)
	assert_bool(AiSpawner.spawns_here(tree, false, NetArgs.new(), server_map)).is_false()
	assert_bool(AiSpawner.spawns_here(tree, true, NetArgs.new(), server_map)).is_true()
	var arena: Node = auto_free(Node.new())
	var client_map := Node3D.new()
	arena.add_child(client_map)
	assert_bool(AiSpawner.spawns_here(tree, true, NetArgs.new(), client_map)).is_true()
	arena.add_child(NetClient.new())
	assert_bool(AiSpawner.spawns_here(tree, true, NetArgs.new(), client_map)).is_false()


func test_a_map_that_handed_its_ai_to_a_server_stops_spawning() -> void:
	var spawner := _spawner(GRUNT, {"respawn_delay": 0.5})
	await _ticks(2)
	assert_int(spawner.alive.size()).is_equal(2)
	AiAuthority.hand_over(_arena)
	await _ticks(TICKS)
	assert_int(get_tree().get_nodes_in_group(AiCharacter.GROUP).size()).is_equal(0)
	assert_int(spawner.spawned_total).is_equal(2)
	assert_bool(spawner.is_physics_processing()).is_false()
	assert_int(spawner.pool().parked()).is_equal(0)

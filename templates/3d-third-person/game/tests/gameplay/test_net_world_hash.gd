# The server and the client hash the map's networked parts from the map node (`world_root`, the
# `World` instance), so a client in the online arena (`World` beside its `NetClient`) and a server
# from `net_server.tscn` (`World` under the `NetServer`) agree on the same map, and a client whose
# part sits elsewhere is refused for it (issue #1058).
extends GdUnitTestSuite

## Where the test's part goes in the map, and where the other client's copy of it went.
const PART_PARENT := "Level"
const MOVED_PARENT := "."

var _rig: OnlineRig


func before_test() -> void:
	_rig = auto_free(OnlineRig.new())
	_rig.prepare_server = func(server: Node) -> void:
		_add_part(server.get_node("World"), PART_PARENT)
	add_child(_rig)
	assert_bool(_rig.start()).is_true()


func test_the_hash_is_the_same_whatever_holds_the_map() -> void:
	var map := (load("res://world/world.tscn") as PackedScene).instantiate()
	_add_part(map, PART_PARENT)
	var holder := Node.new()
	holder.add_child(map)
	assert_int(NetServer.world_hash_of(map)).is_equal(_rig.server.world_hash)
	assert_int(_rig.server.world_hash).is_not_equal(NetWire.world_hash(PackedStringArray()))
	holder.free()


func test_a_client_with_the_same_part_is_welcomed() -> void:
	_rig.prepare_arena = func(arena: Node) -> void: _add_part(arena.get_node("World"), PART_PARENT)
	var client := await _rig.join("Ada")
	assert_object(client).is_not_null()
	assert_int(client.welcome.world_hash).is_equal(_rig.server.world_hash)


func test_a_client_with_the_part_moved_is_refused_for_the_world() -> void:
	var reasons: Array[int] = []
	_rig.prepare_arena = func(arena: Node) -> void:
		_add_part(arena.get_node("World"), MOVED_PARENT)
		(arena.get_node("NetClient") as NetClient).refused.connect(reasons.append)
	var client := await _rig.join("Bo", 60)
	assert_object(client).is_null()
	assert_array(reasons).contains_exactly([NetWire.Refusal.WORLD])


static func _add_part(map: Node, parent_path: String) -> void:
	var part := Node3D.new()
	part.name = "TestDoor"
	part.set_meta(&"net_kind", "door")
	part.add_to_group(NetServer.PART_GROUP, true)
	map.get_node(parent_path).add_child(part)

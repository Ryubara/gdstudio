# A predicting client moves its body against its own copy of the map, the server against its own:
# a solid thing only one of them holds is a wall the other walks through
# (multiplayer.md#the-two-worlds-must-hold-the-same-solid-things). With a real client joined to a
# real server, every `CollisionObject3D` and colliding `CSGShape3D` under the client's view is in
# the server's at the same place, and the other way round. The bodies of players are compared by
# slot instead (the client draws others as puppets that meet nothing), and a thing that moves on
# its own clock (a `MovingPlatform`'s body, a prop) is matched by its path alone.
extends GdUnitTestSuite

## Metres two places of one static thing may differ by.
const PLACE_TOLERANCE := 0.001

var _rig: OnlineRig


func before_test() -> void:
	_rig = auto_free(OnlineRig.new())
	add_child(_rig)
	assert_bool(_rig.start()).is_true()


func test_every_solid_thing_is_in_both_worlds_at_the_same_place() -> void:
	var client := await _rig.join("Ada")
	assert_object(client).is_not_null()
	await _rig.wait(10)
	var ours := _solids(_rig.views[0])
	var theirs := _solids(_rig.server_view)
	var only_ours: Array[String] = []
	var only_theirs: Array[String] = []
	var moved: Array[String] = []
	for key: String in ours:
		if not theirs.has(key):
			only_ours.append(key)
		elif not ours[key]["moves"]:
			var gap: float = (ours[key]["at"] as Vector3).distance_to(theirs[key]["at"])
			if gap > PLACE_TOLERANCE:
				moved.append("%s (%.3f m)" % [key, gap])
	for key: String in theirs:
		if not ours.has(key):
			only_theirs.append(key)
	prints(
		"world parity:", ours.size(), "solid things on the client,", theirs.size(), "on the server"
	)
	assert_int(ours.size()).is_greater(50)
	assert_array(only_ours).override_failure_message("client only: %s" % [only_ours]).is_empty()
	assert_array(only_theirs).override_failure_message("server only: %s" % [only_theirs]).is_empty()
	assert_array(moved).override_failure_message("not at the same place: %s" % [moved]).is_empty()


func test_the_bodies_of_players_meet_nothing_but_the_world() -> void:
	var ada := await _rig.join("Ada")
	var bo := await _rig.join("Bo")
	await _rig.wait(10)
	var puppet := bo.remote_players.puppet_at(ada.slot)
	assert_int(puppet.collision_layer).is_equal(0)
	assert_int(puppet.collision_mask).is_equal(PhysicsLayers.WORLD)
	# The server's body and the client's own are on the Characters layer, which no body's mask
	# lists, so the server's bodies never block each other where the puppets would not.
	var server_body := _rig.server_body(ada)
	assert_int(server_body.collision_layer).is_equal(ada.player.collision_layer)
	assert_int(server_body.collision_mask).is_equal(ada.player.collision_mask)
	assert_int(server_body.collision_mask & PhysicsLayers.CHARACTERS).is_equal(0)


# Every solid thing under `view` outside a character, by its path under the map (`World`), with
# where it is and whether it moves on its own.
func _solids(view: Node) -> Dictionary[String, Dictionary]:
	var found: Dictionary[String, Dictionary] = {}
	for node in view.find_children("*", "Node3D", true, false):
		if not _is_solid(node) or _inside_character(node, view):
			continue
		var path := str(view.get_path_to(node))
		var cut := path.find("World/")
		var key := path.substr(cut) if cut >= 0 else path
		var body := node as PhysicsBody3D
		var moves := body != null and not (body is StaticBody3D and not body is AnimatableBody3D)
		found[key] = {"at": (node as Node3D).global_position, "moves": moves}
	return found


static func _is_solid(node: Node) -> bool:
	if node is CollisionObject3D:
		return true
	var csg := node as CSGShape3D
	return csg != null and csg.use_collision and csg.is_root_shape()


static func _inside_character(node: Node, view: Node) -> bool:
	var at := node
	while at != null and at != view:
		if at is Character:
			return true
		at = at.get_parent()
	return false

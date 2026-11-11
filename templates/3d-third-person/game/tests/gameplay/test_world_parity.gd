# A predicting client moves its body against its own copy of the map, the server against its own:
# a solid thing only one of them holds is a wall the other walks through
# (multiplayer.md#the-two-worlds-must-hold-the-same-solid-things). With a real client joined to a
# real server, every `CollisionObject3D` and colliding `CSGShape3D` under the client's view is in
# the server's at the same place, and the other way round. The bodies of players are compared by
# slot instead (the client draws others as puppets that meet nothing), and a thing that moves on
# its own clock (a `MovingPlatform`'s body, a prop) is matched by its path alone (`WorldParity`).
extends GdUnitTestSuite

var _rig: OnlineRig


func before_test() -> void:
	_rig = auto_free(OnlineRig.new())
	add_child(_rig)
	assert_bool(_rig.start()).is_true()


func test_every_solid_thing_is_in_both_worlds_at_the_same_place() -> void:
	var client := await _rig.join("Ada")
	assert_object(client).is_not_null()
	await _rig.wait(10)
	var parity := WorldParity.compare(_rig.views[0], _rig.server_view)
	prints(
		"world parity:",
		parity.ours_count,
		"solid things on the client,",
		parity.theirs_count,
		"on the server"
	)
	assert_int(parity.ours_count).is_greater(50)
	var only_ours := parity.only_ours
	var only_theirs := parity.only_theirs
	assert_array(only_ours).override_failure_message("client only: %s" % [only_ours]).is_empty()
	assert_array(only_theirs).override_failure_message("server only: %s" % [only_theirs]).is_empty()
	var moved := parity.moved
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

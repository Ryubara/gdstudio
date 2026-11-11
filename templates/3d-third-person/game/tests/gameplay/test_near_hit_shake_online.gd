# A hit near the player shakes the camera online too (gdstudio #1068): a game server and two
# clients in worlds of their own (`OnlineRig`, over the in-process link). A HIT event played by
# `ClientCombat` shakes the camera of the screen it lands beside, only that one, even where the
# screen finds no surface at the point; one 20 m away shakes nothing. Nothing about it is sent.
extends GdUnitTestSuite

const NEAR_HIT := "res://core/camera_shake/presets/near_hit.tres"


func before_test() -> void:
	CameraShake.strength = 1.0


func test_a_hit_event_online_shakes_only_the_screen_it_lands_beside() -> void:
	var online: OnlineRig = auto_free(OnlineRig.new(true))
	add_child(online)
	assert_bool(online.start()).is_true()
	var ada := await online.join("Ada", 600)
	var bo := await online.join("Bo", 600)
	assert_object(ada).is_not_null()
	assert_object(bo).is_not_null()
	await online.wait(10)
	var ada_rig := ada.player.get_parent().get_node("PlayerCamera") as PlayerCamera
	var bo_rig := bo.player.get_parent().get_node("PlayerCamera") as PlayerCamera
	var preset := load(NEAR_HIT) as ShakePreset
	ada_rig.shaker.clear()
	bo_rig.shaker.clear()
	var camera := ada_rig.get_viewport().get_camera_3d()
	var near := camera.global_position - camera.global_basis.z * 2.0
	# A HIT on the open ground of the map, as the server sends it: Ada's screen finds the floor.
	var found: Array[Object] = []
	ada.combat.hit_played.connect(
		func(_e: NetEvent, collider: Object) -> void: found.append(collider)
	)
	var floor_hit := NetEvent.hit(Vector3(near.x, 0.0, near.z), Vector3.UP, NetHits.Kind.WORLD)
	ada.combat.play(floor_hit)
	assert_object(found[0]).is_not_null()
	assert_float(ada_rig.shaker.trauma_of(preset)).is_greater(0.2)
	# The other screen is in a world of its own: its camera felt nothing.
	assert_float(bo_rig.shaker.trauma_of(preset)).is_equal(0.0)
	ada_rig.shaker.clear()
	# A HIT where this screen finds no surface (in the air beside the camera) still shakes it.
	ada.combat.play(NetEvent.hit(near + Vector3.UP * 0.5, Vector3.UP, NetHits.Kind.WORLD))
	assert_object(found[1]).is_null()
	assert_float(ada_rig.shaker.trauma_of(preset)).is_greater(0.2)
	ada_rig.shaker.clear()
	# 20 m away: nothing.
	var far := camera.global_position - camera.global_basis.z * 20.0
	ada.combat.play(NetEvent.hit(far, Vector3.UP, NetHits.Kind.WORLD))
	assert_float(ada_rig.shaker.trauma_of(preset)).is_equal(0.0)
	# The server has no camera and no near-hit shake.
	var on_server := online.server_view.find_children("*", "", true, false).filter(
		func(node: Node) -> bool: return node is NearHitShake
	)
	assert_array(on_server).is_empty()

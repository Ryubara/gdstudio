# A camera zone hands the view to another Phantom Camera by priority while the player is inside,
# and back.
extends GdUnitTestSuite

var _runner: GdUnitSceneRunner
var _scene: Node
var _player: Player
var _host: PhantomCameraHost
var _follow: PhantomCamera3D
var _overlook: PhantomCamera3D


func before_test() -> void:
	_runner = scene_runner("res://main.tscn")
	_scene = _runner.scene()
	_player = _scene.get_node("PlayerRig/Player")
	_host = _scene.get_node("PlayerRig/Camera/PhantomCameraHost")
	_follow = _scene.get_node("PlayerRig/PlayerCamera").phantom_camera()
	_overlook = _scene.get_node("World/Level/CameraViews/OverlookCamera")
	# The AI section's population stays asleep: its pool, made as the player comes near, is out of
	# the tree, and GdUnit counts a parked character as an orphan node before `after_test` runs.
	for spawner: AiSpawner in _scene.get_node("World/AISection/Population").get_children():
		spawner.enabled = false
	await InputSim.ticks(get_tree(), 12)


func test_the_follow_camera_has_the_view_until_the_player_enters_the_zone() -> void:
	assert_object(_host.get_active_pcam()).is_same(_follow)
	assert_int(_overlook.priority).is_less(_follow.priority)


func test_entering_the_zone_hands_the_view_over_and_leaving_hands_it_back() -> void:
	var views := []
	_scene.get_node("World/Level/CameraViews/CameraZone").view_changed.connect(
		func(zone_view: bool) -> void: views.append(zone_view)
	)
	_player.teleport(Vector3(-18.0, 0.1, 11.5))
	await InputSim.ticks(get_tree(), 6)
	assert_object(_host.get_active_pcam()).is_same(_overlook)
	assert_int(_overlook.priority).is_greater(_follow.priority)
	# The view blends there over the camera tween (1.2 s), it does not cut.
	await InputSim.ticks(get_tree(), 100)
	var camera: Camera3D = _scene.get_node("PlayerRig/Camera")
	assert_vector(camera.global_position).is_equal_approx(
		_overlook.global_position, Vector3.ONE * 0.2
	)
	_player.teleport(Vector3(0.0, 1.0, 0.0))
	await InputSim.ticks(get_tree(), 6)
	assert_object(_host.get_active_pcam()).is_same(_follow)
	assert_array(views).is_equal([true, false])


func test_a_box_that_is_not_the_player_does_not_take_the_view() -> void:
	var crate := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	crate.add_child(shape)
	# On the Props layer, which the zone senses: the group test is what keeps it out.
	crate.collision_layer = PhysicsLayers.PROPS
	crate.position = Vector3(-18.0, 0.6, 11.5)
	_scene.add_child(crate)
	await InputSim.ticks(get_tree(), 10)
	assert_object(_host.get_active_pcam()).is_same(_follow)
	crate.queue_free()

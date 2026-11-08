# Smoke test: the main scene loads, shows the level through the Phantom Camera host's camera and
# runs a few frames.
extends GdUnitTestSuite


func test_main_scene_shows_the_prototype_level_through_a_current_camera() -> void:
	var runner := scene_runner("res://main.tscn")
	await await_idle_frame()
	var scene := runner.scene()
	assert_object(scene.get_node_or_null("Level")).is_not_null()
	var camera := scene.get_viewport().get_camera_3d()
	assert_object(camera).is_not_null()
	assert_bool(camera.current).is_true()


func test_the_view_camera_is_a_phantom_camera_the_host_follows() -> void:
	var runner := scene_runner("res://main.tscn")
	for _frame in 8:
		await await_idle_frame()
	var scene := runner.scene()
	var host: PhantomCameraHost = scene.get_node("Camera/PhantomCameraHost")
	var view: PhantomCamera3D = scene.get_node("ViewCamera")
	assert_bool(view.is_active()).is_true()
	assert_object(host.get_active_pcam()).is_same(view)
	var camera: Camera3D = scene.get_node("Camera")
	# It does not tween in from the origin when the game starts (`tween_on_load` is off).
	assert_vector(camera.global_position).is_equal_approx(view.global_position, Vector3.ONE * 0.05)


func test_the_main_scene_is_the_one_the_project_runs() -> void:
	assert_str(ProjectSettings.get_setting("application/run/main_scene")).is_equal(
		"res://main.tscn"
	)
	assert_bool(ResourceLoader.exists("res://main.tscn")).is_true()

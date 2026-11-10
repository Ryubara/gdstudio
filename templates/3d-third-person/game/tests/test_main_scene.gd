# Smoke test: the main scene loads, the player stands in the level and the Phantom Camera host
# shows it through the follow camera.
extends GdUnitTestSuite


func test_main_scene_shows_the_level_and_the_player_through_a_current_camera() -> void:
	var runner := scene_runner("res://main.tscn")
	await await_idle_frame()
	var scene := runner.scene()
	assert_object(scene.get_node_or_null("Level")).is_not_null()
	assert_object(scene.get_node_or_null("Player")).is_not_null()
	var camera := scene.get_viewport().get_camera_3d()
	assert_object(camera).is_not_null()
	assert_bool(camera.current).is_true()


func test_the_follow_camera_is_the_phantom_camera_the_host_shows() -> void:
	var runner := scene_runner("res://main.tscn")
	await await_idle_frame()
	await await_idle_frame()
	var scene := runner.scene()
	var host: PhantomCameraHost = scene.get_node("Camera/PhantomCameraHost")
	var follow: PhantomCamera3D = scene.get_node("PlayerCamera").phantom_camera()
	assert_bool(follow.is_active()).is_true()
	assert_object(host.get_active_pcam()).is_same(follow)
	assert_int(follow.follow_mode).is_equal(PhantomCamera3D.FollowMode.THIRD_PERSON)
	assert_object(follow.follow_target).is_same(scene.get_node("Player/CameraTarget"))


func test_the_project_starts_at_the_menu_scene_and_the_game_scene_is_main() -> void:
	assert_str(ProjectSettings.get_setting("application/run/main_scene")).is_equal(
		"res://ui/menus/menu_scene.tscn"
	)
	assert_bool(ResourceLoader.exists("res://ui/menus/menu_scene.tscn")).is_true()
	assert_bool(ResourceLoader.exists("res://main.tscn")).is_true()

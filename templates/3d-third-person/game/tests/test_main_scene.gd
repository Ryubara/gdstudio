# Smoke test: the main scene loads, the player stands in the level and the Phantom Camera host
# shows it through the follow camera.
extends GdUnitTestSuite


func test_main_scene_shows_the_level_and_the_player_through_a_current_camera() -> void:
	var runner := scene_runner("res://main.tscn")
	await await_idle_frame()
	var scene := runner.scene()
	assert_object(scene.get_node_or_null("World/Level")).is_not_null()
	assert_object(scene.get_node_or_null("PlayerRig/Player")).is_not_null()
	var camera := scene.get_viewport().get_camera_3d()
	assert_object(camera).is_not_null()
	assert_bool(camera.current).is_true()


func test_the_follow_camera_is_the_phantom_camera_the_host_shows() -> void:
	var runner := scene_runner("res://main.tscn")
	await await_idle_frame()
	await await_idle_frame()
	var scene := runner.scene()
	var host: PhantomCameraHost = scene.get_node("PlayerRig/Camera/PhantomCameraHost")
	var follow: PhantomCamera3D = scene.get_node("PlayerRig/PlayerCamera").phantom_camera()
	assert_bool(follow.is_active()).is_true()
	assert_object(host.get_active_pcam()).is_same(follow)
	assert_int(follow.follow_mode).is_equal(PhantomCamera3D.FollowMode.THIRD_PERSON)
	assert_object(follow.follow_target).is_same(scene.get_node("PlayerRig/Player/CameraTarget"))


func test_the_project_starts_at_the_menu_scene_and_the_game_scene_is_main() -> void:
	assert_str(ProjectSettings.get_setting("application/run/main_scene")).is_equal(
		"res://ui/menus/menu_scene.tscn"
	)
	assert_bool(ResourceLoader.exists("res://ui/menus/menu_scene.tscn")).is_true()
	assert_bool(ResourceLoader.exists("res://main.tscn")).is_true()


# `main.tscn` stays a list of instances and the wires between them, so a feature that adds a node
# edits its own scene and never this one (a node here is a merge conflict for the next feature).
func test_main_holds_only_scene_instances_and_wires() -> void:
	var state := (load("res://main.tscn") as PackedScene).get_state()
	assert_int(state.get_node_property_count(0)).is_equal(0)
	var instances := {}
	for index in range(1, state.get_node_count()):
		var instance := state.get_node_instance(index)
		assert_object(instance).is_not_null()
		assert_str(String(state.get_node_path(index, true))).is_equal(".")
		instances[String(state.get_node_name(index))] = instance.resource_path
	(
		assert_dict(instances)
		. is_equal(
			{
				"World": "res://world/world.tscn",
				"PlayerRig": "res://ui/player_rig/player_rig.tscn",
				"Hud": "res://ui/hud/hud.tscn",
				"Screens": "res://ui/menus/screen_host.tscn",
			}
		)
	)


func test_the_wires_between_the_instances_reach_across_them() -> void:
	var runner := scene_runner("res://main.tscn")
	await await_idle_frame()
	var scene := runner.scene()
	var player := scene.get_node("PlayerRig/Player")
	var hud: Hud = scene.get_node("Hud")
	assert_object(hud.player).is_same(player)
	assert_object(hud.touch_controls).is_same(scene.get_node("PlayerRig/TouchControls"))
	for widget in hud.widgets():
		assert_object(widget.bound_to()).is_same(player)
	var touch: TouchControls = scene.get_node("PlayerRig/TouchControls")
	var host: ScreenHost = scene.get_node("Screens")
	assert_bool(host.opened.is_connected(touch.suspend)).is_true()
	assert_bool(host.closed.is_connected(touch.resume)).is_true()

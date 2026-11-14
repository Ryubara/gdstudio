# The options after the engine's `--`, and the server's way in: `--server` takes the main scene to
# the server scene before any menu shows, and the server scene holds the map and a `NetServer`
# that holds its frame rate to the tick.
extends GdUnitTestSuite


func test_the_options_are_read_in_both_spellings() -> void:
	var args := NetArgs.new(
		PackedStringArray(["--server", "--port", "9001", "--name=Ada Lovelace", "stray", "--bot"])
	)
	assert_bool(args.is_server()).is_true()
	assert_int(args.port(1)).is_equal(9001)
	assert_str(args.get_string("name")).is_equal("Ada Lovelace")
	assert_bool(args.has("bot")).is_true()
	assert_str(args.get_string("bot")).is_equal("true")
	assert_bool(args.has("stray")).is_false()


func test_a_port_that_is_not_a_number_falls_back() -> void:
	var args := NetArgs.new(PackedStringArray(["--port", "--server"]))
	assert_str(args.get_string("port")).is_equal("true")
	assert_int(args.get_int("port", 7)).is_equal(7)
	var none := NetArgs.new(PackedStringArray())
	assert_bool(none.is_server()).is_false()
	var from_env := OS.get_environment("PORT")
	var expected := int(from_env) if from_env.is_valid_int() else 8910
	assert_int(none.port(8910)).is_equal(expected)


func test_server_goes_to_the_server_scene_before_any_menu() -> void:
	var scene := MenuScene.new()
	scene.main_menu = load("res://ui/menus/main_menu.tscn")
	scene.net_args = NetArgs.new(PackedStringArray(["--server"]))
	var went: Array[String] = []
	scene.scene_changer = func(path: String) -> void: went.append(path)
	add_child(scene)
	assert_array(went).is_equal(["res://gameplay/net/net_server.tscn"])
	assert_int(UIRouter.depth()).is_zero()
	scene.free()


func test_an_address_goes_to_the_online_game() -> void:
	for args: Array in [["--connect", "ws://127.0.0.1:8910"], ["--url=wss://play.example.org"]]:
		var scene := MenuScene.new()
		scene.net_args = NetArgs.new(PackedStringArray(args))
		var went: Array[String] = []
		scene.scene_changer = func(path: String) -> void: went.append(path)
		add_child(scene)
		assert_array(went).is_equal(["res://online_main.tscn"])
		scene.free()


func test_the_bad_network_probe_page_keeps_its_own_client() -> void:
	var scene := MenuScene.new()
	scene.net_args = NetArgs.new(PackedStringArray(["--netplay", "--url", "ws://127.0.0.1:1"]))
	assert_bool(scene.wants_online(scene.net_args)).is_false()
	assert_bool(scene.wants_online(NetArgs.new(PackedStringArray(["--name", "Ada"])))).is_false()
	scene.free()


func test_the_server_scene_holds_the_map_and_caps_the_frame_rate() -> void:
	var packed := load("res://gameplay/net/net_server.tscn") as PackedScene
	var server := packed.instantiate() as NetServer
	assert_bool(server.cap_frame_rate).is_true()
	assert_object(server.get_node_or_null("World/Level")).is_not_null()
	assert_object(server.players_root).is_equal(server.get_node("Players"))
	assert_int(server.port).is_equal(-1)
	assert_str(server.body_scene.resource_path).is_equal("res://gameplay/character/character.tscn")
	server.free()


func test_the_server_exports_are_pinned() -> void:
	var server := auto_free(NetServer.new()) as NetServer
	var pins := {
		&"port": -1,
		&"bind_address": "*",
		&"max_players": NetLimits.MAX_PLAYERS,
		&"cap_frame_rate": false,
		&"print_log": true,
		&"world_root": null,
		&"body_scene": load("res://gameplay/character/character.tscn"),
		&"body_items": load("res://gameplay/net/body_items.tscn"),
		&"players_root": null,
		&"spawn_group": &"player",
		&"spawn_seed": 1,
		&"command_ticks": 30,
		&"hold_ticks": 4,
		&"silent_seconds": 15.0,
		&"hello_seconds": 10.0,
		&"origin_slack": 4.0,
		&"revive_seconds": 3.0,
		&"revive_at_spawn": false,
		&"ai_rewind_seconds": 0.6,
		&"ai_rewind_flight_seconds": 0.5,
		&"entity_lead_ticks": 12,
		&"ai_rates": load("res://gameplay/net/ai_tier_rates.tres"),
		&"ai_section_origin": Vector3.ZERO,
		&"ai_variants":
		[
			load("res://gameplay/ai/profiles/grunt.tres"),
			load("res://gameplay/ai/profiles/ally.tres"),
			load("res://gameplay/ai/profiles/civilian.tres"),
			load("res://gameplay/ai/profiles/shooter.tres"),
		],
		&"ai_sees_players": true,
	}
	assert_array(ExportPins.differences(server, pins)).is_empty()
	assert_array(ExportPins.wrong_values(server, pins)).is_empty()

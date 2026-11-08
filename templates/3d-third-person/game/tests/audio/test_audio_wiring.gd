# The sounds the template ships are played by something: the wind by the main scene, the coin by
# the pickup, the steps by the footsteps. Every sound player sits on one of the template's buses
# and every sound file in `assets/audio/` is used by a scene.
extends GdUnitTestSuite

const BUSES: Array[StringName] = [&"SFX", &"Ambient", &"UI"]

var _scene: Node


func before_test() -> void:
	_scene = scene_runner("res://main.tscn").scene()
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	AudioDrain.stop_all(_scene)


func _players() -> Array[Node]:
	var found: Array[Node] = []
	found.append_array(_scene.find_children("*", "AudioStreamPlayer", true, false))
	found.append_array(_scene.find_children("*", "AudioStreamPlayer3D", true, false))
	return found


func test_the_wind_plays_from_the_start_as_a_loop_on_the_ambient_bus() -> void:
	var wind := _scene.get_node("Wind") as AudioStreamPlayer
	assert_bool(wind.autoplay).is_true()
	assert_bool(wind.playing).is_true()
	assert_str(String(wind.bus)).is_equal("Ambient")
	assert_str(wind.stream.resource_path).is_equal("res://assets/audio/wind/wind_soft_1.ogg")
	assert_bool((wind.stream as AudioStreamOggVorbis).loop).is_true()


func test_every_sound_player_is_on_a_bus_of_the_template_never_on_master() -> void:
	var players := _players()
	assert_int(players.size()).is_greater(8)
	for player in players:
		var bus: StringName = player.get("bus")
		(
			assert_bool(BUSES.has(bus))
			. override_failure_message("%s is on %s" % [_scene.get_path_to(player), bus])
			. is_true()
		)
		assert_int(AudioServer.get_bus_index(bus)).is_greater_equal(0)


func test_steps_and_coins_are_on_sfx_and_the_wind_alone_is_ambient() -> void:
	var ambient := 0
	for player in _players():
		if player.get("bus") == &"Ambient":
			ambient += 1
		else:
			assert_str(String(player.get("bus"))).is_equal("SFX")
	assert_int(ambient).is_equal(1)


func test_every_sound_file_is_used_by_a_scene() -> void:
	var text := ""
	for path in [
		"res://main.tscn",
		"res://gameplay/pickup/pickup.tscn",
		"res://gameplay/player/footsteps.tscn",
	]:
		text += FileAccess.get_file_as_string(path)
	for folder in ["coin", "footsteps", "wind"]:
		var dir := DirAccess.open("res://assets/audio/%s" % folder)
		assert_object(dir).is_not_null()
		for file in dir.get_files():
			if file.ends_with(".ogg"):
				(
					assert_bool(text.contains("assets/audio/%s/%s" % [folder, file]))
					. override_failure_message("%s/%s plays nowhere" % [folder, file])
					. is_true()
				)


func test_the_weapon_has_a_slot_for_a_shot_sound_that_is_empty_until_a_game_adds_one() -> void:
	var weapon := _scene.get_node("Player/Weapon") as Weapon
	var sound := weapon.get_node("%ShotSound") as AudioStreamPlayer3D
	assert_object(sound.stream).is_null()
	assert_str(String(sound.bus)).is_equal("SFX")
	# With a stream in the slot a shot plays it at the muzzle.
	sound.stream = load("res://assets/audio/coin/coin_pickup_1.ogg")
	weapon.fire()
	assert_bool(sound.playing).is_true()
	assert_vector(sound.global_position).is_equal_approx(
		weapon.muzzle.global_position, Vector3.ONE * 0.5
	)

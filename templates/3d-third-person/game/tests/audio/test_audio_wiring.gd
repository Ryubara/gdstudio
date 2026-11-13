# The sounds the template ships are played by something: the wind by the main scene, the coin by
# the pickup, the steps by the footsteps, the shot by the weapon. Every sound player sits on one of
# the template's buses, has a stream (or is given one when it plays), and every sound file in
# `assets/audio/` is used by a scene. The levels the maintainer tuned and the ones measured against
# them are pinned here, with the shot's voices.
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
	var wind := _scene.get_node("World/Wind") as AudioStreamPlayer
	assert_bool(wind.autoplay).is_true()
	assert_bool(wind.playing).is_true()
	assert_str(String(wind.bus)).is_equal("Ambient")
	assert_str(wind.stream.resource_path).is_equal("res://assets/audio/wind/wind_soft_1.ogg")
	assert_bool((wind.stream as AudioStreamOggVorbis).loop).is_true()


func test_the_wind_is_20_db_down_in_a_player_of_its_own() -> void:
	# A game's own wind is another file in this one player: the level and the bus stay.
	var wind := _scene.get_node("World/Wind") as AudioStreamPlayer
	assert_float(wind.volume_db).is_equal(-20.0)


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
		"res://world/world.tscn",
		"res://gameplay/pickup/pickup.tscn",
		"res://gameplay/character/footsteps.tscn",
		"res://gameplay/weapon/weapon.tscn",
		"res://gameplay/weapon/pistol.tres",
		"res://gameplay/weapon/fists.tres",
		"res://gameplay/weapon/categories/unarmed.tres",
		"res://gameplay/weapon/categories/pistol.tres",
		"res://gameplay/weapon/categories/rifle.tres",
		"res://gameplay/inventory/bandage_use.tres",
	]:
		text += FileAccess.get_file_as_string(path)
	for folder in ["coin", "footsteps", "pistol", "fists", "wind", "bandage"]:
		var dir := DirAccess.open("res://assets/audio/%s" % folder)
		assert_object(dir).is_not_null()
		for file in dir.get_files():
			if file.ends_with(".ogg"):
				(
					assert_bool(text.contains("assets/audio/%s/%s" % [folder, file]))
					. override_failure_message("%s/%s plays nowhere" % [folder, file])
					. is_true()
				)


# A player with no stream is as silent as no player: every one has a stream, or is the one that is
# given its stream when it plays (a step from the footsteps' files, a coin from the pickup's).
func test_every_sound_player_has_a_stream_or_is_given_one_when_it_plays() -> void:
	for player in _players():
		if player.get("stream") != null:
			continue
		var parent := player.get_parent()
		var files = parent.get("steps") if parent.get("steps") != null else parent.get("sounds")
		if parent is Weapon and player.name == &"ReloadSound":
			# The weapon gives it each step of its definition's reload as the reload reaches it.
			files = (parent as Weapon).definition.reload_sounds
		(
			assert_bool(files is Array and not files.is_empty())
			. override_failure_message(
				"%s has no stream and nothing gives it one" % _scene.get_path_to(player)
			)
			. is_true()
		)


func test_the_shot_is_five_pistol_files_with_a_small_pitch_spread_and_three_voices() -> void:
	var weapon := _scene.get_node("PlayerRig/Player/Weapon") as Weapon
	var sound := weapon.get_node("%ShotSound") as AudioStreamPlayer3D
	var randomizer := weapon.definition.shot_sound as AudioStreamRandomizer
	assert_object(randomizer).is_not_null()
	assert_int(randomizer.streams_count).is_equal(5)
	for n in 5:
		var path := randomizer.get_stream(n).resource_path
		assert_str(path).is_equal("res://assets/audio/pistol/pistol_shot_%d.ogg" % (n + 1))
	# A little spread keeps a pistol a pistol: under a semitone either way.
	assert_float(randomizer.random_pitch).is_between(1.01, 1.06)
	assert_float(randomizer.random_volume_offset_db).is_between(0.5, 2.0)
	assert_int(sound.max_polyphony).is_equal(3)
	assert_str(String(sound.bus)).is_equal("SFX")


# The players hold the takes decoded once (`DecodedSounds`): starting an Ogg Vorbis take set its
# decoder up, about 250 µs a shot on the desktop and 300 to 400 in a browser; a decoded one about 1.
func test_the_weapon_plays_its_sounds_decoded_with_the_definitions_spread() -> void:
	var weapon := _scene.get_node("PlayerRig/Player/Weapon") as Weapon
	var shot := weapon.get_node("%ShotSound").stream as AudioStreamRandomizer
	var written := weapon.definition.shot_sound as AudioStreamRandomizer
	assert_object(shot).is_same(DecodedSounds.decoded(written))
	assert_int(shot.streams_count).is_equal(written.streams_count)
	assert_float(shot.random_pitch).is_equal_approx(written.random_pitch, 0.0001)
	for n in shot.streams_count:
		assert_object(shot.get_stream(n)).is_instanceof(AudioStreamWAV)
	var empty := weapon.get_node("%EmptySound").stream as AudioStreamRandomizer
	for n in empty.streams_count:
		assert_object(empty.get_stream(n)).is_instanceof(AudioStreamWAV)
	assert_object(weapon.get_node("%DrawSound").stream).is_instanceof(AudioStreamWAV)


func test_a_shot_plays_at_the_muzzle() -> void:
	var weapon := _scene.get_node("PlayerRig/Player/Weapon") as Weapon
	var sound := weapon.get_node("%ShotSound") as AudioStreamPlayer3D
	weapon.fire()
	assert_bool(sound.playing).is_true()
	assert_vector(sound.global_position).is_equal_approx(
		weapon.muzzle.global_position, Vector3.ONE * 0.5
	)


# The levels. Step -20, crouch step -29, landing -15 and the wind -20 dB are the maintainer's own,
# set by ear in a game made from the template. The coin and the shot were levelled against them by
# measuring each through the camera, the buses and the 3D players (the loudest 400 ms at the mix:
# step -40, crouch step -46, landing -37, coin -37, shot -31, the wind -50 LUFS integrated). A
# 3D player's volume is not one to one with what is heard (it also darkens the sound as it falls),
# so change a number by measuring again, never by adding dB.
func test_the_levels_are_the_ones_measured_and_no_effect_jumps_out() -> void:
	var pickup := (load("res://gameplay/pickup/pickup.tscn") as PackedScene).instantiate()
	auto_free(pickup)
	var levels := {
		"Wind": [_scene.get_node("World/Wind"), -20.0],
		"Step": [_scene.get_node("PlayerRig/Player/Footsteps").get_node("%Step"), -20.0],
		"CrouchStep":
		[_scene.get_node("PlayerRig/Player/Footsteps").get_node("%CrouchStep"), -29.0],
		"LandStep": [_scene.get_node("PlayerRig/Player/Footsteps").get_node("%LandStep"), -15.0],
		"Coin": [pickup.get_node("%Sound"), -16.0],
		"Shot": [_scene.get_node("PlayerRig/Player/Weapon").get_node("%ShotSound"), -22.5],
	}
	for label in levels:
		var pair: Array = levels[label]
		(
			assert_float((pair[0] as Node).get("volume_db"))
			. override_failure_message(
				"%s is at %s dB" % [label, (pair[0] as Node).get("volume_db")]
			)
			. is_equal(pair[1])
		)

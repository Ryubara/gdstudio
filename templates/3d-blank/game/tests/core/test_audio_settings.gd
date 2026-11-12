# The bus layout and the AudioSettings node: a volume set in the inspector reaches AudioServer at
# once, and the wind the base ships is a seamless loop the Ambient bus plays.
extends GdUnitTestSuite

const BUSES: Array[StringName] = [&"Master", &"SFX", &"Ambient", &"UI"]

var _saved: Dictionary = {}


func before_test() -> void:
	for bus in BUSES:
		_saved[bus] = AudioSettings.bus_volume_db(bus)


func after_test() -> void:
	AudioSettings.reset_player_gain()
	for bus in BUSES:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), _saved[bus])
		AudioServer.set_bus_mute(AudioServer.get_bus_index(bus), false)


func test_the_project_has_the_four_buses_and_the_three_send_to_master() -> void:
	for bus in BUSES:
		assert_int(AudioServer.get_bus_index(bus)).is_greater_equal(0)
	for bus in [&"SFX", &"Ambient", &"UI"]:
		var index := AudioServer.get_bus_index(bus)
		assert_str(str(AudioServer.get_bus_send(index))).is_equal("Master")


func test_a_volume_set_on_the_node_reaches_the_audio_server_at_once() -> void:
	var settings: AudioSettings = auto_free(AudioSettings.new())
	settings.sfx_db = -12.0
	settings.ambient_db = -7.5
	settings.ui_db = -20.0
	settings.master_db = -1.0
	assert_float(AudioSettings.bus_volume_db(&"SFX")).is_equal_approx(-12.0, 0.001)
	assert_float(AudioSettings.bus_volume_db(&"Ambient")).is_equal_approx(-7.5, 0.001)
	assert_float(AudioSettings.bus_volume_db(&"UI")).is_equal_approx(-20.0, 0.001)
	assert_float(AudioSettings.bus_volume_db(&"Master")).is_equal_approx(-1.0, 0.001)


func test_the_defaults_in_the_layout_and_on_the_node_agree() -> void:
	var settings: AudioSettings = auto_free(AudioSettings.new())
	var layout: AudioBusLayout = load("res://default_bus_layout.tres")
	var volumes := {&"SFX": settings.sfx_db, &"Ambient": settings.ambient_db, &"UI": settings.ui_db}
	for index in range(1, 4):
		var bus_name := StringName(layout.get("bus/%d/name" % index))
		assert_float(float(layout.get("bus/%d/volume_db" % index))).is_equal_approx(
			volumes[bus_name], 0.001
		)


func test_the_main_scene_applies_the_node_when_it_starts() -> void:
	var runner := scene_runner("res://main.tscn")
	await await_idle_frame()
	var settings: AudioSettings = runner.scene().find_child("AudioSettings", true, false)
	settings.ui_db = -9.0
	assert_float(AudioSettings.bus_volume_db(&"UI")).is_equal_approx(-9.0, 0.001)


func test_a_bus_the_project_lacks_is_skipped_and_the_others_still_apply() -> void:
	assert_bool(is_nan(AudioSettings.bus_volume_db(&"Nope"))).is_true()
	var settings: AudioSettings = auto_free(AudioSettings.new())
	settings.apply_all()
	assert_float(AudioSettings.bus_volume_db(&"SFX")).is_equal_approx(settings.sfx_db, 0.001)


func _wind() -> AudioStreamOggVorbis:
	return load("res://assets/audio/wind/wind_soft_1.ogg")


## Long enough that its gusts are not heard repeating (kit sound-effects.md#wind).
func test_the_wind_is_a_seamless_loop_between_twenty_and_sixty_seconds() -> void:
	var wind := _wind()
	assert_object(wind).is_not_null()
	assert_float(wind.get_length()).is_between(20.0, 60.0)
	assert_bool(wind.loop).is_true()


func test_leaving_the_tree_stops_the_voices_and_waits_for_the_audio_thread() -> void:
	var holder: Node = auto_free(Node.new())
	var player := AudioStreamPlayer.new()
	player.stream = _wind()
	player.bus = &"Ambient"
	holder.add_child(player)
	var settings := AudioSettings.new()
	holder.add_child(settings)
	add_child(holder)
	player.play()
	assert_bool(player.playing).is_true()
	holder.remove_child(settings)
	settings.free()
	assert_bool(player.playing).is_false()
	AudioSettings.stop_players(holder)
	assert_bool(AudioSettings.drain_mixer()).is_true()


func test_the_players_volume_sits_on_top_of_the_mix_and_a_new_mix_keeps_it() -> void:
	var settings: AudioSettings = auto_free(AudioSettings.new())
	settings.sfx_db = -6.0
	AudioSettings.set_player_gain(&"SFX", 0.5)
	assert_float(AudioSettings.bus_volume_db(&"SFX")).is_equal_approx(
		-6.0 + linear_to_db(0.5), 0.01
	)
	settings.sfx_db = -10.0
	assert_float(AudioSettings.bus_volume_db(&"SFX")).is_equal_approx(
		-10.0 + linear_to_db(0.5), 0.01
	)
	assert_float(AudioSettings.player_gain(&"SFX")).is_equal(0.5)


func test_a_player_volume_of_zero_mutes_the_bus_and_one_unmutes_it() -> void:
	AudioSettings.set_player_gain(&"Ambient", 0.0)
	assert_bool(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Ambient"))).is_true()
	AudioSettings.set_player_gain(&"Ambient", 1.0)
	assert_bool(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Ambient"))).is_false()
	assert_float(AudioSettings.bus_volume_db(&"Ambient")).is_equal_approx(_saved[&"Ambient"], 0.01)


func test_a_gain_set_before_any_node_exists_starts_from_the_layouts_volume() -> void:
	AudioSettings.set_player_gain(&"UI", 0.5)
	assert_float(AudioSettings.bus_volume_db(&"UI")).is_equal_approx(
		_saved[&"UI"] + linear_to_db(0.5), 0.01
	)
	AudioSettings.reset_player_gain()
	assert_float(AudioSettings.bus_volume_db(&"UI")).is_equal_approx(_saved[&"UI"], 0.01)


func test_a_bus_the_project_lacks_takes_a_gain_without_error() -> void:
	AudioSettings.set_player_gain(&"Nope", 0.3)
	assert_float(AudioSettings.player_gain(&"Nope")).is_equal_approx(0.3, 0.0001)


func test_a_movie_capture_ends_at_its_quit_after_frame_and_nothing_else_does() -> void:
	var movie := "C:/captures/f.png"
	assert_int(AudioSettings.movie_quit_frame(["--quit-after", "1200"], movie)).is_equal(1200)
	assert_int(AudioSettings.movie_quit_frame(["--quit-after=90", "--verbose"], movie)).is_equal(90)
	assert_int(AudioSettings.movie_quit_frame(["--quit-after", "1200"], "")).is_equal(-1)
	assert_int(AudioSettings.movie_quit_frame(["--fixed-fps", "30"], movie)).is_equal(-1)
	assert_int(AudioSettings.movie_quit_frame(["--quit-after"], movie)).is_equal(-1)
	assert_int(AudioSettings.movie_quit_frame(["--quit-after", "soon"], movie)).is_equal(-1)


func test_a_run_that_writes_no_movie_never_watches_the_frames() -> void:
	var settings: AudioSettings = auto_free(AudioSettings.new())
	add_child(settings)
	assert_bool(settings.is_processing()).is_false()


func test_silencing_for_the_quit_pauses_the_tree_and_stops_every_voice() -> void:
	var holder: Node = auto_free(Node.new())
	var player := AudioStreamPlayer.new()
	player.stream = _wind()
	holder.add_child(player)
	var settings := AudioSettings.new()
	holder.add_child(settings)
	add_child(holder)
	player.play()
	settings.silence_for_quit()
	var paused := get_tree().paused
	get_tree().paused = false
	assert_bool(paused).is_true()
	assert_bool(player.playing).is_false()
	AudioSettings.stop_players(holder)
	AudioSettings.drain_mixer()

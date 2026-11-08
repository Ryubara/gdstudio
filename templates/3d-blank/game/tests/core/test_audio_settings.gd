# The bus layout and the AudioSettings node: a volume set in the inspector reaches AudioServer at
# once, and the wind the base ships is a seamless loop the Ambient bus plays.
extends GdUnitTestSuite

const BUSES: Array[StringName] = [&"Master", &"SFX", &"Ambient", &"UI"]

var _saved: Dictionary = {}


func before_test() -> void:
	for bus in BUSES:
		_saved[bus] = AudioSettings.bus_volume_db(bus)


func after_test() -> void:
	for bus in BUSES:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), _saved[bus])


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
	var settings: AudioSettings = runner.scene().get_node("AudioSettings")
	settings.ui_db = -9.0
	assert_float(AudioSettings.bus_volume_db(&"UI")).is_equal_approx(-9.0, 0.001)


func test_a_bus_the_project_lacks_is_skipped_and_the_others_still_apply() -> void:
	assert_bool(is_nan(AudioSettings.bus_volume_db(&"Nope"))).is_true()
	var settings: AudioSettings = auto_free(AudioSettings.new())
	settings.apply_all()
	assert_float(AudioSettings.bus_volume_db(&"SFX")).is_equal_approx(settings.sfx_db, 0.001)


func test_the_wind_is_a_seamless_loop_between_ten_and_twelve_seconds() -> void:
	var wind: AudioStreamOggVorbis = load("res://assets/audio/wind/wind_soft_1.ogg")
	assert_object(wind).is_not_null()
	assert_float(wind.get_length()).is_between(10.0, 12.0)
	assert_bool(wind.loop).is_true()

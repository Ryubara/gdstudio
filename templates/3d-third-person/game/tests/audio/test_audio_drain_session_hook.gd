# The run-wide audio drain (gdstudio #1506): a menu sound still playing when GdUnit quits was held
# by the audio thread at exit (`10 ObjectDB instances were leaked`, every case green), from
# whichever suite ran last. The session hook stops every voice and waits on the mixer after the
# last suite; these tests pin that it is registered and that it lets go of a voice that plays.
extends GdUnitTestSuite

const HOOK_PATH := "res://tests/fixtures/audio_drain_session_hook.gd"
const HOOKS_SETTING := "gdunit4/hooks/session_hooks"
## The frames after the hook's drain that the voice may take to go.
const RELEASE_FRAMES := 4


func test_the_hook_is_registered_and_enabled() -> void:
	assert_bool(ProjectSettings.has_setting(HOOKS_SETTING)).is_true()
	var hooks: Dictionary = ProjectSettings.get_setting(HOOKS_SETTING, {})
	assert_bool(hooks.get(HOOK_PATH, false)).is_true()


func test_the_hook_lets_go_of_a_playing_voice() -> void:
	var player: AudioStreamPlayer = auto_free(AudioStreamPlayer.new())
	player.stream = _tone()
	add_child(player)
	player.play()
	await get_tree().process_frame
	await get_tree().process_frame
	# Mixed once: a voice that was never mixed is let go of at once and proves nothing.
	AudioSettings.drain_mixer()
	assert_bool(player.playing).is_true()
	var playback: WeakRef = weakref(player.get_stream_playback())
	# Asked as a bool: an assert keeps the value it was given, which would hold the voice itself.
	assert_bool(playback.get_ref() != null).is_true()
	var hook: GdUnitTestSessionHook = load(HOOK_PATH).new()
	var result: GdUnitResult = await hook.shutdown(null)
	assert_bool(result.is_success()).is_true()
	for _frame in RELEASE_FRAMES:
		if playback.get_ref() == null:
			break
		await get_tree().process_frame
	(
		assert_bool(playback.get_ref() == null)
		. override_failure_message("the hook left the voice held by the audio thread")
		. is_true()
	)


# A second of a quiet tone: long enough to be playing when the hook runs.
func _tone() -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	data.resize(rate * 2)
	for i in rate:
		data.encode_s16(i * 2, int(sin(TAU * 440.0 * i / rate) * 1000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav

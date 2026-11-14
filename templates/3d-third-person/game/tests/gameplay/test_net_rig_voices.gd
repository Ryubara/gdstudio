# The online rig lets go of its bodies' voices when it is freed (gdstudio #1495): the audio thread
# frees a playback a few mixes after it stops, so a rig freed right after a swing, by the last
# suite of a run, left the swing's playback and its decoded takes alive at exit (`6 ObjectDB
# instances were leaked`) while every case passed. Here a voice plays under the rig, the rig is
# freed, and the playback must be gone within a few frames, before the audio thread could have
# mixed again by itself.
extends GdUnitTestSuite

## The frames after `free()` the voice may take to go (the audio server's updates).
const RELEASE_FRAMES := 4


func test_a_freed_rig_holds_no_voice() -> void:
	var rig := OnlineRig.new()
	add_child(rig)
	var player := AudioStreamPlayer3D.new()
	player.stream = _tone()
	rig.add_child(player)
	player.play()
	# A 3D player hands its voice to the audio server on its next physics frame.
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Until the audio thread has mixed it: a voice freed before its first mix is let go of at once.
	AudioSettings.drain_mixer()
	assert_float(player.get_playback_position()).is_greater(0.0)
	assert_bool(player.playing).is_true()
	var playback: WeakRef = weakref(player.get_stream_playback())
	# Asked as a bool: an assert keeps the value it was given, which would hold the voice itself.
	assert_bool(playback.get_ref() != null).is_true()
	rig.free()
	# The audio server deletes a voice the mix thread has let go of on its next updates, on this
	# thread: a few frames, which on `--fixed-fps` are a fraction of a millisecond, far less than
	# one mix (tens of milliseconds) of the audio thread.
	for _frame in RELEASE_FRAMES:
		if playback.get_ref() == null:
			break
		await get_tree().process_frame
	(
		assert_bool(playback.get_ref() == null)
		. override_failure_message(
			"the voice was still held by the audio thread when the rig was freed"
		)
		. is_true()
	)


# A second of a quiet tone: long enough to be playing when the rig goes.
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

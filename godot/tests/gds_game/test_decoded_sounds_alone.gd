# `DecodedSounds` of `gds_game` on its own: a short Ogg Vorbis comes back as a WAV holding the
# samples its decoder plays, made once and shared; mono stays mono; a loop, a long sound and a WAV
# come back as they were; and a decoded sound starts far faster than the Ogg. The two tones in
# `fixtures/` are generated sines (ffmpeg's `sine` source), 0.15 s mono and 0.2 s stereo.
extends GdUnitTestSuite

const MONO := "res://tests/gds_game/fixtures/tone_mono.ogg"
const STEREO := "res://tests/gds_game/fixtures/tone_stereo.ogg"


func before_test() -> void:
	DecodedSounds.clear()


func after() -> void:
	DecodedSounds.clear()


func _ogg(path: String) -> AudioStreamOggVorbis:
	# A copy, so a test that sets `loop` leaves the cached resource alone.
	return (load(path) as AudioStreamOggVorbis).duplicate()


# What the Ogg's own decoder plays, frame by frame, at the mix rate.
func _played(stream: AudioStream, frames: int) -> PackedVector2Array:
	var playback := stream.instantiate_playback()
	playback.start(0.0)
	var out := PackedVector2Array()
	while out.size() < frames:
		out.append_array(playback.mix_audio(1.0, mini(1024, frames - out.size())))
	return out


func _frame(wav: AudioStreamWAV, index: int) -> Vector2:
	if wav.stereo:
		return Vector2(wav.data.decode_s16(index * 4), wav.data.decode_s16(index * 4 + 2)) / 32767.0
	var value := wav.data.decode_s16(index * 2) / 32767.0
	return Vector2(value, value)


func test_a_short_ogg_becomes_a_wav_made_once_and_shared() -> void:
	var ogg := load(MONO) as AudioStream
	var first := DecodedSounds.decoded(ogg)
	assert_object(first).is_instanceof(AudioStreamWAV)
	assert_object(DecodedSounds.decoded(ogg)).is_same(first)
	var wav := first as AudioStreamWAV
	assert_int(wav.format).is_equal(AudioStreamWAV.FORMAT_16_BITS)
	assert_int(wav.mix_rate).is_equal(int(AudioServer.get_mix_rate()))
	# As long as the file, give or take the silence the encoder padded.
	assert_float(wav.get_length()).is_between(ogg.get_length() - 0.03, ogg.get_length() + 0.03)


func test_the_wav_holds_the_samples_the_decoder_plays() -> void:
	var ogg := load(STEREO) as AudioStream
	var wav := DecodedSounds.decoded(ogg) as AudioStreamWAV
	var frames := int(wav.get_length() * wav.mix_rate)
	var played := _played(ogg, frames)
	var worst := 0.0
	for index in frames:
		var difference := (_frame(wav, index) - played[index]).abs()
		worst = maxf(worst, maxf(difference.x, difference.y))
	# 16-bit rounding is half a step; nothing more may differ.
	assert_float(worst).is_less_equal(1.0 / 32767.0)


func test_mono_stays_mono_and_two_channels_stay_two() -> void:
	assert_bool((DecodedSounds.decoded(load(MONO)) as AudioStreamWAV).stereo).is_false()
	assert_bool((DecodedSounds.decoded(load(STEREO)) as AudioStreamWAV).stereo).is_true()


func test_a_loop_a_long_sound_and_a_wav_come_back_as_they_were() -> void:
	var looping := _ogg(MONO)
	looping.loop = true
	assert_object(DecodedSounds.decoded(looping)).is_same(looping)
	var long := load(STEREO) as AudioStream
	assert_object(DecodedSounds.decoded(long, 0.1)).is_same(long)
	var wav := AudioStreamWAV.new()
	assert_object(DecodedSounds.decoded(wav)).is_same(wav)
	assert_object(DecodedSounds.decoded(null)).is_null()


func test_decoded_all_keeps_the_order() -> void:
	var streams: Array[AudioStream] = [load(MONO), load(STEREO)]
	var decoded := DecodedSounds.decoded_all(streams)
	assert_int(decoded.size()).is_equal(2)
	assert_object(decoded[0]).is_same(DecodedSounds.decoded(streams[0]))
	assert_object(decoded[1]).is_same(DecodedSounds.decoded(streams[1]))


# The reason it exists. Measured here: an Ogg start about 250 µs, a WAV start about 1 µs; the test
# asks only for ten times, so a slow runner passes.
func test_a_decoded_sound_starts_far_faster_than_the_ogg() -> void:
	var ogg := load(MONO) as AudioStream
	var wav := DecodedSounds.decoded(ogg)
	var player: AudioStreamPlayer = auto_free(AudioStreamPlayer.new())
	add_child(player)
	var spent := {}
	for stream: AudioStream in [ogg, wav]:
		player.stream = stream
		var start := Time.get_ticks_usec()
		for _i in 20:
			player.play()
		spent[stream] = Time.get_ticks_usec() - start
		player.stop()
	assert_int(spent[ogg]).is_greater(spent[wav] * 10)

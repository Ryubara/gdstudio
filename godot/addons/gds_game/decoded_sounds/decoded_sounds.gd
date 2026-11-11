class_name DecodedSounds
extends RefCounted
## Short compressed sounds decoded once to PCM, so starting one costs next to nothing.
##
## `play()` on an Ogg Vorbis stream sets its decoder up again every time (the headers and
## codebooks are read for each playback): about 250 µs on the desktop and most of a millisecond in
## a browser, for a step a tenth of a second long. The same sound as an `AudioStreamWAV` starts in
## about a microsecond. `decoded(stream)` answers a WAV of a short, non-looping Ogg Vorbis or MP3
## stream, made the first time it is asked for and shared by everyone who asks after (a crowd's 25
## footsteps hold one copy of each file), and the stream itself for anything else (a long bed, a
## loop, a WAV already). The samples are what the decoder plays, at the mix rate, as 16-bit PCM:
## mono when both channels are the same. Use it where a sound is started often (steps, shots,
## impacts) and leave beds and music compressed. An `AudioStreamRandomizer` comes back as a copy
## holding the decoded takes, with the same weights, pitch and volume spread (also made once): a
## shot of five Ogg takes started in about 250 µs, its decoded copy in about 1 µs.

## Longer sounds stay compressed: their PCM would be large, and they start rarely.
const MAX_LENGTH := 2.5
## Frames decoded per call of the decoder.
const CHUNK := 1024

static var _cache: Dictionary = {}


## A WAV of `stream` when it is a short, non-looping compressed sound, made once and shared; else
## `stream` itself.
static func decoded(stream: AudioStream, max_length: float = MAX_LENGTH) -> AudioStream:
	if stream is AudioStreamRandomizer:
		return _decoded_randomizer(stream as AudioStreamRandomizer, max_length)
	if not _decodable(stream, max_length):
		return stream
	var key := stream.get_instance_id()
	var cached: AudioStream = _cache.get(key)
	if cached == null:
		cached = decode(stream)
		_cache[key] = cached
	return cached


## `decoded()` for each stream of `streams`, in order.
static func decoded_all(
	streams: Array[AudioStream], max_length: float = MAX_LENGTH
) -> Array[AudioStream]:
	var result: Array[AudioStream] = []
	for stream in streams:
		result.append(decoded(stream, max_length))
	return result


## Decodes the whole of `stream` to a new WAV at the mix rate, uncached. The decoder's frames go to
## the engine's own WAV reader as one 32-bit float file, which makes the 16-bit samples natively:
## a loop over every sample in script cost about 1.2 ms a take on the desktop and twice that in a
## browser.
static func decode(stream: AudioStream) -> AudioStreamWAV:
	var rate := int(AudioServer.get_mix_rate())
	var total := int(ceil(stream.get_length() * rate)) + CHUNK
	var frames := PackedVector2Array()
	var playback := stream.instantiate_playback()
	playback.start(0.0)
	while frames.size() < total and playback.is_playing():
		var chunk: PackedVector2Array = playback.mix_audio(1.0, CHUNK)
		if chunk.is_empty():
			break
		frames.append_array(chunk)
	_trim_silence(frames)
	var options := {
		"force/mono": _is_mono(frames),
		"force/8_bit": false,
		"force/max_rate": false,
		"edit/trim": false,
		"edit/normalize": false,
		"compress/mode": 0,
	}
	return AudioStreamWAV.load_from_buffer(_float_wav(frames, rate), options)


## Forgets every decoded sound (a test that changes the mix rate, a game that unloads a level).
static func clear() -> void:
	_cache.clear()


# A copy of `randomizer` with each take decoded, made once; `randomizer` itself when no take
# needs decoding. The copy is checked against the original on every ask, so a take swapped or a
# spread changed in the inspector while the game runs shows in the next play.
static func _decoded_randomizer(
	randomizer: AudioStreamRandomizer, max_length: float
) -> AudioStream:
	var key := randomizer.get_instance_id()
	var cached := _cache.get(key) as AudioStreamRandomizer
	if cached != null and _same_spread(cached, randomizer, max_length):
		return cached
	var copy := randomizer.duplicate() as AudioStreamRandomizer
	var changed := false
	for index in randomizer.streams_count:
		var take := randomizer.get_stream(index)
		var plain := decoded(take, max_length)
		changed = changed or plain != take
		copy.set_stream(index, plain)
	# Nothing to decode (WAV takes already): the randomizer itself, remembered so the next ask
	# makes no copy.
	_cache[key] = copy if changed else randomizer
	return _cache[key]


static func _same_spread(
	copy: AudioStreamRandomizer, original: AudioStreamRandomizer, max_length: float
) -> bool:
	if (
		copy.streams_count != original.streams_count
		or copy.random_pitch != original.random_pitch
		or copy.random_volume_offset_db != original.random_volume_offset_db
		or copy.playback_mode != original.playback_mode
	):
		return false
	for index in original.streams_count:
		if (
			copy.get_stream_probability_weight(index)
			!= original.get_stream_probability_weight(index)
		):
			return false
		if copy.get_stream(index) != decoded(original.get_stream(index), max_length):
			return false
	return true


static func _decodable(stream: AudioStream, max_length: float) -> bool:
	if stream is AudioStreamOggVorbis:
		return not (stream as AudioStreamOggVorbis).loop and stream.get_length() <= max_length
	if stream is AudioStreamMP3:
		return not (stream as AudioStreamMP3).loop and stream.get_length() <= max_length
	return false


# The decoder pads the last call with silence: drop the zero frames after the sound ends.
static func _trim_silence(frames: PackedVector2Array) -> void:
	var end := frames.size()
	while end > 0 and frames[end - 1] == Vector2.ZERO:
		end -= 1
	frames.resize(end)


# True when both channels are the same in every frame (a mono file decodes to two equal channels).
static func _is_mono(frames: PackedVector2Array) -> bool:
	for frame in frames:
		if frame.x != frame.y:
			return false
	return true


# `frames` as the bytes of a two-channel 32-bit float WAV file at `rate`.
static func _float_wav(frames: PackedVector2Array, rate: int) -> PackedByteArray:
	var samples := frames.to_byte_array()
	var header := PackedByteArray()
	header.resize(44)
	header.encode_u32(0, 0x46464952)  # "RIFF"
	header.encode_u32(4, 36 + samples.size())
	header.encode_u32(8, 0x45564157)  # "WAVE"
	header.encode_u32(12, 0x20746D66)  # "fmt "
	header.encode_u32(16, 16)
	header.encode_u16(20, 3)  # IEEE float
	header.encode_u16(22, 2)
	header.encode_u32(24, rate)
	header.encode_u32(28, rate * 8)
	header.encode_u16(32, 8)
	header.encode_u16(34, 32)
	header.encode_u32(36, 0x61746164)  # "data"
	header.encode_u32(40, samples.size())
	header.append_array(samples)
	return header

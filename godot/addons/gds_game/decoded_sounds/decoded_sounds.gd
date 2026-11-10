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
## impacts) and leave beds and music compressed.

## Longer sounds stay compressed: their PCM would be large, and they start rarely.
const MAX_LENGTH := 2.5
## Frames decoded per call of the decoder.
const CHUNK := 1024

static var _cache: Dictionary = {}


## A WAV of `stream` when it is a short, non-looping compressed sound, made once and shared; else
## `stream` itself.
static func decoded(stream: AudioStream, max_length: float = MAX_LENGTH) -> AudioStream:
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


## Decodes the whole of `stream` to a new WAV at the mix rate, uncached.
static func decode(stream: AudioStream) -> AudioStreamWAV:
	var rate := AudioServer.get_mix_rate()
	var total := int(ceil(stream.get_length() * rate)) + CHUNK
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	var playback := stream.instantiate_playback()
	playback.start(0.0)
	while left.size() < total and playback.is_playing():
		var chunk: PackedVector2Array = playback.mix_audio(1.0, CHUNK)
		if chunk.is_empty():
			break
		for frame in chunk:
			left.append(frame.x)
			right.append(frame.y)
	_trim_silence(left, right)
	var stereo := left != right
	var data := PackedByteArray()
	data.resize(left.size() * (4 if stereo else 2))
	var at := 0
	for index in left.size():
		data.encode_s16(at, _sample(left[index]))
		at += 2
		if stereo:
			data.encode_s16(at, _sample(right[index]))
			at += 2
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(rate)
	wav.stereo = stereo
	wav.data = data
	return wav


## Forgets every decoded sound (a test that changes the mix rate, a game that unloads a level).
static func clear() -> void:
	_cache.clear()


static func _decodable(stream: AudioStream, max_length: float) -> bool:
	if stream is AudioStreamOggVorbis:
		return not (stream as AudioStreamOggVorbis).loop and stream.get_length() <= max_length
	if stream is AudioStreamMP3:
		return not (stream as AudioStreamMP3).loop and stream.get_length() <= max_length
	return false


# The decoder pads the last call with silence: drop the zero frames after the sound ends.
static func _trim_silence(left: PackedFloat32Array, right: PackedFloat32Array) -> void:
	var end := left.size()
	while end > 0 and left[end - 1] == 0.0 and right[end - 1] == 0.0:
		end -= 1
	left.resize(end)
	right.resize(end)


static func _sample(value: float) -> int:
	return clampi(roundi(value * 32767.0), -32768, 32767)

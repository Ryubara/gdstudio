## What starting a shot or an impact sound costs the main thread, and where the time goes.
##
## Each case starts `PLAYS` sounds, one on each of `PLAYS` `AudioStreamPlayer3D`s already in the
## tree, `ROUNDS` times, and prints the median microseconds of one start on a line starting
## `SOUND_START`. The cases take the time apart: the pistol's shot as the definition holds it (an
## `AudioStreamRandomizer` of Ogg Vorbis takes), one Ogg take alone, the same take decoded to a
## 16-bit `AudioStreamWAV`, the same compressed to QOA, a randomizer of the decoded takes, the take
## on a flat `AudioStreamPlayer` (no 3D), and what the template plays now: the weapon's
## `ShotSound` after `Weapon` set its stream, and an impact through the level's `EffectEmitter`
## (the default surface: the emitter alone, its sound, sound and dust). A first line times decoding
## every short take of the pistol and the impacts once, as the level's load now does.
##
## On a computer: `gds godot -- --headless --path game --scene
## res://tools/bench/sound_start_bench.tscn` (the dummy audio driver still sets each playback up).
## In the browser: `tools/bench/sound_start_bench.py` (the header says how to export it), which
## reads `window.__sound_start_bench`. It lives in tools/, which the export leaves out.
extends Node

## Starts a case times, on as many players, and the rounds a case is measured over.
const PLAYS := 50
const ROUNDS := 9
## Frames the sounds of a round play before they are stopped and the mixer frees the playbacks;
## longer in the browser, whose output comes 50 ms or more after the start and is tapped there.
const SETTLE_FRAMES := 4
const WEB_SETTLE_FRAMES := 20

const PISTOL := preload("res://gameplay/weapon/pistol.tres")
const IMPACTS := preload("res://gameplay/impacts/impacts.tscn")
const WEAPON := preload("res://gameplay/weapon/weapon.tscn")
const EMITTER := preload("res://gameplay/effects/effect_emitter.tscn")

var _players: Array[AudioStreamPlayer3D] = []
var _flat: Array[AudioStreamPlayer] = []
var _results: Array = []


func _ready() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.make_current()
	for index in PLAYS:
		var player := AudioStreamPlayer3D.new()
		player.bus = &"SFX"
		player.position = Vector3(float(index % 10) - 5.0, 0.0, -2.0 - float(index / 10))
		add_child(player)
		_players.append(player)
		var flat := AudioStreamPlayer.new()
		flat.bus = &"SFX"
		add_child(flat)
		_flat.append(flat)
	await get_tree().process_frame
	await _run_all()
	_finish()


func _run_all() -> void:
	_decode_cost()
	var shot := PISTOL.shot_sound as AudioStreamRandomizer
	var take := shot.get_stream(0)
	var wav := _pcm(take)
	var qoa := _qoa(wav)
	var randomizer_wav := shot.duplicate() as AudioStreamRandomizer
	for index in randomizer_wav.streams_count:
		randomizer_wav.set_stream(index, _pcm(shot.get_stream(index)))
	await _case("shot_randomizer_ogg_3d", shot)
	await _case("shot_take_ogg_3d", take)
	await _case("shot_take_ogg_flat", take, true)
	await _case("shot_take_wav_3d", wav)
	await _case("shot_take_qoa_3d", qoa)
	await _case("shot_randomizer_wav_3d", randomizer_wav)
	await _case("shot_randomizer_wav_flat", randomizer_wav, true)
	await _weapon_case()
	await _impact_cases()


# What decoding every short take of the pistol and the impacts costs once, while the level loads
# (`Weapon` and the emitter's slots do it then): milliseconds, on a line of its own.
func _decode_cost() -> void:
	DecodedSounds.clear()
	var streams: Array[AudioStream] = [PISTOL.shot_sound, PISTOL.empty_sound, PISTOL.draw_sound]
	streams.append_array(PISTOL.reload_sounds)
	var impacts := IMPACTS.instantiate()
	for surface in impacts.get_node(^"Surfaces").get_children():
		streams.append(surface.effect.sound)
	impacts.free()
	var takes := 0
	var started := Time.get_ticks_usec()
	for stream in streams:
		DecodedSounds.decoded(stream)
		takes += (
			(stream as AudioStreamRandomizer).streams_count
			if stream is AudioStreamRandomizer
			else 1
		)
	var result := {
		"case": "decode_on_load",
		"ms": snappedf((Time.get_ticks_usec() - started) / 1000.0, 0.01),
		"takes": takes,
	}
	print("SOUND_START ", JSON.stringify(result))
	_results.append(result)


# The median microseconds of one start of `stream` over the rounds.
func _case(case_name: String, stream: AudioStream, flat := false) -> void:
	_mark(case_name)
	for index in PLAYS:
		_players[index].stream = stream
		_flat[index].stream = stream
	var rounds: Array[float] = []
	for _round in ROUNDS:
		var started := Time.get_ticks_usec()
		for index in PLAYS:
			if flat:
				_flat[index].play()
			else:
				_players[index].play()
		rounds.append(float(Time.get_ticks_usec() - started) / PLAYS)
		await _settle()
	_report(case_name, rounds, stream)


# The weapon's `ShotSound` as the template plays it: `Weapon` sets its stream from the definition.
func _weapon_case() -> void:
	var weapon := WEAPON.instantiate() as Weapon
	weapon.definition = PISTOL
	add_child(weapon)
	var sound := weapon.get_node(^"ShotSound") as AudioStreamPlayer3D
	_mark("weapon_shot_sound")
	var rounds: Array[float] = []
	for _round in ROUNDS:
		var started := Time.get_ticks_usec()
		for _play in PLAYS:
			sound.play()
		rounds.append(float(Time.get_ticks_usec() - started) / PLAYS)
		await _settle()
	_report("weapon_shot_sound", rounds, sound.stream)
	weapon.queue_free()


# An impact through the level's emitter, the default surface: its sound alone, then with its dust.
func _impact_cases() -> void:
	var emitter := EMITTER.instantiate() as EffectEmitter
	emitter.warm_up_on_start = false
	emitter.max_effects = PLAYS
	add_child(emitter)
	var impacts := IMPACTS.instantiate()
	add_child(impacts)
	var effect: EffectDef = impacts.get_node(^"Surfaces/Default").effect
	effect = effect.duplicate()
	effect.max_instances = PLAYS
	await get_tree().process_frame
	# The emitter alone (a slot taken, nothing shown or heard), its sound, then sound and dust.
	for parts: Array in [[false, false], [false, true], [true, true]]:
		var with_particles: bool = parts[0]
		var case_name := (
			"impact_with_dust"
			if with_particles
			else ("impact_sound_only" if parts[1] else "impact_emitter_only")
		)
		_mark(case_name)
		var rounds: Array[float] = []
		for _round in ROUNDS:
			var started := Time.get_ticks_usec()
			for index in PLAYS:
				emitter.play_at(
					effect, _players[index].global_position, Vector3.UP, with_particles, parts[1]
				)
			rounds.append(float(Time.get_ticks_usec() - started) / PLAYS)
			await _settle()
			emitter.stop_all()
		var slot := emitter.slots()[0]
		_report(case_name, rounds, slot.sound_player().stream if slot.sound_player() else null)
	emitter.queue_free()
	impacts.queue_free()


# Tells the browser's tap which case plays now, so it reads each case's loudest sample apart.
func _mark(case_name: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__mark && window.__mark('%s')" % case_name)


func _settle() -> void:
	if OS.has_feature("web"):
		for _frame in WEB_SETTLE_FRAMES:
			await get_tree().process_frame
	for index in PLAYS:
		_players[index].stop()
		_flat[index].stop()
	for _frame in SETTLE_FRAMES:
		await get_tree().process_frame


func _report(case_name: String, rounds: Array[float], stream: AudioStream) -> void:
	rounds.sort()
	var result := {
		"case": case_name,
		"us_per_start_median": snappedf(rounds[rounds.size() / 2], 0.1),
		"us_per_start_min": snappedf(rounds[0], 0.1),
		"stream": stream.get_class() if stream != null else "none",
	}
	print("SOUND_START ", JSON.stringify(result))
	_results.append(result)


# The take as the decoder plays it, as 16-bit PCM.
func _pcm(stream: AudioStream) -> AudioStreamWAV:
	return DecodedSounds.decode(stream)


# The same samples compressed to QOA, the way the importer's `compress/mode` QOA does.
func _qoa(wav: AudioStreamWAV) -> AudioStreamWAV:
	var path := "user://sound_start_bench_take.wav"
	wav.save_to_wav(path)
	var qoa := AudioStreamWAV.load_from_file(path, {"compress/mode": 2})
	DirAccess.remove_absolute(path)
	return qoa


func _finish() -> void:
	_mark("end")
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__sound_start_bench = %s;" % JSON.stringify(_results))
		return
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()

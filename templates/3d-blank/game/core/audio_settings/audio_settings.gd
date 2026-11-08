@tool
class_name AudioSettings
extends Node
## The volume of each audio bus, as inspector values. Changing one applies to `AudioServer` at
## once, so the remote inspector tunes the mix while the game runs, and the editor follows too
## (the buses are the project's own, `default_bus_layout.tres`; this node never saves anything).
## Add one node to the main scene; a settings screen can set the same properties.
##
## The buses are `Master`, then `SFX`, `Ambient` and `UI` sending to it. A bus the project does
## not have is skipped, so a game that renames one only loses that slider.

## The bus every other bus sends to.
const MASTER := &"Master"
## Effects: steps, pickups, hits.
const SFX := &"SFX"
## Beds that play for a whole stay: wind, room tone.
const AMBIENT := &"Ambient"
## Menus and the interface.
const UI := &"UI"

const MIN_DB := -60.0
const MAX_DB := 6.0

## How many times the audio thread must have mixed before a stopped voice is let go of.
const DRAIN_MIX_STEPS := 3
## The most checks, 5 ms apart, that `drain_mixer()` makes.
const DRAIN_MAX_POLLS := 200

@export_group("Volume")
## Everything, last.
@export_range(MIN_DB, MAX_DB, 0.1, "suffix:dB") var master_db := 0.0:
	set(value):
		master_db = value
		_apply(MASTER, value)
## Steps, pickups and other effects.
@export_range(MIN_DB, MAX_DB, 0.1, "suffix:dB") var sfx_db := 0.0:
	set(value):
		sfx_db = value
		_apply(SFX, value)
## Wind and other beds.
@export_range(MIN_DB, MAX_DB, 0.1, "suffix:dB") var ambient_db := 0.0:
	set(value):
		ambient_db = value
		_apply(AMBIENT, value)
## Menu and interface sounds. They sit under the game's own sounds.
@export_range(MIN_DB, MAX_DB, 0.1, "suffix:dB") var ui_db := -3.0:
	set(value):
		ui_db = value
		_apply(UI, value)


func _ready() -> void:
	apply_all()


func _exit_tree() -> void:
	# A voice still playing when the engine quits is reported as `ObjectDB instances were leaked`
	# and `resources still in use` (the audio thread frees it a few mixes after it was stopped).
	if not Engine.is_editor_hint() and get_parent() != null:
		stop_players(get_parent())
		drain_mixer()


## Sends every volume to `AudioServer` again (the buses may have been loaded after this node was).
func apply_all() -> void:
	_apply(MASTER, master_db)
	_apply(SFX, sfx_db)
	_apply(AMBIENT, ambient_db)
	_apply(UI, ui_db)


## Stops every audio player under `root`, so no voice is left playing (see `drain_mixer()`).
static func stop_players(root: Node) -> void:
	for node in root.find_children("*", "AudioStreamPlayer", true, false):
		(node as AudioStreamPlayer).stop()
	for node in root.find_children("*", "AudioStreamPlayer3D", true, false):
		(node as AudioStreamPlayer3D).stop()


## Waits, blocking this thread, until the audio thread has mixed a few times, so every voice that
## was stopped has been let go of (`stop_players()` first). Returns false when the thread did not
## mix in time (or there is no audio thread to wait for).
static func drain_mixer() -> bool:
	var steps := 0
	var last := AudioServer.get_time_since_last_mix()
	for _poll in DRAIN_MAX_POLLS:
		if steps >= DRAIN_MIX_STEPS:
			return true
		OS.delay_msec(5)
		var now := AudioServer.get_time_since_last_mix()
		if now < last:
			steps += 1
		last = now
	return false


## The volume `AudioServer` has for a bus, or `NAN` when the project has no such bus.
static func bus_volume_db(bus: StringName) -> float:
	var index := AudioServer.get_bus_index(bus)
	return AudioServer.get_bus_volume_db(index) if index >= 0 else NAN


func _apply(bus: StringName, volume_db: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, volume_db)

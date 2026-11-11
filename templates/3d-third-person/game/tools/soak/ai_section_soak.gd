## The AI section's short soak (kit #969): the real game with the section's whole population,
## the player (invulnerable) walked round the section by `SectionPilot` and fighting whatever is
## hostile in its sight, for `AI_SOAK_SECONDS` simulated seconds (180 by default). It holds three
## gates and prints them as one `SOAK {json}` line, then quits (exit 1 when a gate failed):
##
## - no stuck episode longer than 3 s: a living character whose navigator has a goal it has not
##   reached, and that moved less than 0.5 m in that time;
## - no character idle with a threat in view longer than 5 s: its brain sees a hostile
##   (`AiBrain` reminder's test) and its controller asks for nothing, its weapon neither reloading
##   nor switching;
## - no engine error (a `Logger` counts them).
##
## Run it headless at a fixed step, from the game folder:
## `godot --headless --path game --fixed-fps 60 res://tools/soak/ai_section_soak.tscn`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const STUCK_SECONDS := 3.0
const STUCK_METRES := 0.5
const IDLE_SECONDS := 5.0
## The loop the pilot walks, in the section's space (its origin is the doorway).
const LOOP: Array[Vector3] = [
	Vector3(-3.0, 0.0, 0.0),
	Vector3(-12.0, 0.0, -4.0),
	Vector3(-20.0, 0.0, -12.0),
	Vector3(-25.0, 0.0, 1.5),
	Vector3(-12.0, 0.0, 11.0),
	Vector3(-6.0, 0.0, 3.0),
]

var _seconds := 180.0
var _clock := 0.0
var _errors := ErrorCount.new()
var _watch: Dictionary[int, Watch] = {}
var _stuck: Array[String] = []
var _idle: Array[String] = []
var _deaths: Dictionary[StringName, int] = {}
var _steps := PackedFloat64Array()
var _pilot: SectionPilot

@onready var _main: Node = $Main
@onready var _player: Player = $Main/PlayerRig/Player


## What the soak keeps of one character.
class Watch:
	var since := 0.0
	var anchor := Vector3.ZERO
	var idle := 0.0
	var stuck_told := false
	var idle_told := false


## Counts the engine's errors and warnings while the soak runs.
class ErrorCount:
	extends Logger
	var lines: Array[String] = []

	func _log_error(
		function: String,
		_file: String,
		_line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_backtraces: Array[ScriptBacktrace]
	) -> void:
		if error_type != ERROR_TYPE_WARNING:
			lines.append("%s: %s %s" % [function, code, rationale])


func _ready() -> void:
	_seconds = (
		float(OS.get_environment("AI_SOAK_SECONDS"))
		if OS.has_environment("AI_SOAK_SECONDS")
		else 180.0
	)
	OS.add_logger(_errors)
	Health.of(_player).invulnerable = true
	var section := _main.get_node("World/AISection") as Node3D
	var points := PackedVector3Array()
	for point in LOOP:
		points.append(section.to_global(point))
	_player.teleport(points[0], -PI / 2.0)
	_pilot = SectionPilot.new()
	_pilot.player = _player
	_pilot.camera_rig = _main.get_node("PlayerRig/PlayerCamera")
	_pilot.waypoints = points
	add_child(_pilot)
	for spawner: AiSpawner in section.get_node("Population").get_children():
		spawner.spawned.connect(_on_spawned.bind(spawner.name))


func _physics_process(delta: float) -> void:
	_clock += delta
	var director := AiDirector.find(get_tree())
	if director != null and _clock > 2.0:
		_steps.append(director.last_step_usec)
	for node in get_tree().get_nodes_in_group(AiCharacter.GROUP):
		_check(node as AiCharacter, delta)
	if _clock >= _seconds:
		_finish()


func _check(character: AiCharacter, delta: float) -> void:
	if character == null or character.is_dead():
		return
	var id := character.get_instance_id()
	if not _watch.has(id):
		_watch[id] = Watch.new()
		_watch[id].anchor = character.global_position
		_watch[id].since = _clock
	var watch := _watch[id]
	var navigator := character.navigator as AiNavigator
	var going := navigator != null and navigator.is_active() and not navigator.is_arrived()
	if not going or character.global_position.distance_to(watch.anchor) > STUCK_METRES:
		watch.anchor = character.global_position
		watch.since = _clock
		watch.stuck_told = false
	elif _clock - watch.since > STUCK_SECONDS and not watch.stuck_told:
		watch.stuck_told = true
		_stuck.append(
			"%s at %s, t=%.1f" % [character.name, character.global_position.round(), _clock]
		)
	var mind := character.brain as AiBrain
	var threat: AiBelief = mind.call(&"_threat_in_view") if mind != null else null
	if (
		threat != null
		and threat.band == AiRelations.Band.HOSTILE
		and not _asks_something(character)
	):
		watch.idle += delta
		if watch.idle > IDLE_SECONDS and not watch.idle_told:
			watch.idle_told = true
			_idle.append(
				(
					"%s (%s) t=%.1f"
					% [
						character.name,
						(character.task_runner as AiTasks).runner.active_kind(),
						_clock
					]
				)
			)
	else:
		watch.idle = 0.0
		watch.idle_told = false


func _asks_something(character: AiCharacter) -> bool:
	if not character.ai_controller().is_still():
		return true
	if character.weapon != null and character.weapon.is_reloading():
		return true
	return character.loadout != null and character.loadout.is_switching()


func _on_spawned(character: AiCharacter, kind: StringName) -> void:
	if not character.died.is_connected(_on_died):
		character.died.connect(_on_died.bind(kind))


func _on_died(kind: StringName) -> void:
	_deaths[kind] = _deaths.get(kind, 0) + 1


func _finish() -> void:
	set_physics_process(false)
	OS.remove_logger(_errors)
	var sorted := _steps.duplicate()
	sorted.sort()
	var spawned := {}
	for spawner: AiSpawner in _main.get_node("World/AISection/Population").get_children():
		spawned[spawner.name] = spawner.spawned_total
	var result := {
		"seconds": snappedf(_clock, 0.1),
		"stuck_over_3s": _stuck,
		"idle_with_threat_over_5s": _idle,
		"errors": _errors.lines.slice(0, 10),
		"error_count": _errors.lines.size(),
		"deaths": _deaths,
		"spawned": spawned,
		"player_shots": _pilot.fired,
		"director_step_us_mean": _mean(sorted),
		"director_step_us_p95": sorted[int(sorted.size() * 0.95)] if not sorted.is_empty() else 0,
	}
	print("SOAK " + JSON.stringify(result))
	var passed := _stuck.is_empty() and _idle.is_empty() and _errors.lines.is_empty()
	get_tree().quit(0 if passed else 1)


func _mean(values: PackedFloat64Array) -> float:
	var total := 0.0
	for value in values:
		total += value
	return snappedf(total / maxf(values.size(), 1.0), 0.1)

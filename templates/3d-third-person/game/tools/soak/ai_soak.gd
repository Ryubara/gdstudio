class_name AiSoak
extends Node
## The AI soak of 3D Third Person (kit #971): the real game (`main.tscn`) with the AI section's
## population times `population_scale` and `pathing_count_each` of each of `pathing_kinds` going
## about the pathing section, the player (invulnerable) walked round the AI section by
## `SectionPilot` and shooting every hostile in its sight, for `seconds` of simulated time at a
## fixed step, seeded. `AiSoakWatch` (the `Watch` node) holds the gates; this scene adds the
## round: the AI section's hostiles alive when a round starts must all die, and a round still
## open after `round_seconds` sends the pilot to its nearest living hostile (the rescue,
## counted), half way through the rescue the soak kills what is left (the safety net, counted),
## and one still alive at its end (a pocket nothing ends: an invulnerable body) breaks the
## `round` gate.
##
## It prints one `AI_SOAK {json}` line (the gates broken, rounds, rescues, think and step costs,
## the hash of every character's commands), an `AI_SOAK_GATE {json}` line a broken gate with what
## the character held, did and decided, with `--lines` an `AI_SOAK_CHARACTER {json}` line a
## character (the nightly job's numbers), then quits: exit 1 when a gate broke. Open it in the
## editor to set the counts and the thresholds in the inspector and watch it (the overlay shows
## the gates live).
##
## Headless, from the game folder:
## `godot --headless --path . --fixed-fps 60 res://tools/soak/ai_soak.tscn -- --seconds 180`
## (options: `--seed N`, `--scale N`, `--pathing N`, `--faults stuck,idle,...|all`, `--round S`,
## `--rescue S`, `--lines`). In a browser (`gds template bench-web 3d-third-person
## tools/soak/ai_soak.tscn`, read by `tools/web_smoke/ai.py`) it takes the same options from the
## page's query (`?scale=4&seconds=20`) and leaves its result in `window.__ai_soak`.
## Docs: the kit's `docs/gamedev/bots.md#ai-soak` and `docs/engines/godot/crowds.md#ai-characters`.

## The pilot's loop in the AI section's space (its origin is the doorway).
const LOOP: Array[Vector3] = [
	Vector3(-3.0, 0.0, 0.0),
	Vector3(-12.0, 0.0, -4.0),
	Vector3(-20.0, 0.0, -12.0),
	Vector3(-25.0, 0.0, 1.5),
	Vector3(-12.0, 0.0, 11.0),
	Vector3(-6.0, 0.0, 3.0),
]
## Metres between a spawn marker and the extra ones `population_scale` adds round it.
const EXTRA_MARKER_SPACING := 2.0
## Metres an extra marker may be from the walking mesh.
const EXTRA_MARKER_SLACK := 0.3
## Seconds between two looks at the round.
const ROUND_CHECK_SECONDS := 0.25
## Seconds between two updates of the rescue's goal.
const RESCUE_RETARGET_SECONDS := 3.0
## Ticks folded into one link of the command hash.
const HASH_TICKS := 60

## Simulated seconds it runs.
@export_range(1.0, 3600.0, 1.0, "suffix:s") var seconds := 180.0
## The seed of every character's rolls (each gets its own from it, in spawn order).
@export var random_seed := 1
## Times each spawner of the AI section keeps its count (more markers are added round its own).
@export_range(1, 16) var population_scale := 1
## The kinds that go about the pathing section (its routes' ends are their homes; a kind with a
## patrol route of the AI section would walk to it, and the two sections' meshes do not join).
@export var pathing_kinds: Array[PackedScene] = []
## How many of each pathing kind.
@export_range(0, 64) var pathing_count_each := 6
## Seconds a round may stay open before the rescue.
@export_range(5.0, 3600.0, 1.0, "suffix:s") var round_seconds := 120.0
## Seconds the rescue has before the round gate breaks.
@export_range(1.0, 600.0, 1.0, "suffix:s") var rescue_seconds := 30.0
## Quits with the result when the run is over (off: it keeps running for a person to watch).
@export var quit_at_end := true
## Prints a line of numbers a character at the end.
@export var character_lines := false
## Seconds at the start the frame costs leave out (the web probe's warm-up).
@export_range(0.0, 600.0, 1.0, "suffix:s") var warm_seconds := 5.0

## The result, once the run is over.
var result := {}
## Rounds ended, rescues sent, and the seconds each ended round took.
var rounds_ended := 0
var rescues := 0
## Hostiles the safety net killed after the pilot's half of the rescue.
var rescue_kills := 0
var round_lengths := PackedFloat64Array()

var _clock := 0.0
var _scaled := false
var _round: Array[AiCharacter] = []
var _round_index := 0
var _round_started := 0.0
var _rescuing := false
var _rescued_rounds := 0
var _rescue_retarget := 0.0
var _round_check := 0.0
var _loop := PackedVector3Array()
var _hash := 0
var _hash_values := PackedFloat64Array()
var _ticks := 0
var _spawn_index := 0
var _steps := PackedFloat64Array()
var _frame_work := PackedFloat64Array()
var _frames := 0
var _frame_ticks := 0
var _tick_start := -1
var _deaths: Dictionary[String, int] = {}
var _finished := false

@onready var _main: Node = $Main
@onready var _player: Player = $Main/PlayerRig/Player
@onready var _section: Node3D = $Main/World/AISection
@onready var _pathing: Node3D = $Main/World/PathingSection
@onready var _watch: AiSoakWatch = $Watch
@onready var _faults: AiSoakFaults = $Faults
@onready var _overlay: Label = $Overlay/Panel/Text
@onready var _pilot: SectionPilot = $Pilot


func _ready() -> void:
	# Its `_process` reads the frame's work after every other node's.
	process_priority = 1 << 30
	_read_options()
	Health.of(_player).invulnerable = true
	for point in LOOP:
		_loop.append(_section.to_global(point))
	_player.teleport(_loop[0], -PI / 2.0)
	_pilot.player = _player
	_pilot.camera_rig = _main.get_node("PlayerRig/PlayerCamera")
	_pilot.retarget(_loop)
	_faults.player = _player
	_faults.wall = _section.get_node("Navigation/Cover/TallCover")
	_faults.watch = _watch
	for spawner in _section_spawners():
		_wire_spawner(spawner)
		for character in spawner.alive:
			_on_spawned(character)
	_add_pathing_spawners()
	_overlay.get_parent().visible = DisplayServer.get_name() != "headless"
	get_tree().physics_frame.connect(_on_tick)


func _read_options() -> void:
	var options := _options()
	seconds = float(options.get("seconds", seconds))
	random_seed = int(options.get("seed", random_seed))
	population_scale = clampi(int(options.get("scale", population_scale)), 1, 16)
	pathing_count_each = int(options.get("pathing", pathing_count_each))
	round_seconds = float(options.get("round", round_seconds))
	rescue_seconds = float(options.get("rescue", rescue_seconds))
	warm_seconds = float(options.get("warm", warm_seconds))
	character_lines = character_lines or options.has("lines")
	if options.has("faults"):
		_faults.faults = AiSoakFaults.parse(String(options.faults))


# `--name value` pairs of the command line after `--`, or the page's query in a browser.
func _options() -> Dictionary:
	var options := {}
	if OS.has_feature("web"):
		var query := str(JavaScriptBridge.eval("window.location.search", true))
		for pair in query.trim_prefix("?").split("&", false):
			var parts := pair.split("=")
			options[parts[0]] = parts[1].uri_decode() if parts.size() > 1 else "1"
		return options
	if get_tree().current_scene != self:
		return options
	var args := OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		var key := args[index].trim_prefix("--")
		var has_value := index + 1 < args.size() and not args[index + 1].begins_with("--")
		options[key] = args[index + 1] if has_value else "1"
		index += 2 if has_value else 1
	return options


func _section_spawners() -> Array[AiSpawner]:
	var found: Array[AiSpawner] = []
	for node in _section.get_node("Population").get_children():
		if node is AiSpawner:
			found.append(node)
	return found


func _wire_spawner(spawner: AiSpawner) -> void:
	if not spawner.spawned.is_connected(_on_spawned):
		spawner.spawned.connect(_on_spawned)


# A spawner for each pathing kind, its markers the ends of the section's routes.
func _add_pathing_spawners() -> void:
	if pathing_count_each <= 0:
		return
	var markers: Array[Node3D] = []
	for route in _pathing.get_node("Routes").get_children():
		for end in route.get_children():
			if end is Node3D:
				markers.append(end)
	for kind in pathing_kinds:
		var spawner := AiSpawner.new()
		spawner.name = "Soak%s" % kind.resource_path.get_file().get_basename().to_pascal_case()
		spawner.scene = kind
		spawner.count = pathing_count_each
		spawner.markers = markers
		spawner.respawn_delay = 10.0
		spawner.spawned.connect(_on_spawned)
		_pathing.add_child(spawner)


func _on_spawned(character: AiCharacter) -> void:
	_spawn_index += 1
	var mind := character.brain as AiBrain
	if mind != null:
		mind.reseed(random_seed * 7919 + _spawn_index)
	if not character.died.is_connected(_on_died):
		character.died.connect(_on_died.bind(character))


func _on_died(character: AiCharacter) -> void:
	var kind := character.profile.display_name if character.profile != null else "AI"
	_deaths[kind] = _deaths.get(kind, 0) + 1


func _on_tick() -> void:
	if _finished:
		return
	var delta := 1.0 / Engine.physics_ticks_per_second
	_clock += delta
	_ticks += 1
	if not _scaled:
		_scale_population()
	_hash_commands()
	_round_check -= delta
	if _round_check <= 0.0:
		_round_check = ROUND_CHECK_SECONDS
		_refill_pilot()
		_tend_round()
	if _clock > warm_seconds:
		var director := AiDirector.find(get_tree())
		if director != null:
			_steps.append(director.last_step_usec)
		_frame_ticks += 1
		if _tick_start < 0:
			_tick_start = Time.get_ticks_usec()
	if _ticks % 15 == 0 and _overlay.get_parent().visible:
		_overlay.text = _overlay_text()
	if _clock >= seconds:
		_finish()


func _process(_delta: float) -> void:
	if _tick_start >= 0 and not _finished:
		_frame_work.append((Time.get_ticks_usec() - _tick_start) / 1000.0)
		_frames += 1
	_tick_start = -1


# Once the walking mesh is up: more markers round each spawner's own and the counts times
# `population_scale`.
func _scale_population() -> void:
	var map := _player.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return
	_scaled = true
	if population_scale <= 1:
		return
	var holder := Node3D.new()
	holder.name = "SoakMarkers"
	add_child(holder)
	for spawner in _section_spawners():
		var originals: Array[Node3D] = spawner.markers.duplicate()
		var wanted := spawner.count * population_scale
		var ring := 1
		while spawner.markers.size() < wanted and ring <= 4:
			for marker in originals:
				for step in 6:
					var angle := TAU * step / 6.0 + ring * 0.5
					var spot := (
						marker.global_position
						+ Vector3(cos(angle), 0.0, sin(angle)) * EXTRA_MARKER_SPACING * ring
					)
					var ground := NavigationServer3D.map_get_closest_point(map, spot)
					if Vector2(ground.x - spot.x, ground.z - spot.z).length() > EXTRA_MARKER_SLACK:
						continue
					var extra := Marker3D.new()
					holder.add_child(extra)
					extra.global_transform = Transform3D(marker.global_basis, ground)
					spawner.markers.append(extra)
			ring += 1
		spawner.count = wanted
		while spawner.alive.size() < spawner.count:
			if spawner.spawn_one() == null:
				break


func _hash_commands() -> void:
	for node in get_tree().get_nodes_in_group(AiCharacter.GROUP):
		var character := node as AiCharacter
		if character == null or character.is_dead():
			continue
		var at := character.global_position
		_hash_values.append(snappedf(at.x, 0.001))
		_hash_values.append(snappedf(at.z, 0.001))
		var controller := character.ai_controller()
		if controller != null:
			_hash_values.append(snappedf(controller.walk_direction.x, 0.001))
			_hash_values.append(snappedf(controller.walk_direction.z, 0.001))
			_hash_values.append(float(controller.aim) + 2.0 * float(controller.fire))
	if _ticks % HASH_TICKS == 0:
		_hash = hash([_hash, hash(_hash_values)])
		_hash_values.clear()


# The player never runs dry: a soak of the AI must not end its rounds by the pilot's ammunition.
func _refill_pilot() -> void:
	var weapon := _player.weapon
	if weapon == null or weapon.definition == null or weapon.definition.magazine_size <= 0:
		return
	if int(weapon.reserve) < weapon.definition.magazine_size:
		weapon.set_ammo(int(weapon.ammo), weapon.definition.start_reserve)


# The round: the hostiles alive at its start must all die; past `round_seconds` the pilot walks to
# the nearest living one; past the rescue the gate breaks and the next round starts.
func _tend_round() -> void:
	var living: Array[AiCharacter] = []
	for character in _round:
		if is_instance_valid(character) and character.is_inside_tree() and not character.is_dead():
			living.append(character)
	if not _round.is_empty() and living.is_empty():
		rounds_ended += 1
		_rescued_rounds += 1 if _rescuing else 0
		round_lengths.append(_clock - _round_started)
		_round.clear()
		if _rescuing:
			_rescuing = false
			_pilot.retarget(_loop)
	if _round.is_empty():
		_start_round()
		return
	_round = living
	var open := _clock - _round_started
	if open > round_seconds + rescue_seconds:
		var left := PackedStringArray()
		for character in living:
			left.append("%s at %s" % [character.name, character.global_position.round()])
		_watch.fail(
			&"round",
			living[0],
			(
				"round %d open %.0f s after a %.0f s rescue: %s"
				% [_round_index, open, rescue_seconds, ", ".join(left)]
			)
		)
		_round.clear()
		_rescuing = false
		_pilot.retarget(_loop)
		return
	if open > round_seconds + rescue_seconds * 0.5:
		# The safety net: the pilot did not end it, so the soak does (each one counted); a
		# character that still lives a moment later is a pocket nothing can end.
		for character in living:
			var health := Health.of(character)
			if health != null and not health.invulnerable and not health.is_dead():
				health.kill()
				rescue_kills += 1
	if open > round_seconds:
		if not _rescuing:
			_rescuing = true
			rescues += 1
			_rescue_retarget = 0.0
		_rescue_retarget -= ROUND_CHECK_SECONDS
		if _rescue_retarget <= 0.0:
			_rescue_retarget = RESCUE_RETARGET_SECONDS
			_pilot.retarget(PackedVector3Array([_nearest(living).global_position]))


func _start_round() -> void:
	for spawner in _section_spawners():
		for character in spawner.alive:
			if not character.is_dead() and _hostile(character):
				_round.append(character)
	if not _round.is_empty():
		_round_index += 1
		_round_started = _clock


func _nearest(characters: Array[AiCharacter]) -> AiCharacter:
	var best := characters[0]
	for character in characters:
		var far := character.global_position.distance_squared_to(_player.global_position)
		if far < best.global_position.distance_squared_to(_player.global_position):
			best = character
	return best


func _hostile(character: AiCharacter) -> bool:
	var factions := AiFactions.find(character)
	var me := AiFactionMember.of(_player)
	var them := AiFactionMember.of(character)
	if factions == null or me == null or them == null:
		return false
	return factions.band_of_members(me, them) == AiRelations.Band.HOSTILE


func _overlay_text() -> String:
	var broken := {}
	for sample in _watch.failures:
		broken[sample.gate] = broken.get(sample.gate, 0) + 1
	var lines := PackedStringArray()
	lines.append("AI soak  %.0f / %.0f s  seed %d" % [_clock, seconds, random_seed])
	lines.append(
		(
			"characters %d   round %d (%.0f s open)   ended %d   rescues %d"
			% [
				get_tree().get_nodes_in_group(AiCharacter.GROUP).size(),
				_round_index,
				_clock - _round_started,
				rounds_ended,
				rescues
			]
		)
	)
	for gate in AiSoakWatch.GATES:
		lines.append("%-18s %s" % [gate, "BROKEN x%d" % broken[gate] if broken.has(gate) else "ok"])
	return "\n".join(lines)


func _finish() -> void:
	_finished = true
	var broken := _watch.finish()
	var steps := _steps.duplicate()
	steps.sort()
	var work := _frame_work.duplicate()
	work.sort()
	var think := _watch.think_us.duplicate()
	think.sort()
	var calibration := _watch.calibrations.duplicate()
	calibration.sort()
	var spawned := {}
	for spawner in _section_spawners():
		spawned[String(spawner.name)] = spawner.spawned_total
	var gates := {}
	for gate in broken:
		gates[String(gate)] = broken[gate]
	result = {
		"seconds": snappedf(_clock, 0.1),
		"seed": random_seed,
		"scale": population_scale,
		"faults": _faults.faults,
		"fault_targets": _faults.target_names(),
		"passed": broken.is_empty(),
		"gates": gates,
		"characters": _watch.character_rows().size(),
		"spawned": spawned,
		"deaths": _deaths,
		"rounds": _round_index,
		"rounds_ended": rounds_ended,
		"rescues": rescues,
		"rescue_kills": rescue_kills,
		"rounds_without_rescue": rounds_ended - _rescued_rounds,
		"round_seconds_max": snappedf(_max(round_lengths), 0.1),
		"player_shots": _pilot.fired,
		"error_count": _watch.errors.size(),
		"errors": _watch.errors.slice(0, 5),
		"thinks": think.size(),
		"think_us_p50": AiSoakWatch.percentile(think, 0.5),
		"think_us_p99": AiSoakWatch.percentile(think, 0.99),
		"think_budget_us": snappedf(_watch.think_budget_us(), 1.0),
		"calibration_ms": snappedf(AiSoakWatch.percentile(calibration, 0.5), 0.01),
		"director_step_us_mean": snappedf(_mean(steps), 0.1),
		"director_step_us_p95": AiSoakWatch.percentile(steps, 0.95),
		"frames": _frames,
		"ticks_per_frame": snappedf(float(_frame_ticks) / maxi(_frames, 1), 0.01),
		"frame_work_ms_p50": snappedf(AiSoakWatch.percentile(work, 0.5), 0.01),
		"frame_work_ms_p95": snappedf(AiSoakWatch.percentile(work, 0.95), 0.01),
		"command_hash": _hash,
		"web": OS.has_feature("web"),
	}
	for sample in _watch.failures:
		print("AI_SOAK_GATE " + JSON.stringify(sample))
	if character_lines:
		for row in _watch.character_rows():
			row["seed"] = random_seed
			print("AI_SOAK_CHARACTER " + JSON.stringify(row))
	var line := JSON.stringify(result)
	print("AI_SOAK " + line)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__ai_soak = %s;" % line, true)
	elif quit_at_end and get_tree().current_scene == self:
		get_tree().quit(0 if broken.is_empty() else 1)


static func _mean(values: PackedFloat64Array) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / maxf(values.size(), 1.0)


static func _max(values: PackedFloat64Array) -> float:
	var most := 0.0
	for value in values:
		most = maxf(most, value)
	return most

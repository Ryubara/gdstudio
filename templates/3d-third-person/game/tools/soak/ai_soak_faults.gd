class_name AiSoakFaults
extends Node
## Breaks AI characters on purpose, one fault a character, so the soak's tests can prove that each
## gate of `AiSoakWatch` fails on the fault it is there for (kit #971). Each fault waits for a
## living hostile (to the player) whose state lets the fault show, takes it as its target and
## breaks it every tick from then on:
##
## - `ERROR`: one engine error, a second into the run;
## - `STUCK`: a hostile walking somewhere is held where it stands, and sent on again whenever its
##   navigator gives up (a body that cannot move while its mind keeps asking);
## - `IDLE`: a hostile that sees a hostile of its own has its tasks paused and its navigator and
##   controller let go, and keeps believing it sees the player (refreshed after its senses); it
##   cannot die until it has stood so for the watch's `idle_seconds` and `IDLE_HOLD_SLACK`, so the
##   pilot's shots (it shoots every hostile in its sight, and a still one is easy) cannot end the
##   stretch before the gate sees it, then it can;
## - `TASK_OVERDUE`: a hostile is given a task that never ends, with a hard timeout of
##   `overdue_timeout`, at the top layer, and its active task's clock is held at 0, so the timeout
##   never ends it;
## - `PATH_STORM`: a walking hostile's navigator has its query clock put back every tick (a path
##   asked at every step, the bug the query interval is there to stop);
## - `SLOW_THINK`: a hostile's every think is made `slow_think_usec` longer;
## - `POCKET`: a hostile cannot die, so the round it is in never ends;
## - `BELIEF`: a hostile believes, fully aware, in a wall of the level.
##
## It belongs to the soak (`ai_soak.tscn`), which turns faults on with `faults`; with none it
## does nothing.

enum Fault {
	ERROR = 1,
	STUCK = 2,
	IDLE = 4,
	TASK_OVERDUE = 8,
	PATH_STORM = 16,
	SLOW_THINK = 32,
	POCKET = 64,
	BELIEF = 128,
}

## The gate each fault must break.
const GATE_OF := {
	Fault.ERROR: &"error",
	Fault.STUCK: &"stuck_episode",
	Fault.IDLE: &"idle_with_threat",
	Fault.TASK_OVERDUE: &"task_overdue",
	Fault.PATH_STORM: &"path_storm",
	Fault.SLOW_THINK: &"think_p99",
	Fault.POCKET: &"round",
	Fault.BELIEF: &"belief",
}
## Seconds past the watch's `idle_seconds` an `IDLE` target is kept alive.
const IDLE_HOLD_SLACK := 1.0
## The names the command line takes (`--faults stuck,idle`).
const NAMES := {
	"error": Fault.ERROR,
	"stuck": Fault.STUCK,
	"idle": Fault.IDLE,
	"task_overdue": Fault.TASK_OVERDUE,
	"path_storm": Fault.PATH_STORM,
	"slow_think": Fault.SLOW_THINK,
	"pocket": Fault.POCKET,
	"belief": Fault.BELIEF,
}

## The faults on (flags of `Fault`).
@export_flags(
	"Error", "Stuck", "Idle", "Task overdue", "Path storm", "Slow think", "Pocket", "Belief"
)
var faults := 0
## Microseconds `SLOW_THINK` adds to each think of its target.
@export_range(0, 100000, 100, "suffix:us") var slow_think_usec := 6000
## The hard timeout, seconds, `TASK_OVERDUE` gives its target's tasks.
@export_range(0.5, 60.0, 0.5, "suffix:s") var overdue_timeout := 3.0
## The player the hostiles are hostile to.
@export var player: Player
## A node of the level a `BELIEF` target believes in (a wall).
@export var wall: Node3D
## The watch whose gates the faults break (its `idle_seconds` sets how long `IDLE` holds its
## target alive).
@export var watch: AiSoakWatch

## Each fault's target, once taken.
var targets: Dictionary[int, AiCharacter] = {}

var _clock := 0.0
var _error_told := false
var _pinned := Vector3.ZERO
var _stuck_turn := 0
## Seconds the `IDLE` target has stood broken and alive (its hold ends past the gate's window).
var _idle_held := 0.0
var _late := Late.new()


## A task that runs until it is taken off (the `TASK_OVERDUE` fault's).
class HoldTask:
	extends AiTask

	func update(_delta: float) -> Status:
		return Status.RUNNING


## Runs after the director and before the watch, so a belief the senses rewrote is set again.
class Late:
	extends Node
	var step := Callable()

	func _ready() -> void:
		process_physics_priority = 999

	func _physics_process(_delta: float) -> void:
		step.call()


## The flags of `names` (comma-separated `NAMES`); an unknown name is an error.
static func parse(names: String) -> int:
	var flags := 0
	for name_given in names.split(",", false):
		var key := name_given.strip_edges()
		if key == "all":
			for value: int in NAMES.values():
				flags |= value
		elif NAMES.has(key):
			flags |= NAMES[key]
		else:
			push_error("AiSoakFaults: no fault named %s (%s)" % [key, ", ".join(NAMES.keys())])
	return flags


## The name of each fault's target, for a report.
func target_names() -> Dictionary:
	var names := {}
	for fault: int in targets:
		var target := targets[fault]
		names[String(GATE_OF[fault])] = String(target.name) if is_instance_valid(target) else ""
	return names


func _ready() -> void:
	# Before the director steps (it is in the level, after this node's parent's first child).
	process_physics_priority = -1000
	_late.step = _after_senses
	add_child(_late)


func _notification(what: int) -> void:
	# A scene instanced and freed out of the tree never adds the late node: free it, or it is an
	# orphan (`test_physics_layers.gd` instances every scene).
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_late) and _late.get_parent() == null:
		_late.free()


func _after_senses() -> void:
	var target: AiCharacter = targets.get(Fault.IDLE)
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var senses := target.senses as AiSenses
	if senses == null or player == null or target.is_dead():
		return
	var belief := senses.beliefs.track(player, AiFactionMember.of(player))
	belief.band = AiRelations.Band.HOSTILE
	belief.time = senses.beliefs.clock
	belief.last_position = player.global_position
	belief.awareness = 1.0
	belief.noticed = true
	belief.believed = true
	belief.seen_now = true


func _physics_process(delta: float) -> void:
	if faults == 0:
		return
	_clock += delta
	if faults & Fault.ERROR and not _error_told and _clock >= 1.0:
		_error_told = true
		push_error("AiSoakFaults: the injected error")
	for fault: int in GATE_OF:
		if fault == Fault.ERROR or not faults & fault:
			continue
		var target: AiCharacter = targets.get(fault)
		if target == null or not is_instance_valid(target):
			target = _take_target(fault)
			if target == null:
				continue
		# A dead target, or one back in the pool, is broken again once it is spawned again.
		if target.is_inside_tree() and not target.is_dead():
			_break(fault, target, delta)


func _take_target(fault: int) -> AiCharacter:
	for node in get_tree().get_nodes_in_group(AiCharacter.GROUP):
		var character := node as AiCharacter
		if character == null or character.is_dead() or targets.values().has(character):
			continue
		if not _hostile(character) or not _shows(fault, character):
			continue
		targets[fault] = character
		_start(fault, character)
		return character
	return null


# True when `character` is in a state the fault can show in.
func _shows(fault: int, character: AiCharacter) -> bool:
	var navigator := character.navigator as AiNavigator
	match fault:
		Fault.STUCK:
			return navigator != null and navigator.is_active() and not navigator.is_arrived()
		Fault.IDLE:
			var mind := character.brain as AiBrain
			var threat: AiBelief = mind.call(&"_threat_in_view") if mind != null else null
			return threat != null and threat.band == AiRelations.Band.HOSTILE
		Fault.TASK_OVERDUE:
			var tasks := character.task_runner as AiTasks
			return tasks != null and tasks.runner.active != null
		Fault.PATH_STORM:
			return navigator != null and navigator.is_active() and not navigator.is_arrived()
	return true


func _start(fault: int, character: AiCharacter) -> void:
	match fault:
		Fault.STUCK:
			_pinned = character.global_position
		Fault.SLOW_THINK:
			character.thought.connect(_slow_think)
		Fault.IDLE:
			_idle_held = 0.0
			Health.of(character).invulnerable = true
		Fault.POCKET:
			Health.of(character).invulnerable = true


func _break(fault: int, character: AiCharacter, delta: float) -> void:
	match fault:
		Fault.STUCK:
			character.global_position = _pinned
			character.velocity = Vector3.ZERO
			var walker := character.navigator as AiNavigator
			if walker != null and (not walker.is_active() or walker.is_arrived()):
				_stuck_turn += 1
				var away := Vector3.FORWARD.rotated(Vector3.UP, _stuck_turn * PI / 2.0) * 5.0
				walker.go_to(_pinned + away)
		Fault.IDLE:
			var tasks := character.task_runner as AiTasks
			if tasks != null:
				tasks.runner.set_can_think(false)
			var navigator := character.navigator as AiNavigator
			if navigator != null and navigator.is_active():
				navigator.stop()
			if character.ai_controller() != null:
				character.ai_controller().release()
			_hold_idle(character, delta)
		Fault.TASK_OVERDUE:
			var runner := (character.task_runner as AiTasks).runner
			if not runner.active is HoldTask:
				var hold := HoldTask.new()
				hold.id = &"soak_hold"
				hold.layer = AiTask.Layer.REACTION
				hold.channels = 0
				hold.interruptible = AiTask.Interruptible.NO
				hold.hard_timeout = overdue_timeout
				runner.assign(hold, &"soak")
			if runner.active != null:
				runner.active.elapsed = 0.0
		Fault.PATH_STORM:
			var navigator := character.navigator as AiNavigator
			navigator.set(&"_since_query", INF)
			navigator.set(&"_want_query", true)
		Fault.POCKET:
			Health.of(character).invulnerable = true
		Fault.BELIEF:
			var senses := character.senses as AiSenses
			if senses != null and wall != null:
				var belief := senses.beliefs.track(wall)
				belief.time = senses.beliefs.clock
				belief.awareness = 1.0
				belief.noticed = true


# Keeps the `IDLE` target alive until the idle gate has had its window and a little more, then
# lets it die as any hostile does: a target the pilot shot first ended the stretch it had to show.
func _hold_idle(character: AiCharacter, delta: float) -> void:
	var health := Health.of(character)
	if health == null or not health.invulnerable:
		return
	_idle_held += delta
	var window := watch.idle_seconds if watch != null else 0.0
	if _idle_held > window + IDLE_HOLD_SLACK:
		health.invulnerable = false


func _slow_think(_seconds: float) -> void:
	OS.delay_usec(slow_think_usec)


func _hostile(character: AiCharacter) -> bool:
	var factions := AiFactions.find(character)
	var me := AiFactionMember.of(player) if player != null else null
	var them := AiFactionMember.of(character)
	if factions == null or me == null or them == null:
		return false
	return factions.band_of_members(me, them) == AiRelations.Band.HOSTILE

class_name AiBrain
extends Node
## The part that makes an AI character do something: the `Brain` child of `ai_character.tscn`,
## set as the character's `brain` slot. It turns what happens to the character into tasks through
## its `behaviour` (an `AiBehaviourSet`, the router's table) and keeps its play state.
##
## - **Events, not polling.** The senses' signals (`entity_noticed`, `suspicious`, `heard`,
##   `entity_lost`), a hit, a task that failed for a reason the table answers (a target lost, a dry
##   gun), the navigator reaching a link it does not cross itself, the play state turning Safe, the
##   start, and a script's orders (`order()`) are each routed once through the table: the first row
##   that matches the band toward the subject, the situation and the play state places a copy of
##   its task and may move the situation. The brain has no branch for any behaviour.
## - **The play state** (`play`, an `AiPlayState`) is fed each think from the health share and the
##   hostiles seen now; turning Safe with a hostile in view is the `hurt` event, and a Safe
##   character's roaming tasks (a patrol, a wander) do not run.
## - **One reminder.** While a hostile is seen and the running task does not answer a threat, the
##   noticed event is routed again every `threat_recheck_seconds`, so a character never stands
##   idle with a threat in view (a response refused inside the commit time is asked again).
## - **Three choices are scored** (`AiChoice`, with a commitment bonus): the target here, the cover
##   spot in `TakeCover` and the next marker in `Patrol`.
##
## It runs where the senses do (`authority_only`): on a client of a remote server it does nothing,
## and only the situation and the active task's id and target leave the server. Barks (`barked`)
## and reactions (`reacted`) are signals for the character's own sound and animation, never sent.
##
## Docs: the kit's `docs/engines/godot/third-person/ai-behaviour.md`.

## An event was routed and a row answered it (`task` is the instance placed, or null when the row
## only moved the situation or the runner refused it).
signal reacted(event: StringName, row: AiReactionRow, task: AiTask)
## A bark passed its cooldowns: the character's sound and subtitles play it (never sent).
signal barked(line: StringName)
## The play state changed (`AiPlayState.State`).
signal play_state_changed(state: int, previous: int)

## Who placed the tasks the brain hands out (`AiTask.issuer`).
const ISSUER := &"brain"

static var _crowd_said: Dictionary[StringName, float] = {}

## How this kind answers what happens to it. Empty: the brain does nothing (one check a think).
@export var behaviour: AiBehaviourSet
## Whom it follows and returns to (an ally's player); empty: nobody.
@export var leader: Node3D
## The patrol route its `Patrol` walks (`AiMarker.route`); empty: any patrol marker.
@export var patrol_route := &""
## How far from home a `Wander` or a `Guard` goes.
@export_range(0.0, 100.0, 0.5, "suffix:m") var home_radius := 6.0
## The seed of its rolls (a row's chance, a wander's points); 0 takes one from the character's
## name, so the same scene gives the same choices.
@export var random_seed := 0

@export_group("Threats")
## Seconds between two reminders of a hostile in view that nothing answers.
@export_range(0.1, 10.0, 0.05, "suffix:s") var threat_recheck_seconds := 1.0
## The score a target already chosen keeps over the others (its commitment).
@export_range(0.0, 5.0, 0.05) var target_bonus := 0.3
## The least friendly band the reminder counts as a threat: Hostile for a fighter (a civilian in
## view is watched once, not every second), Unfriendly for a civilian (an enemy is a threat to it).
@export var remind_up_to := AiRelations.Band.HOSTILE
## Seconds an answer the runner did not place (a response inside another's commit time) is asked
## again, at each think.
@export_range(0.0, 5.0, 0.05, "suffix:s") var retry_seconds := 1.0

@export_group("Barks")
## Seconds before the same line again from this character.
@export_range(0.0, 120.0, 0.5, "suffix:s") var line_cooldown := 8.0
## Seconds before any line again from this character.
@export_range(0.0, 60.0, 0.1, "suffix:s") var any_line_cooldown := 2.5
## Seconds before the same line again from anybody (a crowd that all saw one thing shouts once).
@export_range(0.0, 60.0, 0.1, "suffix:s") var crowd_cooldown := 1.5

@export_group("Network")
## Runs only where the game's authority runs (as the senses do).
@export var authority_only := true

## How boldly it plays now.
var play := AiPlayState.new()
## Where it started (a `Wander`'s and a `Guard`'s centre, `Place.HOME`).
var home := Vector3.ZERO
## What the last answer was about, and where (a composite's steps read them).
var focus: Node3D = null
var focus_point := Vector3.ZERO
## The target it chose last (the commitment of the target choice).
var target: Node3D = null
## The last event routed and how it was answered, for the overlay and the decision log.
var last_event := &""
var last_answer := ""
## Events routed (a test counts them).
var routed := 0
## Where the link the navigator stopped at starts (a `TraverseLink` reads it).
var link_from := Vector3.ZERO

var _character: AiCharacter
var _rng := RandomNumberGenerator.new()
var _since_reminder := 0.0
var _said: Dictionary[StringName, float] = {}
var _said_any := -INF
var _started := false
var _retry: Array = []
var _retry_left := 0.0
var _retrying := false


## True when `task` (or a step of it, for a composite) answers a threat.
static func answers_threat(task: AiTask) -> bool:
	if task is AiStockTask:
		return (task as AiStockTask).answers_threat
	if task is AiTaskComposite:
		for child in (task as AiTaskComposite).children:
			if child != null and answers_threat(child):
				return true
	return false


## The brain of `node` (an `AiCharacter`), or null.
static func of(node: Node) -> AiBrain:
	var character := node as AiCharacter
	return character.brain as AiBrain if character != null else null


func _ready() -> void:
	_character = get_parent() as AiCharacter
	if _character == null:
		return
	_rng.seed = random_seed if random_seed != 0 else hash(String(_character.name))
	play.changed.connect(_on_play_changed)
	var senses := _character.senses as AiSenses
	if senses != null:
		senses.entity_noticed.connect(_on_noticed)
		senses.suspicious.connect(_on_suspicious)
		senses.entity_lost.connect(_on_lost)
		senses.heard.connect(_on_heard)
	_character.took_hit.connect(_on_took_hit)
	_character.revived.connect(play.reset)
	var tasks := _character.task_runner as AiTasks
	if tasks != null:
		tasks.runner.task_failed.connect(_on_task_failed)
		tasks.runner.task_finished.connect(_on_task_finished)
	var navigator := _character.navigator as AiNavigator
	if navigator != null:
		navigator.link_reached.connect(_on_link_reached)


## Starts over as a new character (a pooled body spawned again): the play state, the target, the
## retries and the reminder are forgotten, and the next think starts it again where it stands then
## (its home, the default task, the `spawned` event).
func restart() -> void:
	_started = false
	play.reset()
	target = null
	focus = null
	focus_point = Vector3.ZERO
	last_event = &""
	last_answer = ""
	_retry = []
	_retry_left = 0.0
	_since_reminder = 0.0
	_said.clear()
	_said_any = -INF


## The task runner it places tasks in, or null.
func runner() -> AiTaskRunner:
	var tasks := _character.task_runner as AiTasks if _character != null else null
	return tasks.runner if tasks != null else null


## The character's beliefs, or null.
func beliefs() -> AiBeliefs:
	var senses := _character.senses as AiSenses if _character != null else null
	return senses.beliefs if senses != null else null


## One think, after the senses and before the tasks step: the start (once), the situation's alert
## hold, the play state and the reminder.
func think(seconds: float) -> void:
	if behaviour == null or not _runs():
		return
	if not _started:
		_start()
	var profile := _character.profile
	_character.situation.alert_hold = profile.alert_hold_seconds
	if _character.is_dead():
		return
	var most := _character.max_health
	var share := _character.health / most if most > 0.0 else 1.0
	play.feed(share, _hostiles_seen(), seconds, profile)
	if not _retry.is_empty():
		_retry_left -= seconds
		var again := _retry
		_retry = []
		if _retry_left > 0.0 and (again[1] == null or is_instance_valid(again[1])):
			_retrying = true
			route(again[0], again[1], again[2], again[3], again[4], again[5])
			_retrying = false
	_since_reminder += seconds
	if _since_reminder >= threat_recheck_seconds:
		_remind()


## Routes `event` about `subject` at `place` through the table and returns the task placed, or
## null. `band` is the character's band toward the subject (-1: looked up; a subject-less event
## is Neutral); `noise` the kind of a heard noise (a row may answer only a shot).
func route(
	event: StringName, subject: Node3D, place: Vector3, awareness := 1.0, band := -1, noise := &""
) -> AiTask:
	if behaviour == null or not _runs() or _character.is_dead():
		return null
	if band < 0:
		band = _band_of(subject)
	var situation := _character.situation.current
	if situation == AiSituation.Situation.DEAD:
		return null
	routed += 1
	last_event = event
	if behaviour.blocks(situation, event):
		last_answer = "blocked"
		return null
	var row := behaviour.pick(
		event, band, situation, play.current, awareness, _character.profile, _rng.randf, noise
	)
	if row == null:
		last_answer = "nothing"
		return null
	if row.enter > 0:
		_character.situation.request((row.enter - 1) as AiSituation.Situation)
	var placed: AiTask = null
	var at := runner()
	if row.task != null and at != null:
		if behaviour.layer_open(_character.situation.current, row.task.layer):
			var task := row.task.fresh_copy()
			task.target = subject
			task.goal = _place_of(row.place, place)
			_hand_down(task)
			focus = subject
			focus_point = task.goal
			placed = at.assign(task, ISSUER)
			if placed == null:
				_keep_for_retry([event, subject, place, awareness, band, noise])
	last_answer = row.task.display_label() if row.task != null else "situation"
	reacted.emit(event, row, placed)
	_show()
	return placed


## A script asks it to go to `point` (`order_go`), hold `point` (`order_hold`) or use `object`
## (`order_use`): routed through the table like any event, so each kind answers its own way.
func order(event: StringName, point: Vector3, object: Node3D = null) -> AiTask:
	return route(event, object, point, 1.0, AiRelations.Band.NEUTRAL)


## Says `line` when its cooldowns allow (this line, any line, anybody's same line): emits
## `barked` and returns true.
func say(line: StringName) -> bool:
	var now := _now()
	if now - _said_any < any_line_cooldown:
		return false
	if now - float(_said.get(line, -INF)) < line_cooldown:
		return false
	if now - float(_crowd_said.get(line, -INF)) < crowd_cooldown:
		return false
	_said_any = now
	_said[line] = now
	_crowd_said[line] = now
	barked.emit(line)
	return true


## The hostile to fight: among those believed and seen now, the nearest (an attacker counts as
## nearer), the one chosen last keeping `target_bonus`. Null when none.
func choose_target() -> Node3D:
	var known := beliefs()
	if known == null:
		return null
	var ids: Array = []
	var scores := PackedFloat32Array()
	var bodies: Array[Node3D] = []
	var at := _character.global_position
	var reach := maxf(_character.profile.engage_range, 1.0)
	var tasks := runner()
	var attacker: Variant = tasks.beliefs.get(&"attacker") if tasks != null else null
	for belief: AiBelief in known.by_id.values():
		if not belief.can_fire_at() or belief.band != AiRelations.Band.HOSTILE:
			continue
		var body := belief.entity()
		var score := 1.0 - at.distance_to(belief.last_position) / reach
		if is_instance_valid(attacker) and body == attacker:
			score += 0.5
		ids.append(belief.entity_id)
		scores.append(score)
		bodies.append(body)
	var kept: Variant = target.get_instance_id() if is_instance_valid(target) else null
	var index := AiChoice.best(ids, scores, kept, target_bonus)
	target = bodies[index] if index >= 0 else null
	return target


## The overlay's line: the play state and the last event and answer.
func debug_text() -> String:
	var line := AiPlayState.name_of(play.current)
	if last_event != &"":
		line += " · %s: %s" % [last_event, last_answer]
	return line


func _start() -> void:
	_started = true
	home = _character.global_position
	var at := runner()
	if behaviour.default_task != null and at != null:
		var task := behaviour.default_task.fresh_copy()
		task.goal = home
		at.assign(task, ISSUER)
	route(AiBehaviourSet.SPAWNED, leader, home)


func _remind() -> void:
	_since_reminder = 0.0
	var at := runner()
	if at == null:
		return
	if at.active != null and not at.active.is_done() and AiBrain.answers_threat(at.active):
		return
	var belief := _threat_in_view()
	if belief == null:
		return
	route(
		AiBehaviourSet.NOTICED, belief.entity(), belief.last_position, belief.awareness, belief.band
	)


# The nearest thing believed, in view and at most `remind_up_to` (the fight's target first).
func _threat_in_view() -> AiBelief:
	var fight := choose_target()
	var known := beliefs()
	if fight != null:
		return known.of(fight)
	var best: AiBelief = null
	var nearest := INF
	var at := _character.global_position
	for belief: AiBelief in known.by_id.values():
		if not belief.can_fire_at() or belief.band > remind_up_to:
			continue
		var far := at.distance_squared_to(belief.last_position)
		if far < nearest:
			nearest = far
			best = belief
	return best


# An answer the runner did not place is asked again at the next thinks, for `retry_seconds`.
func _keep_for_retry(asked: Array) -> void:
	if not _retrying:
		_retry_left = retry_seconds
	_retry = asked


func _hostiles_seen() -> int:
	var known := beliefs()
	if known == null:
		return 0
	var count := 0
	for belief: AiBelief in known.by_id.values():
		if belief.seen_now and belief.believed and belief.band == AiRelations.Band.HOSTILE:
			count += 1
	return count


func _band_of(subject: Node3D) -> int:
	if subject == null:
		return AiRelations.Band.NEUTRAL
	var me := AiFactionMember.of(_character)
	var it := AiFactionMember.of(subject)
	if me == null or it == null:
		return AiRelations.Band.NEUTRAL
	var factions := me.level()
	if factions == null or factions.relations == null:
		return AiRelations.Band.NEUTRAL
	return factions.band_of_members(me, it)


func _place_of(place: AiReactionRow.Place, event_place: Vector3) -> Vector3:
	match place:
		AiReactionRow.Place.HOME:
			return home
		AiReactionRow.Place.LEADER:
			return leader.global_position if is_instance_valid(leader) else home
	return event_place


# A composite's steps get the answer's target and goal (a step that set its own keeps it).
func _hand_down(task: AiTask) -> void:
	var composite := task as AiTaskComposite
	if composite == null:
		return
	for child in composite.children:
		if child == null:
			continue
		if child.target == null:
			child.target = task.target
		if child.goal == Vector3.ZERO:
			child.goal = task.goal
		_hand_down(child)


func _runs() -> bool:
	return _character != null and (not authority_only or AiNoise.runs_here())


func _now() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)


func _show() -> void:
	if _character != null and _character.debug:
		_character.refresh_debug()


func _on_noticed(entity: Node3D, belief: AiBelief) -> void:
	route(AiBehaviourSet.NOTICED, entity, belief.last_position, belief.awareness, belief.band)


func _on_suspicious(entity: Node3D, belief: AiBelief) -> void:
	route(AiBehaviourSet.SUSPICIOUS, entity, belief.last_position, belief.awareness, belief.band)


func _on_lost(_entity_id: int, belief: AiBelief) -> void:
	route(AiBehaviourSet.FORGOT, belief.entity(), belief.last_position, 0.0, belief.band)


func _on_heard(kind: StringName, position: Vector3, source: Node3D) -> void:
	# A noise with no known source is "something": Hostile, as the senses treat it.
	var band := AiRelations.Band.HOSTILE if source == null else _band_of(source)
	route(AiBehaviourSet.HEARD, source, position, 0.5, band, kind)


func _on_took_hit(_amount: float, source: Node3D) -> void:
	if source == null or source == _character:
		return
	route(AiBehaviourSet.HIT, source, source.global_position, 1.0)


func _on_task_failed(task: AiTask, reason: AiTask.Reason) -> void:
	var stock := task as AiStockTask
	if stock == null or task.issuer != ISSUER:
		return
	var event := stock.event_for(reason)
	if event == &"":
		return
	var subject := task.target as Node3D if is_instance_valid(task.target) else null
	var known := beliefs()
	var belief := known.of(subject) if known != null and subject != null else null
	var place := belief.last_position if belief != null else stock.last_known
	route(event, subject, place)


func _on_task_finished(task: AiTask, _state: AiTask.State) -> void:
	var stock := task as AiStockTask
	if stock != null and stock.found:
		stock.found = false
		_remind()


func _on_link_reached(_link: Node, from: Vector3, to: Vector3) -> void:
	var navigator := _character.navigator as AiNavigator
	if navigator == null or navigator.auto_traverse_links:
		return
	link_from = from
	route(AiBehaviourSet.LINK, null, to)


func _on_play_changed(now: AiPlayState.State, previous: AiPlayState.State) -> void:
	play_state_changed.emit(now, previous)
	# Turning Safe with a hostile in view is the `hurt` event; with none it only stops roaming.
	var threat := choose_target() if now == AiPlayState.State.SAFE else null
	if threat != null:
		route(AiBehaviourSet.HURT, threat, beliefs().of(threat).last_position)
	_show()

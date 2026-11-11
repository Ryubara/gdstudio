extends Node
## What the relationship lookups cost: 200 entities (a `Node3D` each with an `AiFactionMember`,
## the four shipped factions in turn, a personal grudge on every tenth) and the level's
## `AiFactions` with the shipped `ai_relations.tres`, asked 8 lookups an entity: one round is
## 1600 lookups, what 200 characters each looking at 8 others in one think would ask.
##
## `index_us`: a round of `AiRelations.band_at(i, j)` (faction indexes already known).
## `members_us`: a round of `AiFactions.is_hostile_members(a, b)` (the members already in hand, as
## the senses keep them: a grudge check, two cached indexes, the band). `between_us`:
## a round of `AiFactions.is_hostile_between(a, b)` (the member, a grudge check, the band).
## `can_hurt_us`: a round of `AiFactions.can_hurt(a, b)` (which also finds the node in the tree).
## Each is the mean of `ROUNDS` rounds; `ns` columns are one lookup.
##
## Run it headless on the desktop:
## `godot --headless --path game res://tools/bench/ai_relations_bench.tscn`
## and in a browser from a web export with this scene as `run/main_scene` and `tools/*` taken out
## of the preset's exclude filter (`tools/bench/ai_relations_bench.py`). It prints one line of JSON
## that starts with `AI_RELATIONS_BENCH` and, on the web, puts it in `window.__ai_relations_bench`.

const ENTITIES := 200
const LOOKS := 8
const ROUNDS := 200
const WARM_ROUNDS := 20
const RELATIONS := "res://gameplay/ai/relations/ai_relations.tres"
const SIDES: Array[StringName] = [&"player", &"enemy", &"ally", &"civilian"]

var _entities: Array[Node3D] = []
var _indexes := PackedInt32Array()
var _members: Array[AiFactionMember] = []
var _factions: AiFactions


func _ready() -> void:
	_factions = AiFactions.new()
	_factions.relations = load(RELATIONS) as AiRelations
	add_child(_factions)
	for at in ENTITIES:
		var entity := Node3D.new()
		var member := AiFactionMember.new()
		member.faction = SIDES[at % SIDES.size()]
		entity.add_child(member)
		add_child(entity)
		_entities.append(entity)
		_indexes.append(_factions.relations.index_of(member.faction))
		_members.append(member)
	for at in range(0, ENTITIES, 10):
		AiFactionMember.of(_entities[at]).grudge(_entities[(at + 1) % ENTITIES], -90.0)
	_run.call_deferred()


func _run() -> void:
	await get_tree().physics_frame
	var row := {"entities": ENTITIES, "lookups_a_round": ENTITIES * LOOKS}
	row["index_us"] = _time(_round_index)
	row["members_us"] = _time(_round_members)
	row["between_us"] = _time(_round_between)
	row["can_hurt_us"] = _time(_round_can_hurt)
	for key in ["index", "members", "between", "can_hurt"]:
		row[key + "_ns"] = row[key + "_us"] * 1000.0 / (ENTITIES * LOOKS)
	var line := JSON.stringify(row)
	print("AI_RELATIONS_BENCH ", line)
	# On the web the page stays up: a quit there tears the audio worklet down and the page logs
	# an error.
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__ai_relations_bench = %s;" % line, true)
		return
	get_tree().quit()


func _time(round_of: Callable) -> float:
	for _i in WARM_ROUNDS:
		round_of.call()
	var started := Time.get_ticks_usec()
	for _i in ROUNDS:
		round_of.call()
	return float(Time.get_ticks_usec() - started) / ROUNDS


func _round_index() -> int:
	var relations := _factions.relations
	var hostile := 0
	for a in ENTITIES:
		var i := _indexes[a]
		for look in LOOKS:
			if relations.band_at(i, _indexes[(a + look + 1) % ENTITIES]) == 0:
				hostile += 1
	return hostile


func _round_members() -> int:
	var hostile := 0
	for a in ENTITIES:
		var member := _members[a]
		for look in LOOKS:
			if _factions.is_hostile_members(member, _members[(a + look + 1) % ENTITIES]):
				hostile += 1
	return hostile


func _round_between() -> int:
	var hostile := 0
	for a in ENTITIES:
		var entity := _entities[a]
		for look in LOOKS:
			if _factions.is_hostile_between(entity, _entities[(a + look + 1) % ENTITIES]):
				hostile += 1
	return hostile


func _round_can_hurt() -> int:
	var allowed := 0
	for a in ENTITIES:
		var entity := _entities[a]
		for look in LOOKS:
			if AiFactions.can_hurt(entity, _entities[(a + look + 1) % ENTITIES]):
				allowed += 1
	return allowed

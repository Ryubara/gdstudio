@tool
class_name AiFactions
extends Node
## The level's relationships: plays a copy of the game's `AiRelations` (so a match never writes
## the file), answers who is hostile to whom between two entities (a personal grudge first, then
## the factions), turns reported acts into attitude changes for the factions that perceived them,
## lets the current values drift back to their base, and colours characters by band toward the
## player when `show_bands` is on.
##
## The senses filter by `is_hostile_between`, the weapon refuses a hit through `can_hurt`
## (`HitZones.deliver`), and an AI's fire decision asks `can_hurt` before it pulls the trigger.
## Without an `AiFactions` in the tree everyone may hurt everyone and nobody is hostile.

## The group the node joins, which `find` reads.
const GROUP := &"ai_factions"

## The relationships the level plays: a copy is made when the game starts, so an edit here (or in
## the remote inspector) applies to this match only.
@export var relations: AiRelations:
	set(value):
		relations = value
		update_configuration_warnings()

@export_group("Debug")
## Colours every member's band ring by how it feels about the player (red Hostile to blue Allied).
@export var show_bands := false:
	set(value):
		show_bands = value
		if is_node_ready() and not Engine.is_editor_hint():
			_paint_bands()
## Seconds between repaints of the band rings while `show_bands` is on.
@export_range(0.05, 5.0, 0.05, "suffix:s") var band_refresh_seconds := 0.25
## The ring colour of each band, from Hostile to Allied.
@export var band_colors := PackedColorArray(
	[
		Color(0.9, 0.15, 0.1),
		Color(0.95, 0.55, 0.1),
		Color(0.85, 0.85, 0.8),
		Color(0.35, 0.85, 0.3),
		Color(0.2, 0.55, 1.0),
	]
)
## The group whose first member the bands are measured toward.
@export var player_group := &"player"

## Who perceived an act: `func(actor: Node, victim: Node) -> Array` (the senses set it). Unset:
## the victim alone, which feels a blow on itself.
var witness_source: Callable

var _since_paint := 0.0


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group(GROUP)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if relations != null:
		relations = relations.copy()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or relations == null:
		return
	relations.recover(delta)
	if show_bands:
		_since_paint += delta
		if _since_paint >= band_refresh_seconds:
			_paint_bands()


## The level's `AiFactions` (the first of the group in `node`'s tree), or null.
static func find(node: Node) -> AiFactions:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group(GROUP) as AiFactions


## False when `attacker` must not hurt `victim`: it is Friendly or Allied toward the victim and its
## faction does not hurt friends. True with no `AiFactions` in the tree, for itself, or for a
## victim or attacker in no faction.
static func can_hurt(attacker: Node, victim: Node) -> bool:
	if attacker == null or victim == null or attacker == victim:
		return true
	var factions := find(victim)
	if factions == null or factions.relations == null:
		return true
	var attacker_faction := AiFactionMember.faction_of(attacker)
	if attacker_faction == &"" or AiFactionMember.faction_of(victim) == &"":
		return true
	if factions.band_between(attacker, victim) < AiRelations.Band.FRIENDLY:
		return true
	var side := factions.relations.faction(attacker_faction)
	return side == null or side.hurts_friends


## How `a` feels about `b`: its personal grudge toward `b` when it holds one, else its faction's
## toward `b`'s.
func attitude_between(a: Node, b: Node) -> float:
	var member := AiFactionMember.of(a)
	if member != null and member.has_grudge(b):
		return member.grudge_toward(b)
	if relations == null:
		return 0.0
	return relations.attitude(AiFactionMember.faction_of(a), AiFactionMember.faction_of(b))


## The band of `a` toward `b` (`AiRelations.Band`): a grudge's by its value, else the factions'.
func band_between(a: Node, b: Node) -> int:
	var member := AiFactionMember.of(a)
	if relations == null:
		return AiRelations.Band.NEUTRAL
	if member != null and member.has_grudge(b):
		return relations.band_of(member.grudge_toward(b))
	return relations.band(AiFactionMember.faction_of(a), AiFactionMember.faction_of(b))


## True when `a` is Hostile toward `b`: the filter the senses read first.
func is_hostile_between(a: Node, b: Node) -> bool:
	return band_between(a, b) == AiRelations.Band.HOSTILE


## Reports that `actor` did `event` (an id of the table's events: `attack`, `kill`, `help`,
## `trespass`) to `victim`. Each faction among the `witnesses` (or `witness_source`'s, or the
## victim alone) that is not Hostile toward the victim moves its attitude toward the actor's
## faction by the event's delta, once however many of its members saw it. An `ALWAYS` event moves
## the victim's faction. Returns how many factions changed.
func report(event_id: StringName, actor: Node, victim: Node, witnesses: Array = []) -> int:
	if relations == null or actor == null:
		return 0
	var event := relations.event(event_id)
	if event == null:
		push_warning("AiFactions: no event %s in the table" % event_id)
		return 0
	var actor_faction := AiFactionMember.faction_of(actor)
	var victim_faction := AiFactionMember.faction_of(victim)
	if actor_faction == &"":
		return 0
	var sides: Array[StringName] = []
	if event.witness == AiRelationEvent.Witness.ALWAYS:
		sides.append(victim_faction)
	else:
		for witness in _witnesses(actor, victim, witnesses):
			var side := AiFactionMember.faction_of(witness)
			if witness != actor and side != &"" and not sides.has(side):
				sides.append(side)
	var changed := 0
	for side in sides:
		if victim_faction != &"" and relations.is_hostile(side, victim_faction):
			continue
		if relations.add_attitude(side, actor_faction, event.delta, 1):
			changed += 1
	return changed


func _witnesses(actor: Node, victim: Node, given: Array) -> Array:
	if not given.is_empty():
		return given
	if witness_source.is_valid():
		return witness_source.call(actor, victim)
	return [victim] if victim != null else []


# Colours each member's ring by its band toward the player; hides them all when off.
func _paint_bands() -> void:
	_since_paint = 0.0
	var viewer := get_tree().get_first_node_in_group(player_group)
	for node in get_tree().get_nodes_in_group(AiCharacter.GROUP):
		var member := AiFactionMember.of(node)
		if member == null:
			continue
		if not show_bands or viewer == null:
			member.show_band(false)
			continue
		var at := band_between(node, viewer)
		member.show_band(true, band_colors[at] if at < band_colors.size() else Color.WHITE)


func _get_configuration_warnings() -> PackedStringArray:
	if relations == null:
		return PackedStringArray(
			["No relations: nobody is hostile and everyone may hurt everyone."]
		)
	return PackedStringArray()

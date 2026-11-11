@tool
class_name AiFactionMember
extends Node
## Puts its parent (a character, the player, a guarded zone) in a faction of the level's
## `AiRelations`, holds its personal grudges, and reports what is done to it: a hit on the parent
## is an `attack` by the hit's source, a death a `kill`, each witnessed by the parent itself
## (senses add the characters that saw it: `AiFactions.witness_source`).
##
## `AiFactionMember.of(node)` finds the member of a node; `AiFactions` reads it for every lookup.

## The meta key on the parent that points at its member.
const META := &"ai_faction_member"

## The faction the parent is in; empty: the parent's `AiProfile.faction` (an `AiCharacter`).
@export var faction := &"":
	set(value):
		faction = value
		table_version = -1
		update_configuration_warnings()
## Reports hits on the parent and its death to the level's `AiFactions`.
@export var reports_events := true
## The ring the debug overlay colours by band toward the player (`AiFactions.show_bands`).
@export var band_marker: GeometryInstance3D

## The parent's instance id, the key of other members' grudges toward it.
var entity_id := 0
## Its faction's index in the table of `table_version` (`refresh`), read by the hot path.
var faction_index := -1
## The `AiRelations.version` `faction_index` was read from; -1 makes the next lookup read it.
var table_version := -1
## True while it holds any grudge, so the hot path skips the grudge lookup otherwise.
var holds_grudges := false

var _grudges: Dictionary[int, float] = {}
var _last_attacker: WeakRef
var _ai: AiCharacter
var _level: AiFactions


func _enter_tree() -> void:
	var parent := get_parent()
	if parent != null:
		parent.set_meta(META, self)
		entity_id = parent.get_instance_id()
		_ai = parent as AiCharacter


func _exit_tree() -> void:
	if get_parent() != null and get_parent().get_meta(META, null) == self:
		get_parent().remove_meta(META)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var parent := get_parent()
	if parent.has_signal(&"took_hit"):
		parent.connect(&"took_hit", _on_took_hit)
	if parent.has_signal(&"died"):
		parent.connect(&"died", _on_died)
	if parent.has_signal(&"revived"):
		parent.connect(&"revived", _on_revived)
	if parent.has_signal(&"thought"):
		parent.connect(&"thought", _on_thought)
	show_band(false)


## The member of `node`, or null.
static func of(node: Object) -> AiFactionMember:
	if node == null or not node.has_meta(META):
		return null
	var found: Variant = node.get_meta(META)
	return found as AiFactionMember if is_instance_valid(found) else null


## The faction of `node`: its member's, else its `AiProfile`'s, else empty (in no faction).
static func faction_of(node: Object) -> StringName:
	var member := of(node)
	if member != null:
		return member.faction_id()
	var ai := node as AiCharacter
	if ai != null and ai.profile != null:
		return ai.profile.faction
	return &""


## The faction this member is in now (read live: a profile edit applies at once).
func faction_id() -> StringName:
	if faction != &"":
		return faction
	if _ai != null and _ai.profile != null:
		return _ai.profile.faction
	return &""


## The level's `AiFactions`, found once and kept while it is in the tree; null without one.
func level() -> AiFactions:
	if _level == null or not is_instance_valid(_level) or not _level.is_inside_tree():
		_level = AiFactions.find(self)
	return _level


## Reads its faction's index in `table` again (`faction_index`). The hot path calls it when the
## table was built again; a think calls it too, so a profile's faction edited live applies at the
## character's next think.
func refresh(table: AiRelations) -> int:
	faction_index = table.index_of(faction_id())
	table_version = table.version
	return faction_index


## Holds a personal attitude toward one entity that beats the faction's (-100 to 100).
func grudge(entity: Object, value: float) -> void:
	if entity != null:
		_grudges[entity.get_instance_id()] = clampf(value, -AiRelations.LIMIT, AiRelations.LIMIT)
		holds_grudges = true


## Drops the personal attitude toward `entity`: the faction's applies again.
func forgive(entity: Object) -> void:
	if entity != null:
		_grudges.erase(entity.get_instance_id())
		holds_grudges = not _grudges.is_empty()


## Drops every personal grudge (a pooled character spawned again as a new one).
func forgive_all() -> void:
	_grudges.clear()
	holds_grudges = false


## True when it holds a personal attitude toward `entity`.
func has_grudge(entity: Object) -> bool:
	return entity != null and _grudges.has(entity.get_instance_id())


## The personal attitude toward `entity` (`has_grudge` first).
func grudge_toward(entity: Object) -> float:
	return _grudges.get(entity.get_instance_id(), 0.0)


## The personal attitude toward the entity with instance id `id`, or NAN when it holds none.
func grudge_by_id(id: int) -> float:
	return _grudges.get(id, NAN)


## Shows the band ring in `color`, or hides it (the debug overlay).
func show_band(visible_now: bool, color := Color.WHITE) -> void:
	if band_marker == null:
		return
	band_marker.visible = visible_now
	if not visible_now:
		return
	var material := band_marker.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = color


func _on_took_hit(_amount: float, source: Node3D) -> void:
	if source == null or source == get_parent():
		return
	_last_attacker = weakref(source)
	if reports_events:
		var factions := level()
		if factions != null:
			factions.report(&"attack", source, get_parent())


func _on_died() -> void:
	var attacker: Object = _last_attacker.get_ref() if _last_attacker != null else null
	if attacker != null and reports_events:
		var factions := level()
		if factions != null:
			factions.report(&"kill", attacker as Node, get_parent())
	_last_attacker = null


func _on_thought(_seconds: float) -> void:
	table_version = -1


func _on_revived() -> void:
	_last_attacker = null


func _get_configuration_warnings() -> PackedStringArray:
	if faction == &"" and not get_parent() is AiCharacter:
		return PackedStringArray(["No faction: set one (an AiCharacter takes its profile's)."])
	return PackedStringArray()

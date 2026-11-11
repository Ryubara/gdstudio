class_name SensesArena
extends AiArena
## The AI arena with what the senses read: the shipped relationships (`AiFactions`), a noise
## board (`AiNoise`) and the director, plus plain targets (a `Node3D` with a faction member in a
## group the senses look at) that a test moves by hand. Free it with `auto_free`.

const RELATIONS := "res://gameplay/ai/relations/ai_relations.tres"

var factions: AiFactions
var board: AiNoise


func _init() -> void:
	super()
	factions = AiFactions.new()
	factions.name = "AiFactions"
	factions.relations = load(RELATIONS) as AiRelations
	add_child(factions)
	board = AiNoise.new()
	board.name = "AiNoise"
	add_child(board)


## A target named `target_name` at `spot` (its feet), in `faction` and the group `group`.
func add_target(
	target_name: String, spot: Vector3, faction := &"player", group := &"player"
) -> Node3D:
	var body := Node3D.new()
	body.name = target_name
	body.position = spot
	body.add_to_group(group)
	var member := AiFactionMember.new()
	member.faction = faction
	body.add_child(member)
	add_child(body)
	return body


## An AI character named `character_name` at `spot` facing `heading` (radians: 0 looks along +Z,
## PI along -Z), with a copy of `profile` (the grunt's when null).
func add_watcher(
	character_name: String, spot: Vector3, heading: float, profile: AiProfile = null
) -> AiCharacter:
	var character := add_character(spot, profile)
	character.name = character_name
	character.teleport(spot, heading)
	return character


## A wall across x from `left` to `right` at z `at`, 3 m high and 0.4 m thick.
func add_wall(left: float, right: float, at: float) -> StaticBody3D:
	return add_block(Vector2((left + right) * 0.5, at), Vector3(absf(right - left), 3.0, 0.4), 3.0)

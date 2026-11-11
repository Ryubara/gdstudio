class_name BehaviourArena
extends NavArena
## A `NavArena` with what an AI brain reads: the shipped relationships (`AiFactions`), a noise
## board (`AiNoise`), the director, and helpers to place the three shipped kinds (`ai_guard.tscn`,
## `ai_ally.tscn`, `ai_civilian.tscn`), plain targets a test moves by hand, real bodies in a faction
## with no brain (to be hit), and `AiMarker`s. Call `build()` and `settle()` after the walls. Free
## it with `auto_free`.

const GUARD := "res://gameplay/ai/ai_guard.tscn"
const ALLY := "res://gameplay/ai/ai_ally.tscn"
const CIVILIAN := "res://gameplay/ai/ai_civilian.tscn"
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
	AiSensePool.forget()


## A character of the scene at `scene_path` at `spot` facing `heading` (0 looks along +Z, PI along
## -Z), with a copy of its profile with `changes` (property to value) applied.
func add_kind(scene_path: String, spot: Vector3, heading := 0.0, changes := {}) -> AiCharacter:
	var character := (load(scene_path) as PackedScene).instantiate() as AiCharacter
	character.profile = character.profile.duplicate() as AiProfile
	for key: String in changes:
		character.profile.set(key, changes[key])
	character.position = spot
	add_child(character)
	character.teleport(spot, heading)
	AiSensePool.forget()
	return character


## A plain target named `target_name` at `spot` in `faction` and the group `group`, moved by hand.
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
	AiSensePool.forget()
	return body


## A real body (hit zones, health) in `faction`, with no brain: something to hit and be seen.
func add_dummy(spot: Vector3, faction := &"player", heading := 0.0) -> AiCharacter:
	var character := add_character(spot, null)
	(character.get_node("AiFactionMember") as AiFactionMember).faction = faction
	(character.senses as AiSenses).sight = false
	(character.senses as AiSenses).hearing = false
	character.teleport(spot, heading)
	AiSensePool.forget()
	return character


## An `AiMarker` of `kind` at `spot`; a cover marker's -Z points along `facing` (radians about
## up from -Z).
func add_marker(
	kind: AiMarker.Kind, spot: Vector3, route := &"", facing := 0.0, wait := 0.5
) -> AiMarker:
	var marker := AiMarker.new()
	marker.kind = kind
	marker.route = route
	marker.wait_seconds = wait
	marker.position = spot
	marker.rotation.y = facing
	add_child(marker)
	return marker


## The brain and the runner of `character`.
static func brain_of(character: AiCharacter) -> AiBrain:
	return character.brain as AiBrain


static func runner_of(character: AiCharacter) -> AiTaskRunner:
	return (character.task_runner as AiTasks).runner


## The active task's id of `character` (empty with none).
static func active_of(character: AiCharacter) -> StringName:
	return runner_of(character).active_kind()


## True when `character` asks its body for something now (a walk, an aim, a trigger, a crouch, a
## jump) or its weapon is reloading or switching: what "not idle" means for the stall tests.
static func asks_something(character: AiCharacter) -> bool:
	var controller := character.ai_controller()
	if not controller.is_still():
		return true
	if character.weapon != null and character.weapon.is_reloading():
		return true
	return character.loadout != null and character.loadout.is_switching()

@tool
class_name Player
extends Character
## The human's character: a `Character` (the body, its model and its ragdoll) driven by the
## keys, pad and touch through its `PlayerInput`. On top of the body it joins the group `player`
## (the HUD, the minimap and a `CameraZone` look for that group, so an AI's character is not
## taken for the player), starts at a `SpawnPoint` of that group, starts there again when it falls
## out of the map, and holds the inspector's input switches (`input_enabled`, `ragdoll_key`),
## which its `PlayerInput` reads.

## The group the player joins, so a HUD or a camera finds it.
const GROUP := &"player"
## The input action that kills and revives the character (`ragdoll_key` is added to it).
const RAGDOLL_ACTION := &"ragdoll"

@export_group("Player")
## Starts at a `SpawnPoint` of the group `player` when the scene has one.
@export var start_at_spawn := true
## Turns the keys, pad and touch stick off (a cutscene, a menu): the `PlayerInput` then asks for
## nothing. Commands from anything else are stepped as they are.
@export var input_enabled := true
## The key that kills and revives the character, added to the input action `ragdoll` while the
## game runs (a game can bind more to that action in the Project Settings). A testing aid: set it
## to None in a game that ships without it.
@export var ragdoll_key: Key = KEY_Y:
	set(value):
		ragdoll_key = value
		var input := controller as PlayerInput
		if input != null:
			input.bind_ragdoll_key()
## The player's bag (an `Inventory` node of `player.tscn`), which the inventory screen draws.
## Empty: the player carries no items, and the screen shows the weapons alone.
@export var inventory: Inventory

var _spawn_rng := RandomNumberGenerator.new()


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	add_to_group(GROUP)
	# Fixed for a character, so a test repeats, but not shared, so two characters pick apart.
	_spawn_rng.seed = hash(str(get_path()))
	fell.connect(respawn)
	if start_at_spawn:
		respawn()


## Puts the character at a spawn point of the group `player` (the first free one), or leaves it.
func respawn() -> void:
	var point := SpawnPoint.pick(get_tree(), GROUP, _spawn_rng)
	if point == null:
		return
	var spot := point.spawn_transform(_spawn_rng)
	teleport(spot.origin, atan2(-spot.basis.z.x, -spot.basis.z.z))

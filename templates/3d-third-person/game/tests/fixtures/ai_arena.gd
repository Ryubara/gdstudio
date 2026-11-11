class_name AiArena
extends PlayArena
## A flat world for the AI suites: the `PlayArena` floor, a stand-in for the player's body (a
## `Node3D` in the group `player`, which the director measures the tiers from) and, once asked
## for, an `AiDirector` and AI characters. Free it with `auto_free`.

const CHARACTER := "res://gameplay/ai/ai_character.tscn"

var viewer: Node3D
var director: AiDirector


func _init() -> void:
	super()
	viewer = Node3D.new()
	viewer.name = "Viewer"
	viewer.add_to_group(&"player")
	add_child(viewer)


## Adds the director (before or after the characters: both find each other).
func add_director() -> AiDirector:
	director = AiDirector.new()
	director.name = "AiDirector"
	add_child(director)
	return director


## Adds an AI character at `spot` with a copy of `profile` (the grunt's when null), so a test may
## change its numbers without touching the file.
func add_character(spot: Vector3, profile: AiProfile = null) -> AiCharacter:
	var character := (load(CHARACTER) as PackedScene).instantiate() as AiCharacter
	var source := profile if profile != null else character.profile
	character.profile = source.duplicate() as AiProfile
	character.position = spot
	add_child(character)
	return character

class_name AiNetStage
extends RefCounted
## AI characters for the online AI tests (gdstudio #970): a body that walks where it is told, with
## no senses, brain, tasks or navigator (the server's director still steps it and the broadcast
## sends it), and the server's position of each by tick.

const CHARACTER_SCENE := "res://gameplay/ai/ai_character.tscn"
const SLOTS: Array[StringName] = [&"Navigator", &"Brain", &"Senses", &"AiTasks"]


## An AI character at `spot` that walks along `way` (a zero way stands), its deciding parts taken
## out; add it under the map.
static func walker(spot: Vector3, way := Vector3.ZERO, strength := 1.0) -> AiCharacter:
	var body := (load(CHARACTER_SCENE) as PackedScene).instantiate() as AiCharacter
	body.navigator = null
	body.brain = null
	body.senses = null
	body.task_runner = null
	for slot in SLOTS:
		var part := body.get_node_or_null(NodePath(slot))
		if part != null:
			body.remove_child(part)
			part.free()
	body.position = spot
	walk(body, way, strength)
	return body


## Points `body`'s walk along `way` (zero stands).
static func walk(body: AiCharacter, way: Vector3, strength := 1.0) -> void:
	var controller := body.controller as AiController
	controller.walk_direction = way
	controller.walk_strength = strength


## The map a server holds (its `World`).
static func server_map(server: Node) -> Node:
	return server.get_node("World")

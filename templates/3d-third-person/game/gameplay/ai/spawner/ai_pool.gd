class_name AiPool
extends RefCounted
## AI characters of one scene kept ready for a spawner (`AiSpawner`): made once, when the level
## loads (behind the loading screen), and taken and given back for every spawn after that, so a
## spawn never loads the scene or builds a character (its animation tree, its ragdoll's
## bones) again.
##
## A made character joins the tree once under `parent` and leaves it at once (`prewarm`), so its
## `_ready` (the animation tree, the model variant, the ragdoll's request for bones) is paid then.
## A parked character is out of the tree: it costs nothing, and the director, the senses and the
## groups do not see it.

## The scene every character is made from.
var scene: PackedScene
## Characters made in all (a test counts that a spawn does not make one).
var made := 0

var _parked: Array[AiCharacter] = []


func _init(from: PackedScene = null) -> void:
	scene = from


## Makes characters until `size` are parked or out (`out` of them are in the level now), at most
## `at_most` of them in this call (0: all), each readied once under `parent` and taken out again.
## True while more are still to make.
func prewarm(size: int, out: int, parent: Node, at_most := 0) -> bool:
	var made_now := 0
	while _parked.size() + out < size:
		if at_most > 0 and made_now >= at_most:
			return true
		var character := _make()
		if character == null:
			return false
		if parent != null and parent.is_inside_tree():
			parent.add_child(character)
			parent.remove_child(character)
		_parked.append(character)
		made_now += 1
	return false


## A parked character, or a new one when none is parked (null without a scene).
func take() -> AiCharacter:
	if not _parked.is_empty():
		return _parked.pop_back()
	return _make()


## Parks `character` (out of the tree; the caller took it out).
func park(character: AiCharacter) -> void:
	if character != null and not _parked.has(character):
		_parked.append(character)


## How many are parked.
func parked() -> int:
	return _parked.size()


## Frees every parked character.
func clear() -> void:
	for character in _parked:
		if is_instance_valid(character):
			character.free()
	_parked.clear()


func _make() -> AiCharacter:
	if scene == null:
		return null
	var node := scene.instantiate()
	var character := node as AiCharacter
	if character == null:
		node.free()
		push_warning("AiPool: %s is not an AiCharacter scene." % scene.resource_path)
		return null
	made += 1
	# A name of its own, so its brain's rolls (seeded from the name) differ from its siblings'.
	character.name = "%s%d" % [character.name, made]
	return character

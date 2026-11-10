class_name RagdollPool
extends Node
## Ragdoll bone sets kept ready, so a character's first death does not make its 16 physical bones
## (about 0.6 ms on the desktop and 1 to 4 ms in a browser, gdstudio #1022) but takes a set made
## earlier and moves it onto its skeleton.
##
## One pool for the whole game, under the scene tree's root (`RagdollPool`), made by the first
## `CharacterRagdoll` that runs in a game. Over the frames after that it makes `wanted` sets, one a
## frame, on the skeleton of a character that has none yet, and parks them under a disabled node:
## parked bones are out of the physics world and process nothing. A character that dies takes one
## (`CharacterRagdoll._ensure_bones`); one that is freed while it holds bones gives them back. A
## set made for one model fits another of the same rig: the bodies are fitted to the new rests.
## Nothing here runs in the editor.

## The name of the pool under the root.
const POOL := &"RagdollPool"
## How many sets the pool makes and keeps when the ragdolls cap nothing (`max_active` 0).
const UNCAPPED_SETS := 4
## The most sets it ever keeps.
const MOST_SETS := 8


## A set of bones off any skeleton: the simulator with its bodies, where each body was when its
## joint was made, the extra joints between them, and what they were made for (the rig, the
## thickness and the joints' settings).
class Spare:
	extends RefCounted
	var simulator: PhysicalBoneSimulator3D
	var bones: Dictionary[StringName, PhysicalBone3D] = {}
	var posed: Dictionary[StringName, Transform3D] = {}
	var braces := RagdollBraces.new()
	var fit := ""

	## Frees the bones and their extra joints.
	func free_all() -> void:
		braces.free_all()
		if is_instance_valid(simulator):
			simulator.free()


static var _pool: RagdollPool

## How many sets to keep parked: the largest `max_active` of the ragdolls that asked.
var wanted := 0
var _parked: Array[Spare] = []
var _park: Node
# Instance ids of the ragdolls that may make a set on their skeleton.
var _makers: Array[int] = []


func _init() -> void:
	name = POOL
	_park = Node.new()
	_park.name = "Parked"
	# Disabled: the parked bodies leave the physics world and nothing under it processes.
	_park.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_park)
	set_process(false)


## The game's pool, made under the root when there is none (null outside a running game).
static func instance(tree: SceneTree) -> RagdollPool:
	if _pool != null and is_instance_valid(_pool) and not _pool.is_queued_for_deletion():
		return _pool
	if tree == null or Engine.is_editor_hint():
		return null
	_pool = RagdollPool.new()
	tree.root.add_child.call_deferred(_pool)
	return _pool


## `ragdoll` will die some day: keep sets for it, made on its skeleton while it has none.
func ask(ragdoll: CharacterRagdoll) -> void:
	var cap := ragdoll.max_active if ragdoll.max_active > 0 else UNCAPPED_SETS
	wanted = mini(maxi(wanted, cap), MOST_SETS)
	var id := ragdoll.get_instance_id()
	if not _makers.has(id):
		_makers.append(id)
	set_process(_parked.size() < wanted)


## A parked set, or null when none is left.
func take() -> Spare:
	var spare: Spare = _parked.pop_back() if not _parked.is_empty() else null
	set_process(_parked.size() < wanted)
	return spare


## True when the pool keeps another set.
func has_room() -> bool:
	return _parked.size() < maxi(wanted, 1)


## Parks `spare`, its simulator off any skeleton.
func park(spare: Spare) -> void:
	_park.add_child(spare.simulator)
	_parked.append(spare)
	set_process(_parked.size() < wanted)


## Frees every parked set (the pool makes them again for the ragdolls that ask next).
func clear() -> void:
	for spare in _parked:
		spare.free_all()
	_parked.clear()
	set_process(false)


## How many sets are parked.
func parked() -> int:
	return _parked.size()


func _process(_delta: float) -> void:
	if _parked.size() >= wanted:
		set_process(false)
		return
	# One set a frame, made on the first character that can.
	while not _makers.is_empty():
		var maker := instance_from_id(_makers[0]) as CharacterRagdoll
		if maker == null or not maker.is_inside_tree():
			_makers.remove_at(0)
			continue
		if maker.make_spare():
			return
		_makers.remove_at(0)
	set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for spare in _parked:
			spare.braces.free_all()
		if _pool == self:
			_pool = null

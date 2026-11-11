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
## joint was made, the plan of its extra joints (freed while parked: the new owner makes them again
## after the bones' own joints, in the order Jolt needs), and what they were made for
## (`CharacterRagdoll._set_key`: the rig and the settings of the bodies and their joints).
class Spare:
	extends RefCounted
	var simulator: PhysicalBoneSimulator3D
	var bones: Dictionary[StringName, PhysicalBone3D] = {}
	var posed: Dictionary[StringName, Transform3D] = {}
	var braces := RagdollBraces.new()
	var fit := 0

	## Takes the bones off their skeleton with nothing of the character that held them: their
	## simulation, marks, exceptions (the character's capsule, `ignored`), the hit zones' tag, and
	## their joints. The extra joints are freed too: the new owner makes them again after the bones'
	## own joints, since Jolt solves joints in the order they were made and kept ones come back
	## body by body as the bodies return to the world (a shoulder then twisted 44 degrees past a
	## person's, gdstudio #1022).
	func detach(ignored: Array[CollisionObject3D]) -> void:
		if simulator.is_inside_tree():
			if simulator.is_simulating_physics():
				simulator.physical_bones_stop_simulation()
			var impacts := Impacts.find(simulator)
			if impacts != null:
				impacts.clear_marks_on(simulator)
			for other in ignored:
				if is_instance_valid(other):
					simulator.physical_bones_remove_collision_exception(other.get_rid())
		braces.free_all()
		for bone: PhysicalBone3D in bones.values():
			bone.remove_meta(&"hit_zones")
			# A new owner makes the joint again, posed on its own skeleton.
			bone.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		simulator.active = false
		simulator.influence = 1.0
		simulator.get_parent().remove_child(simulator)


static var _pool: RagdollPool

## How many sets to keep parked: the largest `max_active` of the ragdolls that asked.
var wanted := 0
## True once the first set made has been through a death and a move (`make_spare`).
var warmed := false
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
		if is_instance_valid(spare.simulator):
			spare.simulator.free()
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
	if what == NOTIFICATION_PREDELETE and _pool == self:
		_pool = null

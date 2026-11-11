class_name WorldParity
extends RefCounted
## The solid things of two worlds compared
## (multiplayer.md#the-two-worlds-must-hold-the-same-solid-things): every
## `CollisionObject3D` and colliding `CSGShape3D` under a view outside a character, by its path
## under the map (`World/...`), and what one world holds that the other does not or holds
## elsewhere. A thing that moves on its own clock (a `MovingPlatform`'s body, a prop) is matched
## by its path alone. Used by `test_world_parity.gd` and the soak (`tools/net/soak.gd`).

## Metres two places of one static thing may differ by.
const PLACE_TOLERANCE := 0.001

## Keys found only in the first view, only in the second, and static things at different places.
var only_ours: Array[String] = []
var only_theirs: Array[String] = []
var moved: Array[String] = []
## How many solid things each view holds.
var ours_count := 0
var theirs_count := 0


## Compares the solid things under `ours` (a client's view) and `theirs` (the server's).
static func compare(ours: Node, theirs: Node) -> WorldParity:
	var result := WorldParity.new()
	var mine := solids(ours)
	var other := solids(theirs)
	result.ours_count = mine.size()
	result.theirs_count = other.size()
	for key: String in mine:
		if not other.has(key):
			result.only_ours.append(key)
		elif not mine[key]["moves"]:
			var gap: float = (mine[key]["at"] as Vector3).distance_to(other[key]["at"])
			if gap > PLACE_TOLERANCE:
				result.moved.append("%s (%.3f m)" % [key, gap])
	for key: String in other:
		if not mine.has(key):
			result.only_theirs.append(key)
	return result


## Whether both hold the same solid things at the same places.
func same() -> bool:
	return only_ours.is_empty() and only_theirs.is_empty() and moved.is_empty()


## Every solid thing under `view` outside a character, by its path under the map (`World`), with
## where it is and whether it moves on its own.
static func solids(view: Node) -> Dictionary[String, Dictionary]:
	var found: Dictionary[String, Dictionary] = {}
	for node in view.find_children("*", "Node3D", true, false):
		if not is_solid(node) or _inside_character(node, view):
			continue
		var path := str(view.get_path_to(node))
		var cut := path.find("World/")
		var key := path.substr(cut) if cut >= 0 else path
		var body := node as PhysicsBody3D
		var moves := body != null and not (body is StaticBody3D and not body is AnimatableBody3D)
		found[key] = {"at": (node as Node3D).global_position, "moves": moves}
	return found


static func is_solid(node: Node) -> bool:
	if node is CollisionObject3D:
		return true
	var csg := node as CSGShape3D
	return csg != null and csg.use_collision and csg.is_root_shape()


static func _inside_character(node: Node, view: Node) -> bool:
	var at := node
	while at != null and at != view:
		if at is Character:
			return true
		at = at.get_parent()
	return false

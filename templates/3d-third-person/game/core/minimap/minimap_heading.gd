@tool
class_name MinimapHeading
extends Node
## Says which way its parent faces on the minimap, for a parent whose own node does not turn: a
## character whose body stays put while its model turns inside it. Add it as a child of that
## parent and point `turns` at the node that does turn; a `MinimapMarker` on the parent (its icon
## arrow) and a `Minimap` that follows the parent (its own arrow, `TARGET_FACING`) both read it.
## A parent without one faces its own forward (-Z in 3D, the rotation in 2D).
##
## A minimap finds it with `MinimapHeading.of(parent)` (a child of the parent), never by a method
## name, so the scene shows which nodes give their own heading. It is data only and never synced.

## Which axis of `turns` is its front.
enum Front {
	MINUS_Z,  ## Godot's forward (a camera, a node built in the engine).
	PLUS_Z,  ## The front of a model exported from Blender with +Y up (the template's mannequins).
}

## The node whose facing is the heading (the model that turns inside a character). Empty: the
## parent itself.
@export var turns: Node3D:
	set(node):
		turns = node
		update_configuration_warnings()
## Which axis of `turns` (or of a 3D parent) is its front.
@export var front := Front.MINUS_Z


## The heading component of `node` (a child of it), or null when it has none.
static func of(node: Node) -> MinimapHeading:
	if node == null:
		return null
	if node is MinimapHeading:
		return node
	for child in node.get_children():
		if child is MinimapHeading:
			return child
	return null


## The facing on the map plane as a unit vector: (x, z) in 3D with north being -Z, (x, y) in 2D.
## North (0, -1) when there is nothing to read or the front points straight up or down.
func heading() -> Vector2:
	var node: Node = turns if turns != null else get_parent()
	if node is Node3D:
		var basis := (node as Node3D).global_basis
		var forward := basis.z if front == Front.PLUS_Z else -basis.z
		var flat := Vector2(forward.x, forward.z)
		if flat.length_squared() > 0.000001:
			return flat.normalized()
	elif node is Node2D:
		return Vector2.RIGHT.rotated((node as Node2D).global_rotation)
	return Vector2(0.0, -1.0)


func _get_configuration_warnings() -> PackedStringArray:
	if turns == null and not (get_parent() is Node3D or get_parent() is Node2D):
		return PackedStringArray(["Set `turns`, or put it under a Node3D or a Node2D."])
	return PackedStringArray()

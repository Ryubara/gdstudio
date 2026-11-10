@tool
class_name Vaultable
extends Node
## Says that a solid object may be crossed: vaulted over, mantled onto, or both. Add it as a child
## of the object's body (a `StaticBody3D`, any `CollisionObject3D`), or of the node that holds the
## body (a `ProtoBlock`, an imported scene's root: it then covers every body directly under that
## node). A body without one is never vaulted or mantled, so a level designer decides what can be
## crossed.
##
## A character's `VaultProbe` measures the object itself (height, depth, room to land); the
## settings here only narrow what it may do there, or give the numbers for a shape the probe would
## measure badly. A body's own script can name its component instead, with a property
## `vaultable` that holds one.

## The faces of the object, in its own axes, that may be crossed from.
enum Face {
	POSITIVE_X = 1,  ## The +X face (approached from +X, going toward -X).
	NEGATIVE_X = 2,  ## The -X face.
	POSITIVE_Z = 4,  ## The +Z face.
	NEGATIVE_Z = 8,  ## The -Z face.
}

## Every face.
const ALL_FACES := 15

@export_group("Allowed")
## On: the object may be vaulted over (a low wall, a fence, a crate) when the probe finds it low
## and thin enough and finds room to land beyond it.
@export var allow_vault := true
## On: the object may be mantled onto (climbed on top of) when it is too high or too deep to vault
## and has room to stand on top.
@export var allow_mantle := true
## The faces it may be crossed from, in the object's own axes (+X, -X, +Z, -Z). A wall that may
## be crossed one way only keeps one face; a face that is not a side (the top, a slope) is never
## crossed.
@export_flags("+X", "-X", "+Z", "-Z") var faces := ALL_FACES

@export_group("Overrides")
## The height the character takes the object to be, from the floor it stands on, in metres; 0
## measures it. For a shape whose top the probe would misread (a rounded rail, a mesh with a lip).
@export_range(0.0, 3.0, 0.01, "suffix:m") var height_override := 0.0
## The depth (thickness) the character takes the object to be, in metres; 0 measures it.
@export_range(0.0, 5.0, 0.01, "suffix:m") var depth_override := 0.0
## The clip to play when the character vaults over this object, instead of its own (a game's
## clip names, as its animation player knows them). Empty: the character's own clip.
@export var vault_clip: StringName = &""
## The clip to play when the character mantles onto this object, instead of its own. Empty: the
## character's own clip.
@export var mantle_clip: StringName = &""


## The component that marks `collider` (a body the physics engine returned), or null when it has
## none: a `Vaultable` child of the body, its `vaultable` property, or a `Vaultable` child of the
## body's parent.
static func find(collider: Object) -> Vaultable:
	var node := collider as Node
	if node == null:
		return null
	var own := _child_of(node)
	if own != null:
		return own
	if &"vaultable" in node:
		var named := node.get(&"vaultable") as Vaultable
		if named != null:
			return named
	var parent := node.get_parent()
	return _child_of(parent) if parent != null else null


static func _child_of(node: Node) -> Vaultable:
	for child in node.get_children():
		if child is Vaultable:
			return child
	return null


## True when the object may be crossed from the side whose outward normal (in the world) is
## `normal`: the face it points out of is one of `faces`.
func allows_face(normal: Vector3) -> bool:
	var holder := _holder()
	var local := normal
	if holder != null:
		local = holder.global_basis.inverse() * normal
	local.y = 0.0
	if local.length_squared() < 0.000001:
		return false
	var face := Face.POSITIVE_X
	if absf(local.x) >= absf(local.z):
		face = Face.POSITIVE_X if local.x > 0.0 else Face.NEGATIVE_X
	else:
		face = Face.POSITIVE_Z if local.z > 0.0 else Face.NEGATIVE_Z
	return (faces & face) != 0


# The node whose axes the faces are named in: the parent (the body, or the node that holds it).
func _holder() -> Node3D:
	return get_parent() as Node3D


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var parent := get_parent()
	var has_body := parent == null or parent is CollisionObject3D
	if not has_body:
		for child in parent.get_children():
			if child is CollisionObject3D:
				has_body = true
				break
	if not has_body:
		warnings.append(
			"Put the Vaultable under a body (a StaticBody3D) or beside one under the same node."
		)
	if not allow_vault and not allow_mantle:
		warnings.append("Neither vault nor mantle is allowed: the object cannot be crossed.")
	if faces == 0:
		warnings.append("No face is allowed: the object cannot be crossed.")
	return warnings

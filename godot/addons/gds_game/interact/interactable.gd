@tool
class_name Interactable
extends Area3D
## Makes its parent usable: a door, a lever, a chest, a switch on a wall. A character's interactor
## asks the physics space for the `Interactable` areas near it (on the Sensors layer, 7 in the
## GDStudio layer names) and uses the nearest one in front with `interact(by)`, which says
## `interacted`; the parent (or anything else) listens to that signal. So a node needs no script
## of its own and no method name to be usable: give it an `Interactable` child with a shape, and
## connect `interacted` in the scene.
##
## The area's shape is where it can be found from: the interactor measures its reach to `point`
## (or this node's place when `point` is empty), on the ground plane.

## `by` (the character that pressed its interact button) used it.
signal interacted(by: Node3D)

## The layer the GDStudio projects name Sensors (7), where the interactor looks.
const SENSORS_LAYER := 1 << 6

## The text a prompt shows for it ("Open", "Pull the lever"). Empty: the game's own word.
@export var prompt := "Use"
## Off: it is not found and `interact()` does nothing (a door that is not to be used by hand,
## a lever already pulled).
@export var enabled := true
## Where the reach is measured to, when the parent moves as it is used (a gate that swings away):
## a node that stays put. Empty: this node's own place.
@export var point: Node3D


func _init() -> void:
	collision_layer = SENSORS_LAYER
	collision_mask = 0
	monitoring = false


## The node it makes usable: its parent (null when it has none).
func usable() -> Node3D:
	return get_parent() as Node3D


## Where the reach is measured to, world space.
func reach_point() -> Vector3:
	if point != null and point.is_inside_tree():
		return point.global_position
	return global_position


## Uses it: says `interacted` with `by`. Returns false when it is switched off.
func interact(by: Node3D = null) -> bool:
	if not enabled:
		return false
	interacted.emit(by)
	return true


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var shaped := false
	for child in get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
			shaped = true
	if not shaped:
		warnings.append(
			"Give it a CollisionShape3D child with a shape: an interactor finds it by it."
		)
	if collision_layer == 0:
		warnings.append("It is on no physics layer, so no interactor can find it.")
	return warnings

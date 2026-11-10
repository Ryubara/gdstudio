@tool
class_name HitZone
extends CollisionShape3D
## One body part a shot can hit: a shape that sits on a bone of the character's skeleton, with
## the part's name and how much a hit on it counts. It is the component a shot looks for: a
## `Projectile` that meets a character's capsule asks the character's `HitZones` which zone lies
## on its path, and the zone says the rest (`record()`).
##
## Put zones under a `HitZones` body (`character_dressed.tscn` has eleven) and size each with its
## own shape (a sphere for the head, capsules along the limbs) in the inspector. A zone's place
## is `bone` and `offset`, never the node's own transform: `HitZones` puts the zone on the
## animated bone when a shot needs it, and in the editor on the model as it stands.

## The part's name, what a hit record and a game read (`&"head"`, `&"chest"`, `&"arm_l"`).
@export var zone: StringName = &"body"
## The skeleton bone it sits on and moves with (`&"Head"`, `&"spine_03"`, `&"upperarm_l"`). A
## bone with a ragdoll body is pushed by the hit; any other pushes the nearest one above it.
@export var bone: StringName = &"":
	set(value):
		bone = value
		_moved()
## Where the shape sits in the bone's frame, metres: Y runs along the bone (from its joint toward
## its child), so a capsule (which stands on its Y axis) lies along the limb.
@export var offset := Vector3.ZERO:
	set(value):
		offset = value
		_moved()
## How much a hit here counts: the shot's damage times this (2 doubles it, 0.5 halves it).
@export_range(0.0, 10.0, 0.05, "or_greater") var damage_multiplier := 1.0
## Off: shots pass through this part as if it were not there (they may still meet a part behind
## it).
@export var enabled := true

## The bone's index on the skeleton the zones were last placed on (-1: not found).
var bone_index := -1


## A hit of `damage` on this zone at `point`, travelling along `direction`, pushing with
## `strength`: the record, with this zone's multiplier applied.
func record(
	damage: float, point: Vector3, direction: Vector3, strength: float, source: Node3D = null
) -> HitRecord:
	return HitRecord.shot(
		damage * damage_multiplier, zone, bone, point, direction, strength, source
	)


func _moved() -> void:
	var holder := get_parent() as HitZones
	if holder != null and Engine.is_editor_hint():
		holder.follow_bones.call_deferred()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not get_parent() is HitZones:
		warnings.append("Put the zone under a `HitZones` body.")
	if bone == &"":
		warnings.append("Name the `bone` the zone sits on.")
	if shape == null:
		warnings.append("Give the zone a shape (a sphere, a capsule, a box).")
	return warnings

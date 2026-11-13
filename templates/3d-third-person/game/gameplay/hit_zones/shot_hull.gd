class_name ShotHull
extends StaticBody3D
## A capsule around a living character that only shots and aim rays meet (layer Shot Hulls,
## `PhysicsLayers.SHOT_HULLS`): wider than the body's moving capsule by `margin` and taller by
## `head_room`, and as tall as the stance the body is going to at once. A shot meets it first and
## asks the character's `HitZones` for the part on its line (the second test), so a part the pose
## holds outside the moving capsule is hit: a crouch's hips 0.37 to 0.41 m from the axis of a
## 0.34 m capsule, the head and chest while the body stands up (the pose is upright at once, the
## capsule grows over `crouch_time`). The moving capsule stays as it is: movement, the camera,
## sensors and the other characters never meet this one (gdstudio #1431).
##
## It sits under the character (its child; `character_dressed.tscn` has one) and is sized again
## whenever the capsule is (`CharacterCapsule.fit`). It is off (on no layer) while the character is
## dead, its capsule disabled or the character on no layer (a networked puppet).

## How much wider than the moving capsule, metres: covers the crouch's hips (0.41 m from the axis
## measured on the template's bodies) and a little of the arms held forward.
@export_range(0.0, 0.6, 0.01, "suffix:m") var margin := 0.12
## How much taller than the moving capsule (or the stance it goes to), metres: the drawn head
## stands up to 0.2 m over the standing capsule's top.
@export_range(0.0, 0.8, 0.01, "suffix:m") var head_room := 0.25

var _character: Character
var _shape: CollisionShape3D


func _enter_tree() -> void:
	_character = get_parent() as Character
	if _character != null:
		_character.set_meta(&"shot_hull", self)


func _exit_tree() -> void:
	if _character != null and is_instance_valid(_character):
		if _character.has_meta(&"shot_hull") and _character.get_meta(&"shot_hull") == self:
			_character.remove_meta(&"shot_hull")


func _ready() -> void:
	collision_mask = 0
	for child in get_children():
		if child is CollisionShape3D:
			_shape = child
			break
	if _shape != null and _shape.shape == null:
		_shape.shape = CapsuleShape3D.new()
	if _character == null:
		return
	_character.died.connect(refresh)
	_character.revived.connect(refresh)
	if _character.is_node_ready():
		fit(_character)
	else:
		_character.ready.connect(fit.bind(_character), CONNECT_ONE_SHOT)


## The shot hull of `body` (a character), or null when it has none.
static func of(body: Object) -> ShotHull:
	if body == null or not is_instance_valid(body) or not body.has_meta(&"shot_hull"):
		return null
	var hull: Variant = body.get_meta(&"shot_hull")
	return hull as ShotHull if is_instance_valid(hull) else null


## `body` and its shot hull, when it has one: what a shot, a ray or a projectile leaves out to
## leave out the body (its shooter, a body it passed between the parts of).
static func with_hull(body: CollisionObject3D) -> Array[CollisionObject3D]:
	var found: Array[CollisionObject3D] = []
	if body == null or not is_instance_valid(body):
		return found
	found.append(body)
	var hull := of(body)
	if hull != null:
		found.append(hull)
	return found


## The RIDs of `body` and of its shot hull, for a ray's `exclude`.
static func rids_of(body: CollisionObject3D) -> Array[RID]:
	var rids: Array[RID] = []
	for each in with_hull(body):
		rids.append(each.get_rid())
	return rids


## Sizes the hull around `body`'s capsule as it is now: `margin` wider, and `head_room` over the
## taller of the capsule now and the stance it is going to (standing up, the pose is there at once).
func fit(body: Character) -> void:
	if _shape == null or body == null or body._body == null:
		return
	var moving := body._body.shape as CapsuleShape3D
	if moving == null:
		return
	var goal := CharacterCapsule.crouch_height(body) if body.crouching else body.tuning.height
	var radius := moving.radius + margin
	var tall := maxf(maxf(moving.height, goal) + head_room, radius * 2.0 + 0.01)
	var hull := _shape.shape as CapsuleShape3D
	if hull.radius != radius:
		hull.radius = radius
	if hull.height != tall:
		hull.height = tall
		_shape.position = Vector3(0.0, tall / 2.0, 0.0)
	refresh()


## The hull's shape (sized again in place as the body crouches), or null before it is ready.
func capsule() -> CapsuleShape3D:
	return _shape.shape as CapsuleShape3D if _shape != null else null


## Puts the hull on its layer while the character can be shot, and on none otherwise.
func refresh() -> void:
	var on := (
		_character != null
		and _character.collision_layer != 0
		and not _character.is_dead()
		and _character._body != null
		and not _character._body.disabled
	)
	var layer := PhysicsLayers.SHOT_HULLS if on else 0
	if collision_layer != layer:
		collision_layer = layer

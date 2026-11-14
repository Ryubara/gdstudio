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
## whenever the capsule is (`CharacterCapsule.fit`). It costs a character nothing while nobody
## shoots, as the hit zones do: it is `top_level` (it does not follow the body as it moves, so the
## physics server never hears of it) and on no layer. A shot or an aim ray first calls `arm()`
## along its line, which finds the characters near it (one shape query against their moving
## capsules) and puts only their hulls in place and on their layer, until the next `arm()` or the
## end of the frame. A hull that followed its body was moved in the physics server every tick for
## every character, and the AI's step paid for it (gdstudio #1459). A hull is never armed while its
## character is dead, its capsule disabled or the character on no layer (a networked puppet).

## How far from a line `arm()` looks for characters along the vertical plane through it, past
## their moving capsules, metres: more than any hull stands over its capsule (a body standing up
## from prone: the standing height and `head_room` over a lying capsule).
const ARM_HEIGHT := 2.5
## The most `arm()` takes at once (the shape query's results).
const ARM_MOST := 64
## The narrowest half width `arm()` searches with, metres (a hull with no `margin` still stands
## over its capsule).
const MIN_HALF_WIDTH := 0.05

## The hulls `arm()` put on their layer, taken off again by the next `arm()` or at the frame's end.
static var _armed: Array = []
static var _disarm_queued := false
## The box `arm()` searches with, sized again for each line.
static var _search_box: BoxShape3D
## The widest `margin` of a hull made so far, the half width of the search (below 0: none yet).
static var _widest := -1.0

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
	_armed.erase(self)
	if _character != null and is_instance_valid(_character):
		if _character.has_meta(&"shot_hull") and _character.get_meta(&"shot_hull") == self:
			_character.remove_meta(&"shot_hull")


func _ready() -> void:
	collision_mask = 0
	collision_layer = 0
	top_level = true
	_widest = maxf(_widest, margin)
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


## Puts in place, on their layer, the shot hulls of the characters whose moving capsule is near
## the line from `from` to `to` (within the widest `margin`, and `ARM_HEIGHT` up and down the
## vertical plane through the line), `width` more for a round with a size; the hulls armed before
## are taken off first. Every shot, aim ray and projectile flight calls it before it meets
## anything on the shot mask. Costs one shape query, and nothing for a character far from it.
static func arm(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, width := 0.0) -> void:
	disarm()
	if space == null or _widest < 0.0:
		return
	var along := to - from
	var length := along.length()
	if length < 0.0001:
		return
	var forward := along / length
	var right := forward.cross(Vector3.UP)
	right = right.normalized() if right.length_squared() > 0.000001 else Vector3.RIGHT
	var up := right.cross(forward)
	var half := maxf(_widest, MIN_HALF_WIDTH) + width
	if _search_box == null:
		_search_box = BoxShape3D.new()
	_search_box.size = Vector3(half * 2.0, (ARM_HEIGHT + width) * 2.0, length + half * 2.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _search_box
	query.transform = Transform3D(Basis(right, up, -forward), from + along * 0.5)
	query.collision_mask = PhysicsLayers.CHARACTERS
	for found in space.intersect_shape(query, ARM_MOST):
		var hull := of(found["collider"])
		if hull != null and hull.can_be_shot():
			hull._place()
	if not _armed.is_empty() and not _disarm_queued:
		_disarm_queued = true
		(func() -> void: disarm()).call_deferred()


## Takes every armed hull off its layer (where it is left stays: nothing meets it there).
static func disarm() -> void:
	_disarm_queued = false
	for hull: Variant in _armed:
		if is_instance_valid(hull):
			(hull as ShotHull).collision_layer = 0
	_armed.clear()


## True when a shot can meet this character now: alive, its capsule on, on a layer.
func can_be_shot() -> bool:
	return (
		_character != null
		and is_inside_tree()
		and _character.collision_layer != 0
		and not _character.is_dead()
		and _character._body != null
		and not _character._body.disabled
	)


## True while the hull is armed (in place on its layer for the shot under way).
func is_armed() -> bool:
	return collision_layer != 0


# Puts the hull on its character as it stands now, in the physics server at once, on its layer.
func _place() -> void:
	global_transform = _character.global_transform
	force_update_transform()
	if collision_layer != PhysicsLayers.SHOT_HULLS:
		collision_layer = PhysicsLayers.SHOT_HULLS
	if not _armed.has(self):
		_armed.append(self)


## `query`'s ray cast as a shot sees it: a shot hull it meets (nowhere drawn) gives the part on
## the ray's line (`HitZones.aimed_point`) with the character as the `collider`; a ray between
## the parts looks on past the hull. The aim rays use it (`PlayerCamera.crosshair_point`), so the
## point and the body under the crosshair are the drawn ones (gdstudio #1431). `along` is the
## ray's direction; `query.exclude` grows by each hull passed. It arms the hulls on its line.
static func ray_as_shot(
	space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D, along: Vector3
) -> Dictionary:
	arm(space, query.from, query.to)
	var hit := space.intersect_ray(query)
	if hit.is_empty() or not hit["collider"] is ShotHull:
		return hit
	var zones := HitZones.of(hit["collider"])
	if zones != null:
		var on_part := zones.aimed_point(hit["position"], along)
		if on_part.is_finite():
			return {"position": on_part, "collider": zones.body_met(hit["collider"])}
	var skipped := query.exclude
	skipped.append(hit["rid"])
	query.exclude = skipped
	return space.intersect_ray(query)


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


## The hull's shape (sized again in place as the body crouches), or null before it is ready.
func capsule() -> CapsuleShape3D:
	return _shape.shape as CapsuleShape3D if _shape != null else null


## Takes the hull off its layer when its character can no longer be shot (it died).
func refresh() -> void:
	if not can_be_shot() and collision_layer != 0:
		collision_layer = 0

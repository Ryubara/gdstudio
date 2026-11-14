@tool
class_name HitZones
extends StaticBody3D
## The body parts a shot can hit on a character: a body on its own physics layer (Hit Zones,
## `PhysicsLayers.HIT_ZONES`) holding one `HitZone` shape per part. Nothing moves into it, looks
## for it or senses it but a shot's second test, so movement, the camera and trigger areas never
## meet a zone.
##
## A shot finds a zone in two steps. It flies against the character's shot hull (`hull`, a
## capsule a little wider and taller than the moving one, that only shots meet) or its capsule as
## it does against anything (cheap: one shape); when it touches either it asks this node (`shot()`),
## which
## puts every zone on its bone of the animated skeleton (`follow_bones()`) and casts a short ray
## along the shot through the capsule against the zones alone, from `look_back` before the touch
## (a part the pose puts in front of the capsule is met too). The zone the ray meets first is
## hit; a ray that meets none passed between the parts (beside the waist, between the legs) and
## the shot flies on. So the zones cost nothing while nobody shoots: they are moved only for a
## shot that reached the capsule, never every frame. A part held outside the hull (an arm
## stretched far out to aim) is not hit: the hull is the first test. A character whose animation
## is throttled (`CharacterAnimationThrottle`) is caught up first (`posing`), so the zones are put
## on the pose it has now, not on one frozen off screen (gdstudio #1431).
##
## A lying body (the character's ragdoll, limp) is hit on its bones: a shot that meets a
## `PhysicalBone3D` of this character's ragdoll makes a record of that bone.
##
## The character (`receiver`) takes the record (`Character.take_hit()`, which gives it to its
## `Health`); a receiver that is not a `Character` gives it to its own `Health` child. The record
## is all a game's networking needs to send.

## Said just before the zones are put on the bones for a shot: whoever moves the skeleton less
## often than every frame (the animation throttle) brings the pose up to now.
signal posing

## The character that takes the hits (`Character.take_hit()`, or the `Health` child of another
## body). Its capsule is what a shot meets
## first, and it is tagged so a shot finds this node from the capsule.
@export var receiver: CollisionObject3D:
	set(value):
		_untag(receiver)
		receiver = value
		_tag(receiver)
## The slot holding the model whose skeleton the zones follow.
@export var model: CharacterModel:
	set(value):
		if model != null and model.rig_changed.is_connected(_on_rig_changed):
			model.rig_changed.disconnect(_on_rig_changed)
		model = value
		if model != null and is_inside_tree():
			model.rig_changed.connect(_on_rig_changed)
		_bones_found = false
## The character's ragdoll: a shot that meets one of its bones while the body lies limp is a hit
## on that bone.
@export var ragdoll: CharacterRagdoll:
	set(value):
		if ragdoll != null and ragdoll.started.is_connected(_tag_bones):
			ragdoll.started.disconnect(_tag_bones)
		ragdoll = value
		if ragdoll != null and is_inside_tree() and not Engine.is_editor_hint():
			ragdoll.started.connect(_tag_bones)
## On: a shot on the capsule looks for the part it hit. Off: a shot on the capsule is a hit on
## the whole body (no zone, no multiplier), as before there were zones.
@export var enabled := true
## How far past the capsule's surface the second test looks along the shot, metres: the
## capsule's width is enough for a level shot, more for a steep one.
@export_range(0.2, 4.0, 0.05, "suffix:m") var ray_length := 1.2
## How far before the capsule's surface the second test starts along the shot, metres: a part the
## pose puts in front of the capsule (the hips of a crouch, behind the body's middle) is met on the
## shot's way in, not passed over (gdstudio #1412).
@export_range(0.05, 1.0, 0.05, "suffix:m") var look_back := 0.5

## The shot-only capsule around the character (`ShotHull`): a shot that meets it asks this node
## as one that meets the capsule does, so a part the pose holds outside the capsule is reached. It
## is tagged as the capsule is. Empty: shots meet the capsule alone.
@export var hull: ShotHull:
	set(value):
		_untag(hull)
		hull = value
		_tag(hull)

var _bones_found := false


func _ready() -> void:
	if model != null and not model.rig_changed.is_connected(_on_rig_changed):
		model.rig_changed.connect(_on_rig_changed)
	_tag(receiver)
	_tag(hull)
	if Engine.is_editor_hint():
		follow_bones.call_deferred()
		return
	# The zones are placed in world space when a shot needs them, not dragged along with the
	# character every tick.
	top_level = true
	if ragdoll != null and not ragdoll.started.is_connected(_tag_bones):
		ragdoll.started.connect(_tag_bones)


## The `HitZones` that answers for `collider` (a character's capsule or one of its ragdoll's
## bones), or null.
static func of(collider: Object) -> HitZones:
	if collider == null or not collider.has_meta(&"hit_zones"):
		return null
	var found: Variant = collider.get_meta(&"hit_zones")
	return found as HitZones if is_instance_valid(found) else null


## The body a shot that met `collider` counts as having met: the character (`receiver`) for its
## shot hull, `collider` itself for anything else. Marks, effects and the hit's `collider` use it.
func body_met(collider: Object) -> Object:
	return receiver if hull != null and collider == hull else collider


## The bodies a shot that passed between the parts leaves out to fly on: the capsule and the hull.
func shot_bodies() -> Array[CollisionObject3D]:
	var bodies: Array[CollisionObject3D] = []
	if receiver != null and is_instance_valid(receiver):
		bodies.append(receiver)
	if hull != null and is_instance_valid(hull):
		bodies.append(hull)
	return bodies


## Every zone under this body.
func zones() -> Array[HitZone]:
	var found: Array[HitZone] = []
	for child in get_children():
		if child is HitZone:
			found.append(child)
	return found


## The zone named `zone_name`, or null.
func zone(zone_name: StringName) -> HitZone:
	for each in zones():
		if each.zone == zone_name:
			return each
	return null


## What a shot that touched `collider` (this character's capsule, or a bone of its ragdoll) at
## `point`, flying along `direction`, hit: a record for the receiver, or null when it passed
## between the parts and should fly on. The damage is `damage` times the zone's multiplier.
## `centre` is where the shot's own middle was at the touch (a projectile's position): the second
## test's ray runs from there, on the shot's line, not from the edge that touched.
func shot(
	collider: Object,
	point: Vector3,
	direction: Vector3,
	damage: float,
	strength: float,
	source: Node3D = null,
	centre := Vector3.INF
) -> HitRecord:
	var along := direction.normalized()
	if collider is PhysicalBone3D:
		var lying := collider as PhysicalBone3D
		var on_bone := _zone_on(lying.bone_name)
		var zone_name: StringName = on_bone.zone if on_bone != null else &""
		return HitRecord.shot(damage, zone_name, lying.bone_name, point, along, strength, source)
	if not enabled or zones().is_empty():
		return HitRecord.shot(damage, &"", &"", point, along, strength, source)
	var start := centre if centre.is_finite() else point
	var found := find(start - along * look_back, point + along * ray_length)
	if found.is_empty():
		return null
	var part: HitZone = found.zone
	return part.record(damage, found.point, along, strength, source)


## Where an aim ray that met this character's capsule at `point`, going `along`, meets the body:
## the point on the part it meets, or `Vector3.INF` when it passes between the parts (the aim goes
## on past the body, as a shot along it would). With the zones off, or none, it is `point`: a shot
## there is a hit on the whole body. A weapon aims at this point, not at the capsule's surface: the
## muzzle is beside the camera, so a shot sent at a point in front of the part crosses the
## crosshair's line there and passes beside the part (gdstudio #1251).
func aimed_point(point: Vector3, along: Vector3) -> Vector3:
	if not enabled or zones().is_empty():
		return point
	var way := along.normalized()
	var found := find(point - way * look_back, point + way * ray_length)
	return found.point if not found.is_empty() else Vector3.INF


## Gives `record` to the receiver: a `Character` takes it (`take_hit()`), any other body's
## `Health` child applies it. A hit its source may not deal (a friend's, `AiFactions.can_hurt`)
## is dropped.
func deliver(record: HitRecord) -> void:
	if record == null or receiver == null:
		return
	if not AiFactions.can_hurt(record.source, receiver):
		return
	var character := receiver as Character
	if character != null:
		character.take_hit(record)
		return
	var health := Health.of(receiver)
	if health != null:
		health.apply(record)


## The first zone of this body on the segment `from`-`to`, after putting the zones on the bones:
## `{zone = HitZone, point = Vector3, normal = Vector3}`, or empty when it meets none. A
## disabled zone is passed through.
func find(from: Vector3, to: Vector3) -> Dictionary:
	if not is_inside_tree():
		return {}
	posing.emit()
	follow_bones()
	var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.HIT_ZONE_MASK)
	var skipped: Array[RID] = []
	var space := get_world_3d().direct_space_state
	# Another character's zones may lie on the segment (they stay where its last shot put them):
	# step past them, and past this body's disabled zones.
	for attempt in 8:
		query.exclude = skipped
		var met := space.intersect_ray(query)
		if met.is_empty():
			return {}
		var part: HitZone = null
		if met.collider == self:
			part = shape_owner_get_owner(shape_find_owner(met.shape)) as HitZone
		if part != null and part.enabled:
			return {zone = part, point = met.position, normal = met.normal}
		if met.collider == self:
			# A disabled zone: look again from just past it.
			query.from = (met.position as Vector3) + (to - from).normalized() * 0.001
		else:
			skipped.append(met.rid)
	return {}


## Puts every zone on its bone as the skeleton is posed now. A shot calls it through `find()`;
## call it yourself before reading the zones' places.
func follow_bones() -> void:
	var skeleton := model.skeleton() if model != null else null
	if skeleton == null or not skeleton.is_inside_tree() or not is_inside_tree():
		return
	if not _bones_found:
		for part in zones():
			part.bone_index = skeleton.find_bone(part.bone)
		_bones_found = true
	if top_level:
		global_transform = skeleton.global_transform
		# The physics server hears of a node's new transform when the frame's transforms are sent,
		# after this shot's query: send it now (a body that moved since the last shot was met where
		# that shot left its zones, gdstudio #1198).
		force_update_transform()
	var to_here := global_transform.affine_inverse() * skeleton.global_transform
	for part in zones():
		if part.bone_index < 0:
			continue
		var pose := skeleton.get_bone_global_pose(part.bone_index)
		part.transform = to_here * pose * Transform3D(Basis.IDENTITY, part.offset)


func _zone_on(bone_name: StringName) -> HitZone:
	for part in zones():
		if part.bone == bone_name:
			return part
	return null


func _on_rig_changed(_rig: Node3D) -> void:
	_bones_found = false
	if Engine.is_editor_hint():
		follow_bones.call_deferred()


func _tag(body: Object) -> void:
	if body != null and not Engine.is_editor_hint():
		body.set_meta(&"hit_zones", self)


func _untag(body: Object) -> void:
	if body != null and is_instance_valid(body) and body.has_meta(&"hit_zones"):
		body.remove_meta(&"hit_zones")


# The ragdoll's bones are made again when the model changes: tag them each time it goes limp.
func _tag_bones() -> void:
	var simulator := ragdoll.simulator() if ragdoll != null else null
	if simulator == null:
		return
	for child in simulator.get_children():
		if child is PhysicalBone3D:
			child.set_meta(&"hit_zones", self)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if receiver == null:
		warnings.append("Set `receiver` to the character that takes the hits.")
	if model == null:
		warnings.append("Set `model` to the CharacterModel whose skeleton the zones follow.")
	if zones().is_empty():
		warnings.append("Add `HitZone` shapes under this body.")
	return warnings

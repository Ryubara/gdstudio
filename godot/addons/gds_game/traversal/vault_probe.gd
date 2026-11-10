class_name VaultProbe
extends RefCounted
## Looks at the obstacle ahead of a body and plans a crossing of it: a vault over it, a mantle onto
## it, or nothing (with the reason). Every look is a shape cast, never a single ray, so a thin rail,
## a gap or a ledge between two rays is not missed:
##
## 1. a box as wide as the body is cast ahead, from just above the floor to the highest mantle,
##    and finds the face (and its body, which must carry a `Vaultable`);
## 2. a small sphere is cast down just past the face and finds the top (its height and slope);
## 3. a thin box is cast back toward the face from a vault's depth beyond it, just under the top,
##    and finds the far face (the depth);
## 4. a sphere is cast down past the far face and finds the floor to land on;
## 5. the body's own capsule is cast along the whole path, and must fit where it ends.
##
## A vault needs the obstacle low and thin enough, a floor to land on and room all the way; a
## mantle (the obstacle too high or too deep, or no landing beyond it) needs room to stand on top.
## The numbers are a `VaultSettings`; the component's overrides and permissions come on top.

## How far the probes start inside the body's own front, so an obstacle the body already touches
## is found.
const INSIDE := 0.05
## How much thinner than the body the casts along the path are, so brushing a side wall is not a
## block.
const SKIN := 0.03
## The thickness of the boxes cast ahead and back.
const SLAB := 0.06
## How many other bodies the depth cast leaves out before it gives up (a crowded far side).
const OTHERS := 4


## Plans a crossing for `body` with its feet at `feet`, going along `direction` (flat), at `speed`
## m/s on the ground. `radius` and `height` are its standing capsule's. The casts use the body's
## collision mask and leave the body out.
static func measure(
	body: CollisionObject3D,
	feet: Vector3,
	direction: Vector3,
	radius: float,
	height: float,
	speed: float,
	settings: VaultSettings
) -> VaultPlan:
	var space := body.get_world_3d().direct_space_state
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.000001:
		return VaultPlan.refused(VaultPlan.NOTHING_AHEAD)
	flat = flat.normalized()
	var mask := body.collision_mask
	var exclude: Array[RID] = [body.get_rid()]
	var reach := maxf(settings.max_mantle_height, settings.max_vault_height)

	# 1. The face ahead.
	var face := _cast_ahead(
		space, feet, flat, radius, reach, settings.detect_reach(speed), mask, exclude
	)
	if face.is_empty():
		return VaultPlan.refused(VaultPlan.NOTHING_AHEAD)
	var collider: Object = instance_from_id(face["collider_id"])
	var vaultable := Vaultable.find(collider)
	if vaultable == null:
		return _refuse(VaultPlan.NOT_VAULTABLE, collider, null)
	var normal: Vector3 = face["normal"]
	# A face that leans back more than the steepest top is a slope to walk, not a wall.
	var lean := rad_to_deg(normal.angle_to(Vector3.UP))
	normal.y = 0.0
	if lean < 90.0 - settings.max_top_slope or normal.length_squared() < 0.01:
		return _refuse(VaultPlan.NOT_A_WALL, collider, vaultable)
	normal = normal.normalized()
	var forward := -normal
	if rad_to_deg(flat.angle_to(forward)) > settings.max_approach_angle:
		return _refuse(VaultPlan.TOO_OBLIQUE, collider, vaultable)
	if not vaultable.allows_face(normal):
		return _refuse(VaultPlan.FACE_NOT_ALLOWED, collider, vaultable)
	var face_point: Vector3 = face["point"]
	# How far ahead of the feet the face is, along the crossing.
	var near := (face_point - feet).dot(forward)

	# 2. The top.
	var over := feet + forward * (near + settings.top_probe_radius + 0.02)
	var top := _cast_down(
		space, over, feet.y + reach, feet.y, settings.top_probe_radius, mask, exclude
	)
	if top.is_empty():
		return _refuse(VaultPlan.TOO_HIGH, collider, vaultable)
	var top_normal: Vector3 = top["normal"]
	if rad_to_deg(top_normal.angle_to(Vector3.UP)) > settings.max_top_slope:
		return _refuse(VaultPlan.TOP_NOT_FLAT, collider, vaultable)
	var top_y: float = top["y"]
	if vaultable.height_override > 0.0:
		top_y = feet.y + vaultable.height_override
	var obstacle_height := top_y - feet.y

	# 3. The depth.
	var depth := _depth(
		space, feet, forward, near, top_y, radius, face["rid"], settings, mask, exclude
	)
	if vaultable.depth_override > 0.0:
		depth = vaultable.depth_override

	var plan := VaultPlan.new()
	plan.collider = collider
	plan.vaultable = vaultable
	plan.height = obstacle_height
	plan.depth = depth
	plan.forward = forward
	plan.face_point = face_point
	plan.top = top_y
	var start := feet
	var why := _plan_vault(plan, space, start, near, radius, height, speed, settings, mask, exclude)
	if why == &"":
		return plan
	if _plan_mantle(plan, space, start, near, radius, height, settings, mask, exclude):
		return plan
	return _refuse(why, collider, vaultable)


# Fills `plan` as a vault; returns empty, or why it cannot be one.
static func _plan_vault(
	plan: VaultPlan,
	space: PhysicsDirectSpaceState3D,
	start: Vector3,
	near: float,
	radius: float,
	height: float,
	speed: float,
	settings: VaultSettings,
	mask: int,
	exclude: Array[RID]
) -> StringName:
	if not plan.vaultable.allow_vault:
		return VaultPlan.NOT_VAULTABLE
	if plan.height < settings.min_vault_height:
		return VaultPlan.TOO_LOW
	if plan.height > settings.max_vault_height:
		return VaultPlan.TOO_HIGH
	if plan.depth > settings.max_vault_depth:
		return VaultPlan.TOO_DEEP
	if speed < settings.min_vault_speed:
		return VaultPlan.TOO_SLOW
	var forward := plan.forward
	var lift := plan.top + settings.foot_clearance
	var plant := start + forward * (near - radius)
	plant.y = lift
	var clear := start + forward * (near + plan.depth + radius)
	clear.y = lift
	var land_at := start + forward * (near + plan.depth + radius + settings.landing_margin)
	var ground := _cast_down(
		space, land_at, plan.top + 0.1, start.y - settings.max_drop, radius - SKIN, mask, exclude
	)
	if ground.is_empty():
		return VaultPlan.NO_LANDING
	land_at.y = ground["y"]
	var path := PackedVector3Array([start, plant, clear, land_at])
	if not _path_clear(space, path, radius, height, mask, exclude):
		return VaultPlan.NO_ROOM
	plan.kind = VaultPlan.Kind.VAULT
	plan.high = plan.height >= settings.high_vault_above
	plan.points = path
	plan.times = PackedFloat32Array(
		[0.0, settings.plant_at, maxf(settings.clear_at, settings.plant_at), 1.0]
	)
	plan.eases = PackedInt32Array(
		[VaultPlan.Ease.EVEN, VaultPlan.Ease.OUT, VaultPlan.Ease.EVEN, VaultPlan.Ease.IN]
	)
	plan.duration = settings.vault_time(_flat_length(path), speed)
	return &""


# Fills `plan` as a mantle; false when it cannot be one.
static func _plan_mantle(
	plan: VaultPlan,
	space: PhysicsDirectSpaceState3D,
	start: Vector3,
	near: float,
	radius: float,
	height: float,
	settings: VaultSettings,
	mask: int,
	exclude: Array[RID]
) -> bool:
	if not plan.vaultable.allow_mantle:
		return false
	if plan.height < settings.min_mantle_height or plan.height > settings.max_mantle_height:
		return false
	var forward := plan.forward
	var hang := start + forward * (near - radius - SKIN)
	hang.y = plan.top + settings.foot_clearance
	# Onto the top by the body's radius and the inset, or to the middle of a top thinner than that.
	var onto := radius + settings.mantle_inset
	if is_finite(plan.depth):
		onto = minf(onto, plan.depth / 2.0)
	var stand := start + forward * (near + onto)
	stand.y = plan.top
	var path := PackedVector3Array([start, hang, stand])
	if not _path_clear(space, path, radius, height, mask, exclude):
		return false
	plan.kind = VaultPlan.Kind.MANTLE
	plan.high = plan.height >= settings.high_mantle_above
	plan.points = path
	plan.times = PackedFloat32Array([0.0, settings.mantle_top_at, 1.0])
	plan.eases = PackedInt32Array([VaultPlan.Ease.EVEN, VaultPlan.Ease.BOTH, VaultPlan.Ease.EVEN])
	plan.duration = settings.mantle_time(plan.height)
	return true


static func _refuse(reason: StringName, collider: Object, vaultable: Vaultable) -> VaultPlan:
	var plan := VaultPlan.refused(reason)
	plan.collider = collider
	plan.vaultable = vaultable
	return plan


# Casts a box as wide as the body ahead, from a hand above the floor to `reach` above it. Empty, or
# the contact's `collider_id`, `point` and `normal`.
static func _cast_ahead(
	space: PhysicsDirectSpaceState3D,
	feet: Vector3,
	forward: Vector3,
	radius: float,
	reach: float,
	distance: float,
	mask: int,
	exclude: Array[RID]
) -> Dictionary:
	# From just above a floor's bumps to the top of the highest crossing.
	var bottom := 0.1
	var box := BoxShape3D.new()
	box.size = Vector3((radius - SKIN) * 2.0, reach - bottom, SLAB)
	var basis := Basis.looking_at(forward, Vector3.UP)
	var middle := feet + Vector3.UP * (bottom + (reach - bottom) / 2.0)
	middle += forward * (radius - INSIDE - SLAB / 2.0)
	var query := _query(box, Transform3D(basis, middle), mask, exclude)
	query.motion = forward * (distance + INSIDE)
	var fractions := space.cast_motion(query)
	if fractions.is_empty() or fractions[1] >= 1.0:
		return {}
	query.transform.origin = middle + query.motion * fractions[1]
	query.motion = Vector3.ZERO
	return space.get_rest_info(query)


# Casts a sphere of `radius` straight down at `over` from `from_y` to `to_y`. Empty when nothing
# is under it or the sphere starts inside something (the obstacle reaches higher than `from_y`);
# else `y` (the surface's height) and `normal`.
static func _cast_down(
	space: PhysicsDirectSpaceState3D,
	over: Vector3,
	from_y: float,
	to_y: float,
	radius: float,
	mask: int,
	exclude: Array[RID]
) -> Dictionary:
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(radius, 0.02)
	var start := Vector3(over.x, from_y + sphere.radius, over.z)
	var query := _query(sphere, Transform3D(Basis.IDENTITY, start), mask, exclude)
	if not space.intersect_shape(query, 1).is_empty():
		return {}
	query.motion = Vector3.DOWN * maxf(from_y - to_y, 0.0)
	var fractions := space.cast_motion(query)
	if fractions.is_empty() or fractions[1] >= 1.0:
		return {}
	var motion := query.motion
	query.transform.origin = start + motion * fractions[1]
	query.motion = Vector3.ZERO
	var rest := space.get_rest_info(query)
	query.motion = motion
	if rest.is_empty():
		return {}
	# The sphere's lowest point where it stopped is the surface's height.
	var y: float = (start + query.motion * fractions[0]).y - sphere.radius
	return {"y": y, "normal": rest["normal"]}


# The obstacle's depth along `forward`: a thin box is cast back toward the face from a vault's
# depth beyond it, just under the top, and only the obstacle's own body counts (anything else in
# the way, a wall behind it, is left out and the cast made again). `INF` when the box starts inside
# the obstacle (deeper than a vault looks).
static func _depth(
	space: PhysicsDirectSpaceState3D,
	feet: Vector3,
	forward: Vector3,
	near: float,
	top_y: float,
	radius: float,
	obstacle: RID,
	settings: VaultSettings,
	mask: int,
	exclude: Array[RID]
) -> float:
	var look := settings.max_vault_depth + SLAB
	var box := BoxShape3D.new()
	box.size = Vector3((radius - SKIN) * 2.0, SLAB, SLAB)
	var basis := Basis.looking_at(forward, Vector3.UP)
	var start := feet + forward * (near + look + SLAB / 2.0)
	start.y = top_y - SLAB
	var skip := exclude.duplicate()
	var query := _query(box, Transform3D(basis, start), mask, skip)
	for _attempt in OTHERS:
		query.exclude = skip
		query.motion = Vector3.ZERO
		var inside := space.intersect_shape(query, OTHERS)
		var other := false
		for hit: Dictionary in inside:
			if hit["rid"] == obstacle:
				return INF
			skip.append(hit["rid"])
			other = true
		if other:
			continue
		query.motion = -forward * look
		var fractions := space.cast_motion(query)
		if fractions.is_empty() or fractions[1] >= 1.0:
			# Nothing between: thinner than the slab itself.
			return SLAB
		var motion := query.motion
		query.transform.origin = start + motion * fractions[1]
		query.motion = Vector3.ZERO
		var rest := space.get_rest_info(query)
		query.transform.origin = start
		if rest.is_empty() or rest["rid"] == obstacle:
			return maxf(look - look * fractions[0], 0.0)
		skip.append(rest["rid"])
	return INF


# True when the body's capsule (a skin thinner) moves along every stretch of `path` (feet points)
# without touching anything and fits where it ends.
static func _path_clear(
	space: PhysicsDirectSpaceState3D,
	path: PackedVector3Array,
	radius: float,
	height: float,
	mask: int,
	exclude: Array[RID]
) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius - SKIN
	capsule.height = maxf(height - SKIN * 2.0, capsule.radius * 2.0 + 0.01)
	var rise := Vector3.UP * (height / 2.0)
	var query := _query(capsule, Transform3D(Basis.IDENTITY, path[0] + rise), mask, exclude)
	for index in range(1, path.size()):
		var from := path[index - 1] + rise
		var to := path[index] + rise
		query.transform.origin = from
		query.motion = to - from
		var fractions := space.cast_motion(query)
		if fractions.is_empty() or fractions[0] < 1.0:
			return false
	query.transform.origin = path[path.size() - 1] + rise
	query.motion = Vector3.ZERO
	return space.intersect_shape(query, 1).is_empty()


static func _query(
	shape: Shape3D, at: Transform3D, mask: int, exclude: Array[RID]
) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = at
	query.collision_mask = mask
	query.exclude = exclude
	return query


static func _flat_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for index in range(1, path.size()):
		var step := path[index] - path[index - 1]
		total += Vector2(step.x, step.z).length()
	return total

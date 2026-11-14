class_name WeaponRay
extends RefCounted
## The rays a `Weapon` looks along (gdstudio #1431), kept apart from its shots: the raw ray past
## its shooter, the aim ray that takes the part of a character it meets, and the cosmetic ray a
## puppet's tracer ends on. A ray on the shot mask meets characters' shot hulls (`ShotHull`),
## which are nowhere drawn, so every ray whose point is shown or shot at goes through the part on
## its line, never the hull. Its functions are static and keep nothing.


## The first thing on `mask` between `start` and `end`, past `weapon`'s shooter and its shot hull
## and the bodies in `skip`: the physics server's hit as it is (a shot hull included).
static func cast(
	weapon: Weapon, start: Vector3, end: Vector3, skip: Array[RID], mask: int
) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(start, end, mask)
	var excluded: Array[RID] = skip.duplicate()
	if weapon.shooter != null:
		excluded.append_array(ShotHull.rids_of(weapon.shooter))
	query.exclude = excluded
	return weapon.get_world_3d().direct_space_state.intersect_ray(query)


## The point the aim ray from `start` to `end` (along `along`) aims at: the first thing it meets,
## the part of a character with hit zones on its line (met on its capsule or its shot hull), or
## `end`. A ray between a body's parts goes on, `passes` bodies at most.
static func aim_point(
	weapon: Weapon, start: Vector3, end: Vector3, along: Vector3, passes: int
) -> Vector3:
	var skipped: Array[RID] = []
	for _pass in passes:
		var found := cast(weapon, start, end, skipped, weapon.aim_mask)
		if found.is_empty():
			return end
		var met: Object = found["collider"]
		var zones := HitZones.of(met) if met is CharacterBody3D or met is ShotHull else null
		if zones == null:
			return found["position"]
		var on_part := zones.aimed_point(found["position"], along)
		if on_part.is_finite():
			return on_part
		skipped.append(found["rid"])
		for body in zones.shot_bodies():
			skipped.append(body.get_rid())
	return end


## Where a cosmetic ray from `start` along `heading` (length 1) ends within `reach` on `mask`:
## the drawn part of a character it meets (`ShotHull.ray_as_shot`), the first other thing, or its
## reach.
static func end_of(
	weapon: Weapon, start: Vector3, heading: Vector3, reach: float, mask: int
) -> Vector3:
	var end := start + heading * reach
	if not weapon.is_inside_tree():
		return end
	var query := PhysicsRayQueryParameters3D.create(start, end, mask)
	if weapon.shooter != null:
		query.exclude = ShotHull.rids_of(weapon.shooter)
	var found := ShotHull.ray_as_shot(weapon.get_world_3d().direct_space_state, query, heading)
	return found["position"] if not found.is_empty() else end

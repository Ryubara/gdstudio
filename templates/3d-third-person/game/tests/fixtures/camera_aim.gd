class_name CameraAim
extends RefCounted
## How the `Weapon` aimed while it read the camera itself (before gdstudio #901 gave it the ray
## as an argument), kept word for word so a test can hold the new `fire(origin, direction)` and
## `aim_point(origin, direction)` to the old numbers. Not for a game: a weapon reads no camera.


## The old `Weapon.aim_point()`: the first thing the ray through the middle of the screen hits
## (past the shooter), or the end of the ray.
static func aim_point(weapon: Weapon) -> Vector3:
	var muzzle := weapon.muzzle
	var shooter := weapon.shooter
	var camera := weapon.get_viewport().get_camera_3d() if weapon.is_inside_tree() else null
	if camera == null:
		var out := -muzzle.global_basis.z if muzzle != null else -weapon.global_basis.z
		var from := muzzle.global_position if muzzle != null else weapon.global_position
		return from + out * weapon.aim_range
	var centre := weapon.get_viewport().get_visible_rect().size / 2.0
	var ray := camera.project_ray_normal(centre)
	var start := camera.project_ray_origin(centre)
	if shooter != null:
		# Start the ray at the shooter's depth, so a wall behind the character is not hit.
		start += ray * maxf((shooter.global_position - start).dot(ray), 0.0)
	var end := start + ray * weapon.aim_range
	var query := PhysicsRayQueryParameters3D.create(start, end, weapon.aim_mask)
	if shooter != null:
		query.exclude = [shooter.get_rid()]
	var found := weapon.get_world_3d().direct_space_state.intersect_ray(query)
	return found["position"] if not found.is_empty() else end


## The old `Weapon._direction_from()`: the way a shot left `origin` (the muzzle).
static func direction_from(weapon: Weapon, origin: Vector3) -> Vector3:
	var camera := weapon.get_viewport().get_camera_3d()
	var toward := aim_point(weapon) - origin
	var fallback := -weapon.muzzle.global_basis.z
	if camera != null:
		fallback = -camera.global_basis.z
		# A point beside or behind the gun (a wall at the character's back) would turn the shot
		# around: shoot along the view instead.
		if toward.dot(fallback) <= 0.0:
			toward = fallback
	if toward.length() < 0.2:
		toward = fallback
	return toward.normalized()


## The ray through the middle of the screen that `camera` draws: where it starts and its
## direction, as a `PlayerInput` writes it into a command's shot block.
static func crosshair_ray(camera: Camera3D) -> PackedVector3Array:
	var centre := camera.get_viewport().get_visible_rect().size / 2.0
	return PackedVector3Array(
		[camera.project_ray_origin(centre), camera.project_ray_normal(centre)]
	)

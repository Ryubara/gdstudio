class_name BodyClearance
extends RefCounted
## Measures how deep a held weapon goes into the body that holds it (kit #1177): every point of
## the weapon (its vertices and its triangles' centres) is tested against the mannequin's skinned
## mesh as drawn, in the pose a `HandContact` copied in `skeleton_updated` (after the hold's
## modifiers). The mannequin's skin is closed (its two surfaces meet at the bands' seams), so a
## point is inside when a ray from it along +Z crosses the skin an odd number of times; its depth
## is the distance to the nearest triangle, and the body part is that triangle's main bone. The
## hands and forearms hold the weapon and are left out (`HandContact` measures them).

## The bones whose skin, and every bone's under them, is not the torso: the arms, which hold the
## weapon and lie along it, and the legs.
const NOT_TORSO: Array[StringName] = [
	&"upperarm_r", &"upperarm_l", &"thigh_r", &"thigh_l", &"neck_01"
]
## The bones left out to measure the whole body (kit #1340): only the forearms and hands, which
## hold the weapon (`HandContact` measures them); the legs, upper arms and head count.
const HOLDING: Array[StringName] = [&"lowerarm_r", &"lowerarm_l"]
## How far round the weapon the skin is looked at, in metres: deeper than this reads as this.
const REACH := 0.15
const _CELL := 0.02

var _skeleton: Skeleton3D
var _contact: HandContact
var _surfaces: Array[Dictionary] = []
var _limbs := PackedByteArray()
var _points := PackedVector3Array()
# The skin `pose_skin()` kept: three corners a triangle, each triangle's bone, the triangles over
# each column of the XY plane and in each cell.
var _skin := PackedVector3Array()
var _owner := PackedInt32Array()
var _columns := {}
var _cells := {}


## `contact` copies the pose (its `bone_pose()`); `weapon` is the node whose meshes are measured;
## `left_out` the bones whose skin, and every bone's under them, is not measured (the torso alone
## by default, `HOLDING` for the whole body).
func _init(
	skeleton: Skeleton3D,
	contact: HandContact,
	weapon: Node3D,
	left_out: Array[StringName] = NOT_TORSO
) -> void:
	_skeleton = skeleton
	_contact = contact
	_limbs.resize(skeleton.get_bone_count())
	for bone in skeleton.get_bone_count():
		var cursor := bone
		while cursor >= 0:
			if left_out.has(skeleton.get_bone_name(cursor)):
				_limbs[bone] = 1
				break
			cursor = skeleton.get_bone_parent(cursor)
	# The nearest level of detail only: the farther ones lie inside it and would be counted too.
	for instance in CharacterBodies.near_meshes(skeleton):
		if instance.skin == null or instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			_add_surface(instance, surface)
	_collect_weapon(weapon)


## The deepest a point of the weapon is in the body in the pose now, left out the hands and
## forearms: {"depth": metres (0 when clear), "bone": the body part's bone, "point": the
## weapon's point in its own space, "out": the way from it to the skin, in the skeleton's space,
## "gap": with `with_gap`, when it is clear, how far its nearest point is from the torso's skin
## (`REACH` at most)}.
func deepest(weapon: Node3D, with_gap := false) -> Dictionary:
	var to_skeleton := _skeleton.global_transform.affine_inverse() * weapon.global_transform
	var points := PackedVector3Array()
	var bounds := AABB()
	for index in _points.size():
		var at := to_skeleton * _points[index]
		points.append(at)
		bounds = AABB(at, Vector3.ZERO) if index == 0 else bounds.expand(at)
	pose_skin(bounds.grow(REACH))
	var found := {"depth": 0.0, "bone": &"", "point": Vector3.ZERO, "out": Vector3.ZERO}
	var gap := REACH
	for index in points.size():
		var hit := depth_at(points[index])
		if hit.depth > found.depth:
			found = hit
			found.point = _points[index]
		elif with_gap and hit.depth <= 0.0 and found.depth <= 0.0:
			var nearest := _nearest(points[index])
			if nearest[1] >= 0 and _limbs[_owner[nearest[1]]] == 0:
				gap = minf(gap, nearest[0])
	found.gap = 0.0 if found.depth > 0.0 else gap
	return found


## Skins the body in the pose now, keeping the skin over `region` (in the skeleton's space) for
## `depth_at()`.
func pose_skin(region: AABB) -> void:
	_skin = PackedVector3Array()
	_owner = PackedInt32Array()
	_columns = {}
	_cells = {}
	for surface: Dictionary in _surfaces:
		var posed := _posed(surface)
		var indices: PackedInt32Array = surface.indices
		var main: PackedInt32Array = surface.main
		for triangle in indices.size() / 3:
			var a := posed[indices[triangle * 3]]
			var b := posed[indices[triangle * 3 + 1]]
			var c := posed[indices[triangle * 3 + 2]]
			var low := a.min(b).min(c)
			var high := a.max(b).max(c)
			# The column test needs every triangle over the region, at any height along Z.
			if (
				high.x < region.position.x
				or low.x > region.end.x
				or high.y < region.position.y
				or low.y > region.end.y
			):
				continue
			_skin.append_array([a, b, c])
			_owner.append(main[indices[triangle * 3]])
	for triangle in _owner.size():
		var a := _skin[triangle * 3]
		var b := _skin[triangle * 3 + 1]
		var c := _skin[triangle * 3 + 2]
		var low := a.min(b).min(c) / _CELL
		var high := a.max(b).max(c) / _CELL
		for x in range(floori(low.x), floori(high.x) + 1):
			for y in range(floori(low.y), floori(high.y) + 1):
				var column := Vector2i(x, y)
				if not _columns.has(column):
					_columns[column] = []
				(_columns[column] as Array).append(triangle)
				for z in range(floori(low.z), floori(high.z) + 1):
					var cell := Vector3i(x, y, z)
					if not _cells.has(cell):
						_cells[cell] = []
					(_cells[cell] as Array).append(triangle)


## How deep the point `at` (in the skeleton's space, inside the region `pose_skin()` kept) is in
## the body, left out the hands and forearms: {"depth": metres (0 outside), "bone", "out"}.
func depth_at(at: Vector3) -> Dictionary:
	var clear := {"depth": 0.0, "bone": &"", "out": Vector3.ZERO}
	var list: Variant = _columns.get(Vector2i(floori(at.x / _CELL), floori(at.y / _CELL)))
	if list == null or HandContact._crossings(_skin, list, at, Vector3.AXIS_Z) % 2 == 0:
		return clear
	var nearest := _nearest(at)
	if nearest[1] < 0 or _limbs[_owner[nearest[1]]] == 1:
		return clear
	return {
		"depth": nearest[0],
		"bone": _skeleton.get_bone_name(_owner[nearest[1]]),
		"out": nearest[2],
	}


# The nearest triangle to `at` within `REACH`: [distance, triangle, the way to it], or
# [REACH, -1, zero].
func _nearest(at: Vector3) -> Array:
	var best := REACH
	var best_triangle := -1
	var best_point := at
	var seen := {}
	var home := Vector3i((at / _CELL).floor())
	for ring in range(0, ceili(REACH / _CELL) + 1):
		if best <= (ring - 1) * _CELL:
			break
		for x in range(-ring, ring + 1):
			for y in range(-ring, ring + 1):
				var edge := absi(x) == ring or absi(y) == ring
				for z in range(-ring, ring + 1) if edge else [-ring, ring]:
					var list: Variant = _cells.get(home + Vector3i(x, y, z))
					if list == null:
						continue
					for triangle: int in list as Array:
						if seen.has(triangle):
							continue
						seen[triangle] = true
						var closest := HandContact.closest_on_triangle(
							at,
							_skin[triangle * 3],
							_skin[triangle * 3 + 1],
							_skin[triangle * 3 + 2]
						)
						var distance := at.distance_to(closest)
						if distance < best:
							best = distance
							best_triangle = triangle
							best_point = closest
	return [best, best_triangle, best_point - at]


func _add_surface(instance: MeshInstance3D, surface: int) -> void:
	var arrays := instance.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if bones.is_empty() or vertices.is_empty():
		return
	var per := bones.size() / vertices.size()
	var skin := instance.skin
	var bind_bones := PackedInt32Array()
	var bind_poses: Array[Transform3D] = []
	for bind in skin.get_bind_count():
		var bone := _skeleton.find_bone(skin.get_bind_name(bind))
		bind_bones.append(bone if bone >= 0 else skin.get_bind_bone(bind))
		bind_poses.append(skin.get_bind_pose(bind))
	var main := PackedInt32Array()
	for vertex in vertices.size():
		var best := 0
		for slot in per:
			if weights[vertex * per + slot] > weights[vertex * per + best]:
				best = slot
		main.append(bind_bones[bones[vertex * per + best]])
	(
		_surfaces
		. append(
			{
				"vertices": vertices,
				"bones": bones,
				"weights": weights,
				"per": per,
				"indices": indices,
				"main": main,
				"bind_bones": bind_bones,
				"bind_poses": bind_poses,
			}
		)
	)


# The surface's vertices skinned in the pose the contact copied, in the skeleton's space.
func _posed(surface: Dictionary) -> PackedVector3Array:
	var bind_bones: PackedInt32Array = surface.bind_bones
	var bind_poses: Array[Transform3D] = surface.bind_poses
	var skins: Array[Transform3D] = []
	for bind in bind_bones.size():
		skins.append(
			_contact.bone_pose(_skeleton.get_bone_name(bind_bones[bind])) * bind_poses[bind]
		)
	var vertices: PackedVector3Array = surface.vertices
	var bones: PackedInt32Array = surface.bones
	var weights: PackedFloat32Array = surface.weights
	var per: int = surface.per
	var posed := PackedVector3Array()
	posed.resize(vertices.size())
	for vertex in vertices.size():
		var sum := Vector3.ZERO
		for slot in per:
			var weight := weights[vertex * per + slot]
			if weight > 0.0:
				sum += weight * (skins[bones[vertex * per + slot]] * vertices[vertex])
		posed[vertex] = sum
	return posed


# The weapon's points in its own space: each vertex once and each triangle's centre.
func _collect_weapon(weapon: Node3D) -> void:
	var inverse := weapon.global_transform.affine_inverse()
	var seen := {}
	for node in weapon.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		var to_weapon := inverse * instance.global_transform
		var faces := instance.mesh.get_faces()
		for triangle in faces.size() / 3:
			var corners: Array[Vector3] = []
			for corner in 3:
				corners.append(to_weapon * faces[triangle * 3 + corner])
			corners.append((corners[0] + corners[1] + corners[2]) / 3.0)
			for at in corners:
				var key := Vector3i((at * 1e3).round())
				if not seen.has(key):
					seen[key] = true
					_points.append(at)

class_name TorsoSkin
extends RefCounted
## The skin of a body's torso as a held long gun's butt meets it (kit #1177; a class of its own
## since kit #1336, when `TwoHandHold` reached the length a script may have): a thinned set of
## points over the torso's triangles, each kept in its main bone's rest space, and how far a
## stock must go forward along its barrel to be clear of them in the pose of this update.
## `TwoHandHold` measures a body once (`measure()`, when the model is put in) and asks for the
## push every frame (`push()`).

## The size of the cells the skin's points are grouped in under each bone, in metres.
const _SKIN_CHUNK := 0.08
## Where round the chest bone (on the rest pose, +X its left) the torso's skin can meet the stock.
const _SKIN_REGION := AABB(Vector3(-0.32, -0.2, 0.0), Vector3(0.47, 0.5, 0.3))
## How far ahead of the stock a point of the skin is still looked at when the gun goes another way
## than its barrel, in metres: the move brings the skin ahead back along the stock (longer than
## any push the arms reach).
const _PUSH_MOST := 0.25
## The least share of a move along the barrel: the hold's pitch limit keeps it over 0.5.
const _LEAST_ALONG := 0.1

# Each point in its main bone's rest space, in groups (a cell of `_SKIN_CHUNK` under one bone):
# the points of group `i` run from `_skin_starts[i]` to the next start, inside `_skin_boxes[i]`,
# so a group the stock is not near is passed over whole.
var _skin_points := PackedVector3Array()
var _skin_starts := PackedInt32Array()
var _skin_boxes: Array[AABB] = []
# The points of each group as an array of their own, turned into the gun's space by one call a
# group rather than one a point (kit #1347).
var _group_points: Array[PackedVector3Array] = []
# The bones the groups ride, in the groups' order: each bone's index, the box round all its
# points and its first group (one more entry ends the last).
var _torso_bones := PackedInt32Array()
var _torso_boxes: Array[AABB] = []
var _torso_starts := PackedInt32Array()
# For each of those bones, the place in them of its parent (below 0: its parent is none of them),
# and its pose of the push being worked out: a bone under another of them takes that one's pose
# and its own local one, not every pose up to the root again (kit #1347).
var _torso_up := PackedInt32Array()
var _torso_posed: Array[Transform3D] = []
var _torso_parents := PackedInt32Array()


## Keeps a thinned set of the torso's skin, each point in its main bone's rest space, for the butt
## to meet (`push()`): the skin of every vertex whose main bone is one of `torso_bones`, one point
## per `skin_spacing` cell, in front of the bone `chest` (an index; below 0: nothing is kept).
func measure(
	skeleton: Skeleton3D, chest: int, torso_bones: Array[StringName], skin_spacing: float
) -> void:
	_skin_points = PackedVector3Array()
	_skin_starts = PackedInt32Array()
	_skin_boxes.clear()
	_group_points.clear()
	_torso_bones = PackedInt32Array()
	_torso_boxes.clear()
	_torso_starts = PackedInt32Array()
	_torso_up = PackedInt32Array()
	_torso_posed.clear()
	if chest < 0:
		return
	var origin := skeleton.get_bone_global_rest(chest).origin
	var torso := {}
	for bone_name in torso_bones:
		var bone := skeleton.find_bone(bone_name)
		if bone >= 0:
			torso[bone] = true
	var cells := {}
	# The nearest level of detail only: the farther ones are the same skin with fewer points.
	for instance in CharacterBodies.near_meshes(skeleton):
		if instance.skin == null or instance.mesh == null:
			continue
		var to_skeleton := skeleton.global_transform.affine_inverse() * instance.global_transform
		var skin := instance.skin
		var binds: Array[Transform3D] = []
		var bind_bones := PackedInt32Array()
		for bind in skin.get_bind_count():
			var bone := skeleton.find_bone(skin.get_bind_name(bind))
			bone = bone if bone >= 0 else skin.get_bind_bone(bind)
			bind_bones.append(bone)
			binds.append(skeleton.get_bone_global_rest(bone) * skin.get_bind_pose(bind))
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if vertices.is_empty() or bones.is_empty():
				continue
			var per := bones.size() / vertices.size()
			# Each vertex on the rest pose, in the skeleton's space, and the bone it follows most.
			var rests := PackedVector3Array()
			var mains := PackedInt32Array()
			for vertex in vertices.size():
				var main := 0
				var rest := Vector3.ZERO
				for slot in per:
					var share := weights[vertex * per + slot]
					if share > weights[vertex * per + main]:
						main = slot
					if share > 0.0:
						rest += share * (binds[bones[vertex * per + slot]] * vertices[vertex])
				rests.append(to_skeleton * rest)
				mains.append(bind_bones[bones[vertex * per + main]])
			# Points over each triangle, a `skin_spacing` apart: a body of few, large triangles has
			# skin far from any vertex, and a stock pushed clear of the vertices alone stood up
			# to 19 mm inside a face (the prototype male, kit #1177).
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				indices = arrays[Mesh.ARRAY_INDEX]
			var corners := indices.size() if not indices.is_empty() else vertices.size()
			for triangle in corners / 3:
				var at: Array[int] = []
				for corner in 3:
					var index := triangle * 3 + corner
					at.append(indices[index] if not indices.is_empty() else index)
				if not (
					torso.has(mains[at[0]]) or torso.has(mains[at[1]]) or torso.has(mains[at[2]])
				):
					continue
				var a := rests[at[0]]
				var b := rests[at[1]]
				var c := rests[at[2]]
				var longest := maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a)))
				var steps := clampi(ceili(longest / maxf(skin_spacing, 0.001)), 1, 12)
				for u in steps + 1:
					for v in steps + 1 - u:
						var w := steps - u - v
						# The point follows the bone of the corner it is nearest.
						var near := at[0] if u >= v and u >= w else (at[1] if v >= w else at[2])
						var bone := mains[near]
						if not torso.has(bone):
							continue
						var rest := (a * u + b * v + c * w) / steps
						_keep(cells, skeleton, bone, rest, rest - origin, skin_spacing)
	# Grouped by bone and, under each bone, by a `_SKIN_CHUNK` cell of its rest space: a push
	# takes each bone's pose once and goes through the points of the chunks near the stock only.
	var by_chunk := {}
	for cell in cells:
		var entry: Array = cells[cell]
		var at: Vector3 = entry[1]
		var inside := Vector3i((at / _SKIN_CHUNK).floor())
		var chunk := Vector4i(entry[0], inside.x, inside.y, inside.z)
		if not by_chunk.has(chunk):
			by_chunk[chunk] = []
		(by_chunk[chunk] as Array).append(at)
	var chunks := by_chunk.keys()
	chunks.sort()
	for chunk: Vector4i in chunks:
		var box := AABB((by_chunk[chunk] as Array)[0] as Vector3, Vector3.ZERO)
		for at: Vector3 in by_chunk[chunk]:
			_skin_points.append(at)
			box = box.expand(at)
		if _torso_bones.is_empty() or _torso_bones[-1] != chunk.x:
			_torso_bones.append(chunk.x)
			_torso_boxes.append(box)
			_torso_starts.append(_skin_boxes.size())
		_torso_boxes[-1] = _torso_boxes[-1].merge(box)
		_skin_starts.append(_skin_points.size() - (by_chunk[chunk] as Array).size())
		_skin_boxes.append(box)
	_skin_starts.append(_skin_points.size())
	_torso_starts.append(_skin_boxes.size())
	for group in _skin_boxes.size():
		_group_points.append(_skin_points.slice(_skin_starts[group], _skin_starts[group + 1]))
	for bone in _torso_bones:
		_torso_up.append(_torso_bones.find(skeleton.get_bone_parent(bone)))
	_torso_parents.resize(skeleton.get_bone_count())
	for bone in _torso_parents.size():
		_torso_parents[bone] = skeleton.get_bone_parent(bone)
	_torso_posed.resize(_torso_bones.size())


# Keeps `rest` (a point of the skin on the rest pose, `ahead` of the chest bone) as its cell's
# point when it is in the region the stock can meet and the frontmost there.
func _keep(
	cells: Dictionary,
	skeleton: Skeleton3D,
	bone: int,
	rest: Vector3,
	ahead: Vector3,
	skin_spacing: float
) -> void:
	# The front half only, round the right shoulder and across to the sternum's left.
	if ahead.z <= 0.0 or not _SKIN_REGION.has_point(ahead):
		return
	var cell := Vector3i((ahead / maxf(skin_spacing, 0.001)).floor())
	if cells.has(cell) and ((cells[cell] as Array)[2] as Vector3).z >= ahead.z:
		return
	cells[cell] = [bone, skeleton.get_bone_global_rest(bone).affine_inverse() * rest, ahead]


## How far the gun goes from the pocket so no point of the torso's skin is inside its stock: a box
## `butt_pad` across and `butt_depth` long from the butt's place, facing back along the barrel,
## kept `butt_margin` off the skin; `gun` is the butt's place and `to_here` the skeleton's, both
## in the hold's space. The gun goes along its barrel, or along `way` (a unit direction in the
## hold's space with no part across the barrel: `TwoHandHold.push_level`, kit #1346). The skin
## points ride their main bones in the pose of this update (the clip, the crouch and the chest
## turn, from the local poses up the parents), so the butt comes to the skin of whichever body
## holds it.
func push(
	skeleton: Skeleton3D,
	gun: Transform3D,
	to_here: Transform3D,
	butt_pad: Vector2,
	butt_depth: float,
	butt_margin: float,
	way := Vector3.ZERO
) -> float:
	if not way.is_zero_approx():
		var local := gun.basis.inverse() * way
		if absf(local.y) > 1e-4:
			var move := Vector2(local.y, maxf(local.z, _LEAST_ALONG)).normalized()
			return _push_along(skeleton, gun, to_here, butt_pad, butt_depth, butt_margin, move)
	var deepest_of_all := 0.0
	var to_gun := gun.affine_inverse() * to_here
	var wide := butt_pad.x * 0.5 + butt_margin
	var high := butt_pad.y * 0.5 + butt_margin
	var stock := AABB(
		Vector3(-wide, -high, -butt_margin),
		Vector3(wide * 2.0, high * 2.0, butt_depth + butt_margin)
	)
	for bone in _torso_bones.size():
		var pose := to_gun * _posed(skeleton, bone)
		var deepest := 0.0
		# The stock's box in the bone's rest space (a box round it): the boxes of the bone and its
		# groups are met against that as they are, not each turned into the gun's space. A point
		# inside the stock is inside both, so the same points are gone through (kit #1347).
		var near := pose.affine_inverse() * stock
		if _torso_boxes[bone].intersects(near):
			for group in range(_torso_starts[bone], _torso_starts[bone + 1]):
				if not _skin_boxes[group].intersects(near):
					continue
				for at in pose * _group_points[group]:
					if stock.has_point(at):
						deepest = maxf(deepest, at.z + butt_margin)
		deepest_of_all = maxf(deepest_of_all, deepest)
	return deepest_of_all


# The push along `move` (up the gun and along its barrel, in the gun's space): each point of the
# skin near the stock forbids the moves that leave it inside the stock, one open run (low, high),
# and the push is the least move forward no run forbids, so the skin ahead of the stock that the
# move brings back along it counts too.
func _push_along(
	skeleton: Skeleton3D,
	gun: Transform3D,
	to_here: Transform3D,
	butt_pad: Vector2,
	butt_depth: float,
	butt_margin: float,
	move: Vector2
) -> float:
	var to_gun := gun.affine_inverse() * to_here
	var wide := butt_pad.x * 0.5 + butt_margin
	var high := butt_pad.y * 0.5 + butt_margin
	var rise := absf(move.x) * _PUSH_MOST
	var near := AABB(
		Vector3(-wide, -high - rise, -butt_margin),
		Vector3(wide * 2.0, (high + rise) * 2.0, butt_depth + butt_margin + _PUSH_MOST)
	)
	var runs := PackedVector2Array()
	for bone in _torso_bones.size():
		var pose := to_gun * _posed(skeleton, bone)
		# As in `push()`: the boxes are met against the near box in the bone's rest space.
		var near_bone := pose.affine_inverse() * near
		if not _torso_boxes[bone].intersects(near_bone):
			continue
		for group in range(_torso_starts[bone], _torso_starts[bone + 1]):
			if not _skin_boxes[group].intersects(near_bone):
				continue
			for at in pose * _group_points[group]:
				if not near.has_point(at) or absf(at.x) >= wide:
					continue
				# Moved by `d` the point is at `at.y - d * move.x` up and `at.z - d * move.y` along.
				var one := (at.y - high) / move.x
				var other := (at.y + high) / move.x
				var low := maxf((at.z - butt_depth) / move.y, minf(one, other))
				var top := minf((at.z + butt_margin) / move.y, maxf(one, other))
				if top > maxf(low, 0.0):
					runs.append(Vector2(low, top))
	runs.sort()
	var pushed := 0.0
	for run in runs:
		if run.x >= pushed:
			break
		pushed = maxf(pushed, run.y)
	return pushed


# The pose of the torso bone at `bone` (its place in `_torso_bones`) in the skeleton's space, kept
# for the bones under it: a bone under another of them takes that one's pose and its own local
# one, the others go up every parent (`HandPoseModifier.global_pose()` written out: a call costs
# more than a line in the web build). The bones are gone through in their order (kit #1347).
func _posed(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var up := _torso_up[bone]
	var posed: Transform3D
	if up >= 0 and up < bone:
		posed = _torso_posed[up] * skeleton.get_bone_pose(_torso_bones[bone])
	else:
		var cursor := _torso_bones[bone]
		posed = Transform3D.IDENTITY
		while cursor >= 0:
			posed = skeleton.get_bone_pose(cursor) * posed
			cursor = _torso_parents[cursor]
	_torso_posed[bone] = posed
	return posed

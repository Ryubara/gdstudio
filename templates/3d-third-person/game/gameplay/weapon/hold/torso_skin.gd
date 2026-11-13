class_name TorsoSkin
extends RefCounted
## The skin of a body's torso as a held long gun's butt meets it (kit #1177; a class of its own
## since kit #1336, when `TwoHandHold` reached the length a script may have): a thinned set of
## points over the torso's triangles, each kept in its main bone's rest space, and how far a
## stock must go forward along its barrel to be clear of them in the pose of this update.
## `TwoHandHold` measures a body once (`measure()`, when the model is put in) and asks for the
## push every frame (`push()`). The stock kept off the skin is the rifle's own shape when the hold
## names its mesh (`measure_stock()`, kit #1346), else a box the pad's size.

## The size of the cells the skin's points are grouped in under each bone, in metres.
const _SKIN_CHUNK := 0.08
## Where round the chest bone (on the rest pose, +X its left) the torso's skin can meet the stock.
const _SKIN_REGION := AABB(Vector3(-0.32, -0.2, 0.0), Vector3(0.47, 0.5, 0.3))
## How long each slice of the stock is along the barrel, in metres.
const _STOCK_STEP := 0.01
## How far ahead of the stock a point of the skin is still looked at, in metres: a push brings the
## skin ahead of the stock back along it (longer than any push the arms reach).
const _PUSH_MOST := 0.25
## How far along the barrel from the butt the rifle's triangles are kept for the stock, in metres.
const _STOCK_KEPT := 0.45

# Each point in its main bone's rest space, in groups (a cell of `_SKIN_CHUNK` under one bone):
# the points of group `i` run from `_skin_starts[i]` to the next start, inside `_skin_boxes[i]`,
# so a group the stock is not near is passed over whole.
var _skin_points := PackedVector3Array()
var _skin_starts := PackedInt32Array()
var _skin_boxes: Array[AABB] = []
# The bones the groups ride, in the groups' order: each bone's index, the box round all its
# points and its first group (one more entry ends the last).
var _torso_bones := PackedInt32Array()
var _torso_boxes: Array[AABB] = []
var _torso_starts := PackedInt32Array()
# The stock's triangles in the butt's space (+Z along the barrel from the butt), three corners
# each, and its slices along the barrel for the depth, margin and pad they were cut for:
# each slice's box across the barrel (min x, max x, min y, max y), grown by the margin and by the
# slices within the margin of it.
var _stock_triangles := PackedVector3Array()
var _slices := PackedVector4Array()
var _sliced_for := Vector4(-1.0, -1.0, -1.0, -1.0)


## Keeps a thinned set of the torso's skin, each point in its main bone's rest space, for the butt
## to meet (`push()`): the skin of every vertex whose main bone is one of `torso_bones`, one point
## per `skin_spacing` cell, in front of the bone `chest` (an index; below 0: nothing is kept).
func measure(
	skeleton: Skeleton3D, chest: int, torso_bones: Array[StringName], skin_spacing: float
) -> void:
	_skin_points = PackedVector3Array()
	_skin_starts = PackedInt32Array()
	_skin_boxes.clear()
	_torso_bones = PackedInt32Array()
	_torso_boxes.clear()
	_torso_starts = PackedInt32Array()
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


## Keeps the stock's own shape for `push()`: the triangles of `mesh` (the rifle's near level; in
## the butt's space by `to_butt`, +Z along the barrel from the butt) that reach into the first
## `_STOCK_KEPT` from the butt. A null mesh: the stock is the `butt_pad` box.
func measure_stock(mesh: Mesh, to_butt: Transform3D) -> void:
	_stock_triangles = PackedVector3Array()
	_sliced_for = Vector4(-1.0, -1.0, -1.0, -1.0)
	if mesh == null:
		return
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		var corners := indices.size() if not indices.is_empty() else vertices.size()
		for triangle in corners / 3:
			var at: Array[Vector3] = []
			for corner in 3:
				var index := triangle * 3 + corner
				at.append(to_butt * vertices[indices[index] if not indices.is_empty() else index])
			if minf(at[0].z, minf(at[1].z, at[2].z)) < _STOCK_KEPT:
				_stock_triangles.append_array(at)


## Whether the stock is the rifle's own shape (`measure_stock()`), not the pad's box.
func has_stock() -> bool:
	return not _stock_triangles.is_empty()


## The stock's slices for `depth` along the barrel and `margin` off the skin (`_slices`): each
## triangle cut by the slices' planes, its corners and its edges' crossings in a slice widening
## that slice's box, then each box grown by `margin` and by the slices within `margin` of it.
## Without the stock's shape every slice is the pad's box, `pad` across (`butt_pad`).
func stock_slices(depth: float, margin: float, pad: Vector2) -> PackedVector4Array:
	var key := Vector4(depth, margin, pad.x, pad.y)
	if _sliced_for == key:
		return _slices
	var count := maxi(ceili(depth / _STOCK_STEP - 1e-6), 1)
	var empty := Vector4(INF, -INF, INF, -INF)
	var raw: Array[Vector4] = []
	raw.resize(count)
	raw.fill(empty if has_stock() else Vector4(-pad.x, pad.x, -pad.y, pad.y) * 0.5)
	for triangle in _stock_triangles.size() / 3:
		for slice in count:
			# The first slice reaches back `margin` behind the butt: the pad's face is there.
			var from := slice * _STOCK_STEP if slice > 0 else -margin
			var to := (slice + 1) * _STOCK_STEP
			for corner in 3:
				var a := _stock_triangles[triangle * 3 + corner]
				var b := _stock_triangles[triangle * 3 + (corner + 1) % 3]
				if a.z >= from and a.z <= to:
					raw[slice] = _widen(raw[slice], a)
				for plane: float in [from, to]:
					if (a.z - plane) * (b.z - plane) < 0.0:
						raw[slice] = _widen(raw[slice], a.lerp(b, (plane - a.z) / (b.z - a.z)))
	var reach := ceili(margin / _STOCK_STEP - 1e-6)
	_slices = PackedVector4Array()
	for slice in count:
		var box := empty
		for other in range(maxi(slice - reach, 0), mini(slice + reach, count - 1) + 1):
			var near := raw[other]
			box = Vector4(
				minf(box.x, near.x), maxf(box.y, near.y), minf(box.z, near.z), maxf(box.w, near.w)
			)
		if box.x <= box.y:
			box += Vector4(-margin, margin, -margin, margin)
		_slices.append(box)
	_sliced_for = key
	return _slices


## How far the gun goes from the pocket along `way` (a unit direction in the hold's space; zero:
## along its barrel) so no point of the torso's skin is inside its stock, kept `butt_margin` off
## the skin; `gun` is the butt's place and `to_here` the skeleton's, both in the hold's space. The
## stock is the rifle's own shape over its first `butt_depth` from the butt (`measure_stock()`;
## its body rises from the pad's toe to the buffer tube, kit #1346), or without it a box
## `butt_pad` across. Each point near the stock forbids the moves that leave it inside a slice
## that covers it, and the push is the least move no point forbids, so the skin ahead of the
## stock that a push brings back along it counts too. The skin points ride their main bones in
## the pose of this update (the clip, the crouch and the chest turn, from the local poses up the
## parents), so the butt comes to the skin of whichever body holds it.
func push(
	skeleton: Skeleton3D,
	gun: Transform3D,
	to_here: Transform3D,
	butt_pad: Vector2,
	butt_depth: float,
	butt_margin: float,
	way := Vector3.ZERO
) -> float:
	var slices := stock_slices(butt_depth, butt_margin, butt_pad)
	var count := slices.size()
	var across := Vector4(INF, -INF, INF, -INF)
	for box in slices:
		across = Vector4(
			minf(across.x, box.x),
			maxf(across.y, box.y),
			minf(across.z, box.z),
			maxf(across.w, box.w)
		)
	if across.x > across.y:
		return 0.0
	# The move in the gun's space: along the barrel (+Z) and up it (+Y), never across (the hold
	# neither rolls the gun nor moves it aside).
	var move := Vector2(0.0, 1.0)
	if not way.is_zero_approx():
		var local := gun.basis.inverse() * way
		move = Vector2(local.y, maxf(local.z, 0.1)).normalized()
	var ahead := count * _STOCK_STEP + butt_margin + _PUSH_MOST
	var reach := AABB(
		Vector3(across.x, across.z - absf(move.x) * _PUSH_MOST, -butt_margin),
		Vector3(across.y - across.x, across.w - across.z + absf(move.x) * _PUSH_MOST * 2.0, ahead)
	)
	var to_gun := gun.affine_inverse() * to_here
	var runs := PackedVector2Array()
	for bone in _torso_bones.size():
		var pose := to_gun * HandPoseModifier.global_pose(skeleton, _torso_bones[bone])
		if not (pose * _torso_boxes[bone]).intersects(reach):
			continue
		for group in range(_torso_starts[bone], _torso_starts[bone + 1]):
			if not (pose * _skin_boxes[group]).intersects(reach):
				continue
			for index in range(_skin_starts[group], _skin_starts[group + 1]):
				var at := pose * _skin_points[index]
				if reach.has_point(at):
					_add_runs(runs, at, slices, butt_margin, move)
	if runs.is_empty():
		return 0.0
	runs.sort()
	var pushed := 0.0
	for run in runs:
		if run.x >= pushed:
			break
		pushed = maxf(pushed, run.y)
	return pushed


# Adds the moves `d` (along `move`, in the gun's space: up the gun, along the barrel) that leave
# the point `at` (in the butt's space) inside a slice of the stock that covers it: the point is
# then at `at.y - d * move.x` up and `at.z - d * move.y` along, the first slice reaching back
# `margin` behind the butt. One open run (low, high) for each slice, kept when it forbids a move
# forward.
static func _add_runs(
	runs: PackedVector2Array, at: Vector3, slices: PackedVector4Array, margin: float, move: Vector2
) -> void:
	for slice in slices.size():
		var box := slices[slice]
		if at.x <= box.x or at.x >= box.y:
			continue
		var from := slice * _STOCK_STEP if slice > 0 else -margin
		var low := (at.z - (slice + 1) * _STOCK_STEP) / move.y
		var high := (at.z - from) / move.y
		if absf(move.x) > 1e-6:
			var one := (at.y - box.w) / move.x
			var other := (at.y - box.z) / move.x
			low = maxf(low, minf(one, other))
			high = minf(high, maxf(one, other))
		elif at.y <= box.z or at.y >= box.w:
			continue
		if high > maxf(low, 0.0):
			runs.append(Vector2(low, high))


static func _widen(box: Vector4, at: Vector3) -> Vector4:
	return Vector4(minf(box.x, at.x), maxf(box.y, at.x), minf(box.z, at.y), maxf(box.w, at.y))

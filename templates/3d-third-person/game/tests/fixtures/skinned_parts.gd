class_name SkinnedParts
extends RefCounted
## How low each part of a skinned model's own mesh is in the pose its skeleton holds now, worked
## out on the CPU: each vertex's height is the weighted sum of its bones' global pose times the
## skin's bind pose. A clip's bone heights say nothing of a thick forearm or thigh; this reads the
## skin itself, as the clip builds do in Blender (`assets/animation/prone/build_prone_clips.py`,
## `floor_mm`).
##
## A vertex belongs to the part of its heaviest bone, or of that bone's nearest ancestor that is a
## part, so a hand is counted with its fingers.
##
## Used by `test_prone_clips.gd`.

var skeleton: Skeleton3D

# For each part: the vertices as flat arrays, and four bone and weight entries a vertex.
var _parts: Dictionary[StringName, Dictionary] = {}
# For each bone a vertex uses: its bind pose (the skin's), set once.
var _binds: Dictionary[int, Transform3D] = {}


## Reads the meshes skinned to `on` and keeps the vertices of `parts` (bone names).
func _init(on: Skeleton3D, parts: Array[StringName]) -> void:
	skeleton = on
	var part_of := _part_of_bones(parts)
	# plain arrays while collecting (they are shared by reference), packed once at the end
	var found: Dictionary[StringName, Dictionary] = {}
	for part in parts:
		found[part] = {"points": [], "bones": [], "weights": []}
	# the meshes drawn up close: a prototype body's farther levels of detail lie inside the nearest
	# one, and their hand is a mitten whose thumb no clip moves
	for instance in CharacterBodies.near_meshes(skeleton):
		if instance.skin == null or instance.mesh == null:
			continue
		var bone_of := _bind_bones(instance.skin)
		for surface in instance.mesh.get_surface_count():
			_collect(instance.mesh.surface_get_arrays(surface), bone_of, part_of, found)
	for part in parts:
		_parts[part] = {
			"points": PackedVector3Array(found[part].points),
			"bones": PackedInt32Array(found[part].bones),
			"weights": PackedFloat32Array(found[part].weights),
		}


## The number of vertices kept for a part.
func size(part: StringName) -> int:
	return (_parts[part].points as PackedVector3Array).size()


## The height of each part's lowest vertex over the floor in the pose now, in metres, in the
## space of the skeleton's parent scene (a model standing at the origin).
func lowest() -> Dictionary[StringName, float]:
	var to_world := skeleton.global_transform
	# a vertex's height is one row of each bone's matrix: the row and the offset, a bone
	var rows: Dictionary[int, Vector3] = {}
	var offsets: Dictionary[int, float] = {}
	for bone: int in _binds:
		var whole := to_world * skeleton.get_bone_global_pose(bone) * _binds[bone]
		rows[bone] = Vector3(whole.basis.x.y, whole.basis.y.y, whole.basis.z.y)
		offsets[bone] = whole.origin.y
	var out: Dictionary[StringName, float] = {}
	for part: StringName in _parts:
		var points: PackedVector3Array = _parts[part].points
		var bones: PackedInt32Array = _parts[part].bones
		var weights: PackedFloat32Array = _parts[part].weights
		var low := INF
		for index in points.size():
			var point := points[index]
			var height := 0.0
			for slot in range(index * 4, index * 4 + 4):
				var weight := weights[slot]
				if weight > 0.0:
					var bone := bones[slot]
					height += weight * (rows[bone].dot(point) + offsets[bone])
			low = minf(low, height)
		out[part] = low
	return out


# The skeleton's bone of each bind of a skin.
func _bind_bones(skin: Skin) -> PackedInt32Array:
	var bone_of := PackedInt32Array()
	for bind in skin.get_bind_count():
		var bone := skin.get_bind_bone(bind)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(bind))
		bone_of.append(bone)
		if bone >= 0:
			_binds[bone] = skin.get_bind_pose(bind)
	return bone_of


# For each bone, the part it belongs to (its own name or its nearest ancestor's), or nothing.
func _part_of_bones(parts: Array[StringName]) -> Dictionary[int, StringName]:
	var part_of: Dictionary[int, StringName] = {}
	for bone in skeleton.get_bone_count():
		var cursor := bone
		while cursor >= 0:
			var bone_name := StringName(skeleton.get_bone_name(cursor))
			if bone_name in parts:
				part_of[bone] = bone_name
				break
			cursor = skeleton.get_bone_parent(cursor)
	return part_of


func _collect(
	arrays: Array,
	bone_of: PackedInt32Array,
	part_of: Dictionary[int, StringName],
	found: Dictionary[StringName, Dictionary]
) -> void:
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if points.is_empty() or bones.is_empty():
		return
	var per_vertex := bones.size() / points.size()
	for index in points.size():
		var first := index * per_vertex
		# the four heaviest bones of the vertex (a mesh may carry eight)
		var order: Array[int] = []
		for slot in per_vertex:
			order.append(first + slot)
		order.sort_custom(func(a: int, b: int) -> bool: return weights[a] > weights[b])
		var heaviest := bone_of[bones[order[0]]]
		if not part_of.has(heaviest):
			continue
		var part: Dictionary = found[part_of[heaviest]]
		var total := 0.0
		for slot in mini(4, per_vertex):
			total += weights[order[slot]]
		(part.points as Array).append(points[index])
		for slot in 4:
			var used := slot < per_vertex and weights[order[slot]] > 0.0
			(part.bones as Array).append(bone_of[bones[order[slot]]] if used else 0)
			(part.weights as Array).append(weights[order[slot]] / total if used else 0.0)

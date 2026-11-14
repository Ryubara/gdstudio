extends RefCounted
## What `solve_trigger_way.gd` (the rifle) and `solve_pistol_trigger_way.gd` (the pistol) share
## with `plan_trigger_way.py`, the planner of a trigger finger's way (kit #1283, kit #1480): the
## dump the planner reads (the index finger's skin as `HandContact` measures it, every bone pose it
## hangs from, the chain from the hand out, the two ends), the planner's way read back, and the
## way written as a `HandPoseWay`, the default body's into its own file, another's into its fit.

const BONES: Array[StringName] = [&"index_01_r", &"index_02_r", &"index_03_r"]
const PARTS: Array[String] = ["index_base", "index_mid", "index_tip"]
## The body whose way is the scene's own; every other body's is in its `HoldFit` file.
const DEFAULT_BODY := "female"


## The finger the planner moves, as JSON: each vertex of the parts `HandContact` counts as its
## bones and its place in each bone's space, every bone pose it hangs from (the contact's
## snapshot), the chain from the hand out, `to_weapon` (the skeleton's space to the weapon's), the
## two ends and the way between them now. The caller adds the weapon and what else is measured.
static func finger(
	contact: HandContact,
	skeleton: Skeleton3D,
	to_weapon: Transform3D,
	grip: Dictionary,
	trigger: Dictionary,
	way: Array[Dictionary]
) -> Dictionary:
	var used := {}
	var parts := {}
	for part in PARTS:
		var list: Array = contact._parts["r"][part]
		var vertices := []
		for index in list.size() / 2:
			var entry: Dictionary = contact._surfaces[list[index * 2]]
			var vertex: int = list[index * 2 + 1]
			var per: int = entry.per
			var rest: Vector3 = (entry.vertices as PackedVector3Array)[vertex]
			var slots := []
			for slot in per:
				var weight: float = (entry.weights as PackedFloat32Array)[vertex * per + slot]
				if weight <= 0.0:
					continue
				var bind: int = (entry.bones as PackedInt32Array)[vertex * per + slot]
				var bone: int = (entry.bind_bones as PackedInt32Array)[bind]
				var local: Vector3 = (entry.bind_poses as Array)[bind] * rest
				used[bone] = true
				slots.append([bone, weight, local.x, local.y, local.z])
			vertices.append(slots)
		parts[part] = vertices
	var chain := []
	for bone_name in BONES:
		var bone := skeleton.find_bone(bone_name)
		var children := []
		for child in skeleton.get_bone_children(bone):
			if not BONES.has(skeleton.get_bone_name(child)):
				children.append([child, numbers(skeleton.get_bone_pose(child))])
				used[child] = true
		(
			chain
			. append(
				{
					"bone": bone,
					"parent": skeleton.get_bone_parent(bone),
					"position": _vector(skeleton.get_bone_pose_position(bone)),
					"rest":
					_quaternion(skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()),
					"children": children,
				}
			)
		)
		used[skeleton.get_bone_parent(bone)] = true
	var poses := {}
	for bone: int in used:
		poses[str(bone)] = numbers(contact._poses[bone])
	var now := []
	for pose in way:
		now.append(_quaternions(pose))
	return {
		"parts": parts,
		"chain": chain,
		"poses": poses,
		"to_weapon": numbers(to_weapon),
		"grip": _quaternions(grip),
		"trigger": _quaternions(trigger),
		"way": now,
	}


## Flat triangles (three corners each) as the planner reads them: x, y, z of every corner.
static func flat(points: PackedVector3Array, moved := Transform3D.IDENTITY) -> Array:
	var out := []
	for point in points:
		var at := moved * point
		out.append_array([at.x, at.y, at.z])
	return out


## Writes `dump` as JSON to `path`.
static func save_dump(dump: Dictionary, path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(dump))
	file.close()
	return OK


## The poses between the two ends that the planner wrote to `path` ({"poses": [{bone: [x, y, z,
## w]}, ...]}), as {bone name: Quaternion} each; empty with an error printed when there are none.
static func read_way(path: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not (parsed as Dictionary).has("poses"):
		printerr("finger_way_files: no way in ", path)
		return found
	for entry: Dictionary in (parsed as Dictionary)["poses"]:
		var pose := {}
		for bone in BONES:
			var q: Array = entry[String(bone)]
			pose[bone] = Quaternion(q[0], q[1], q[2], q[3]).normalized()
		found.append(pose)
	return found


## Writes the poses between `between` as a `HandPoseWay`: the default body's to `own`, another
## body's into its fit (`fit_pattern % body`, `HoldFit.trigger_way`). Returns the file written and
## the error.
static func save_way(
	between: Array[Dictionary], body: String, own: String, fit_pattern: String
) -> Array:
	var way := HandPoseWay.new()
	for rotations in between:
		var pose := HandPose.new()
		var kept: Dictionary[StringName, Quaternion] = {}
		for bone in BONES:
			kept[bone] = rotations[bone]
		pose.rotations = kept
		way.poses.append(pose)
	if body == DEFAULT_BODY:
		return [own, ResourceSaver.save(way, own)]
	var out := fit_pattern % body
	var fit := load(out) as HoldFit
	fit.trigger_way = way
	return [out, ResourceSaver.save(fit, out)]


## The index finger's rotations of a pose.
static func pose_of(pose: HandPose) -> Dictionary:
	var found := {}
	for bone in BONES:
		found[bone] = pose.rotations[bone]
	return found


## A transform as the planner reads it: the basis's columns, then the origin.
static func numbers(t: Transform3D) -> Array:
	return [
		t.basis.x.x,
		t.basis.x.y,
		t.basis.x.z,
		t.basis.y.x,
		t.basis.y.y,
		t.basis.y.z,
		t.basis.z.x,
		t.basis.z.y,
		t.basis.z.z,
		t.origin.x,
		t.origin.y,
		t.origin.z,
	]


static func _vector(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _quaternion(q: Quaternion) -> Array:
	return [q.x, q.y, q.z, q.w]


static func _quaternions(pose: Dictionary) -> Dictionary:
	var out := {}
	for bone: StringName in pose:
		out[String(bone)] = _quaternion(pose[bone])
	return out

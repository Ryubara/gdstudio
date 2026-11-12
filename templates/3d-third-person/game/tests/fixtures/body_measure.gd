class_name BodyMeasure
extends RefCounted
## Plays clips on a character model and measures the body they give (kit #1149): where its feet
## are against the floor, on the skinned mesh, and how deep its limbs go into each other.
##
## It is how a new body (a prototype mannequin, a game's own character on the same rig) is proved
## to play the clip libraries: `tests/assets/test_prototype_mannequins.gd` holds the limits and
## `tools/mannequin/measure_bodies.gd` prints the table.
##
## Limbs are measured as capsules: a segment from a bone to the next, with the radius the body's
## own skin has round it at rest. Two capsules that are not neighbours overlap by their radii
## less the distance between their segments. It is coarser than a mesh test and the same for every
## body, so a new body is read against one already trusted.

## The capsules: name, the bone it starts at, the bone it ends at.
const SEGMENTS := [
	["hips", "pelvis", "spine_02"],
	["chest", "spine_02", "neck_01"],
	["upperarm_l", "upperarm_l", "lowerarm_l"],
	["forearm_l", "lowerarm_l", "hand_l"],
	["thigh_l", "thigh_l", "calf_l"],
	["calf_l", "calf_l", "foot_l"],
	["upperarm_r", "upperarm_r", "lowerarm_r"],
	["forearm_r", "lowerarm_r", "hand_r"],
	["thigh_r", "thigh_r", "calf_r"],
	["calf_r", "calf_r", "foot_r"],
]
## Pairs that share a joint, or lie against each other in every pose (the thighs at the crotch,
## an upper arm on the chest): not measured.
const NEIGHBOURS := [
	["hips", "chest"],
	["hips", "thigh_l"],
	["hips", "thigh_r"],
	["thigh_l", "thigh_r"],
	["chest", "upperarm_l"],
	["chest", "upperarm_r"],
	["upperarm_l", "forearm_l"],
	["upperarm_r", "forearm_r"],
	["thigh_l", "calf_l"],
	["thigh_r", "calf_r"],
]
## The part of the body each bone's skin belongs to, as `limb_overlap.py` cuts the mesh (kit
## #1286): a bone not named takes its parent's part (a twist bone its limb's, a finger its hand's).
const PARTS := {
	"pelvis": "pelvis",
	"spine_02": "chest",
	"neck_01": "head",
	"upperarm_l": "upperarm_l",
	"lowerarm_l": "lowerarm_l",
	"hand_l": "hand_l",
	"thigh_l": "thigh_l",
	"calf_l": "calf_l",
	"foot_l": "foot_l",
	"upperarm_r": "upperarm_r",
	"lowerarm_r": "lowerarm_r",
	"hand_r": "hand_r",
	"thigh_r": "thigh_r",
	"calf_r": "calf_r",
	"foot_r": "foot_r",
}

var model: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer

var _vertices := PackedVector3Array()
var _bones := PackedInt32Array()
var _weights := PackedFloat32Array()
var _binds: Array[Transform3D] = []
var _bind_bone := PackedInt32Array()
var _heaviest := PackedInt32Array()
var _radius := {}
var _rest_overlap := {}
var _foot_vertices := {"l": PackedInt32Array(), "r": PackedInt32Array()}
var _part_of_vertex := PackedStringArray()


## Put `model_path` under `parent` with an `AnimationPlayer` holding `libraries` (name to path).
static func stage(parent: Node, model_path: String, libraries: Dictionary) -> BodyMeasure:
	var out := BodyMeasure.new()
	out.model = (load(model_path) as PackedScene).instantiate()
	parent.add_child(out.model)
	out.skeleton = out.model.find_children("*", "Skeleton3D", true, false)[0]
	out.player = AnimationPlayer.new()
	parent.add_child(out.player)
	out.player.root_node = out.player.get_path_to(out.model)
	for library: StringName in libraries:
		out.player.add_animation_library(library, load(libraries[library]))
	out._read_mesh()
	return out


func free_nodes() -> void:
	player.queue_free()
	model.queue_free()


## Hold `clip` at `at` seconds.
func pose(clip: StringName, at: float) -> void:
	player.play(clip)
	player.seek(at, true)
	player.pause()


## The track paths of `clip` that find no bone on this body.
func missing_tracks(clip: StringName) -> PackedStringArray:
	var missing := PackedStringArray()
	var animation := player.get_animation(clip)
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		if path.get_subname_count() == 0:
			continue
		if skeleton.find_bone(path.get_subname(0)) < 0:
			missing.append(String(path))
	return missing


# The nearest level of detail's mesh (the only mesh of a model without levels), as arrays.
func _read_mesh() -> void:
	var instance: MeshInstance3D = null
	for child in skeleton.find_children("*", "MeshInstance3D", true, false):
		if instance == null or String(child.name).ends_with("LOD0"):
			instance = child
	var skin := instance.skin
	for bind in skin.get_bind_count():
		_binds.append(skin.get_bind_pose(bind))
		var bone_name := skin.get_bind_name(bind)
		_bind_bone.append(
			skeleton.find_bone(bone_name) if bone_name != &"" else skin.get_bind_bone(bind)
		)
	for surface in instance.mesh.get_surface_count():
		var arrays := instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / vertices.size()
		for i in vertices.size():
			_vertices.append(vertices[i])
			var best := 0
			for k in 4:
				_bones.append(bones[i * per + k])
				_weights.append(weights[i * per + k])
				if weights[i * per + k] > weights[i * per + best]:
					best = k
			_heaviest.append(_bind_bone[bones[i * per + best]])
	for segment: Array in SEGMENTS:
		_radius[segment[0]] = _rest_radius(segment)
	for side: String in _foot_vertices:
		var bones := [skeleton.find_bone("foot_" + side), skeleton.find_bone("ball_" + side)]
		for i in _vertices.size():
			if _heaviest[i] in bones:
				_foot_vertices[side].append(i)
	for i in _vertices.size():
		var bone := _heaviest[i]
		while bone >= 0 and not PARTS.has(skeleton.get_bone_name(bone)):
			bone = skeleton.get_bone_parent(bone)
		_part_of_vertex.append(PARTS[skeleton.get_bone_name(bone)] if bone >= 0 else "pelvis")
	skeleton.reset_bone_poses()
	_rest_overlap = _overlaps()


## The skinned vertices in the model's space, in the pose the skeleton holds; all of them, or
## the ones listed.
func skinned(only := PackedInt32Array()) -> PackedVector3Array:
	var matrices: Array[Transform3D] = []
	for bind in _binds.size():
		matrices.append(skeleton.get_bone_global_pose(_bind_bone[bind]) * _binds[bind])
	var count := _vertices.size() if only.is_empty() else only.size()
	var out := PackedVector3Array()
	out.resize(count)
	for n in count:
		var i := n if only.is_empty() else only[n]
		var point := Vector3.ZERO
		for k in 4:
			var weight := _weights[i * 4 + k]
			if weight > 0.0:
				point += (matrices[_bones[i * 4 + k]] * _vertices[i]) * weight
		out[n] = point
	return out


## The height of the lowest skinned vertex of each foot (the foot's and the toes' skin).
func feet_lowest() -> Dictionary:
	var lowest := {"l": INF, "r": INF}
	for side: String in lowest:
		for point in skinned(_foot_vertices[side]):
			lowest[side] = minf(lowest[side], point.y)
	return lowest


## The height of the lowest skinned vertex of each part of the body (`PARTS`) in the pose held,
## in the model's space: {"hand_l": m, ...}.
func lowest_by_part() -> Dictionary:
	var lowest := {}
	var points := skinned()
	for i in points.size():
		var part := _part_of_vertex[i]
		lowest[part] = minf(lowest.get(part, INF), points[i].y)
	return lowest


## Over a clip sampled 30 times a second: the lowest the lower foot's skin goes (`deepest`, m,
## negative is under the floor), the highest it is (`highest`: how far both feet are off the
## floor at once), the deepest two limbs overlap (`overlap`, m) and which two (`pair`).
func measure_clip(clip: StringName) -> Dictionary:
	var length := player.get_animation(clip).length
	var frames := maxi(1, int(round(length * 30.0)))
	var deepest := INF
	var highest := -INF
	var overlap := 0.0
	var pair := ""
	for frame in frames + 1:
		pose(clip, minf(length, frame / 30.0))
		var feet := feet_lowest()
		var lower := minf(feet["l"], feet["r"])
		deepest = minf(deepest, lower)
		highest = maxf(highest, lower)
		var found := limb_overlap()
		if found["depth"] > overlap:
			overlap = found["depth"]
			pair = found["pair"]
	return {"deepest": deepest, "highest": highest, "overlap": overlap, "pair": pair}


## The deepest two limb capsules overlap in the pose held, beyond what the same two overlap at
## rest (a short body's chest and thighs are close in every pose): {"depth": m, "pair": "a x b"}.
func limb_overlap() -> Dictionary:
	var depth := 0.0
	var pair := ""
	var now := _overlaps()
	for key: String in now:
		var inside: float = now[key] - maxf(0.0, _rest_overlap.get(key, 0.0))
		if inside > depth:
			depth = inside
			pair = key
	return {"depth": depth, "pair": pair}


func _overlaps() -> Dictionary:
	var ends := {}
	for segment: Array in SEGMENTS:
		ends[segment[0]] = [_place(segment[1]), _place(segment[2])]
	var out := {}
	for i in SEGMENTS.size():
		for j in range(i + 1, SEGMENTS.size()):
			var a: String = SEGMENTS[i][0]
			var b: String = SEGMENTS[j][0]
			if [a, b] in NEIGHBOURS or [b, a] in NEIGHBOURS:
				continue
			var apart := segment_distance(ends[a][0], ends[a][1], ends[b][0], ends[b][1])
			out["%s x %s" % [a, b]] = _radius[a] + _radius[b] - apart
	return out


## The radius of each capsule (m), as measured on this body's skin at rest.
func radii() -> Dictionary:
	return _radius


func _place(bone: String) -> Vector3:
	return skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin


# The mean distance from a segment to the rest skin of the bones along it (the limb bone and its
# twist bone; for the trunk the bones between the two ends).
func _rest_radius(segment: Array) -> float:
	var from := skeleton.get_bone_global_rest(skeleton.find_bone(segment[1])).origin
	var to := skeleton.get_bone_global_rest(skeleton.find_bone(segment[2])).origin
	var owners := {}
	var start := skeleton.find_bone(segment[1])
	owners[start] = true
	for bone in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(bone)
		if skeleton.get_bone_parent(bone) == start and bone_name.contains("twist"):
			owners[bone] = true
		if segment[0] == "hips" and bone_name == "spine_01":
			owners[bone] = true
		if segment[0] == "chest" and bone_name == "spine_03":
			owners[bone] = true
	var total := 0.0
	var count := 0
	for i in _vertices.size():
		if not owners.has(_heaviest[i]):
			continue
		var point := _skin_rest(i)
		var along := clampf((point - from).dot(to - from) / (to - from).length_squared(), 0.0, 1.0)
		if along <= 0.02 or along >= 0.98:
			continue
		total += point.distance_to(from.lerp(to, along))
		count += 1
	return total / count if count > 0 else 0.0


func _skin_rest(i: int) -> Vector3:
	var point := Vector3.ZERO
	for k in 4:
		var weight := _weights[i * 4 + k]
		if weight > 0.0:
			var bind := _bones[i * 4 + k]
			point += (
				(skeleton.get_bone_global_rest(_bind_bone[bind]) * _binds[bind] * _vertices[i])
				* weight
			)
	return point


## The distance between two segments.
static func segment_distance(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.length_squared()
	var e := d2.length_squared()
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-12 and e <= 1e-12:
		return r.length()
	if a <= 1e-12:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-12:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denominator := a * e - b * b
			if denominator > 1e-12:
				s = clampf((b * f - c * e) / denominator, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)

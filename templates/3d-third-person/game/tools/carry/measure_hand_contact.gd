extends SceneTree
## Measures both hands against the held pistol in every clip the pistol plays (the grip, the aim
## level, up and down, the shot and the reload), on both mannequins, from the skinned mesh worked
## out on the CPU (`PistolClearance`): for the right hand the deepest skin point inside the gun and
## each finger's gap to it (its last joint's nearest skin point), for the left hand its nearest
## skin point (does it touch the gun at all). A point's side is read from the nearest triangle's
## normal, so a point inside a thin part reads as outside the far face: the numbers are for
## comparing holds, the solved-grip test is `test_pistol_hold.gd` (kit #1001).
##
## `godot --headless --path game -s res://tools/carry/measure_hand_contact.gd`
## It prints a `CONTACT` line a clip and model, in millimetres.

const MODELS: Array[String] = [
	"res://assets/characters/mannequin/mannequin_female.glb",
	"res://assets/characters/mannequin/mannequin_male.glb",
]
const CLIPS: Array[StringName] = [
	CharacterClips.PISTOL_IDLE,
	CharacterClips.PISTOL_AIM,
	CharacterClips.PISTOL_AIM_UP,
	CharacterClips.PISTOL_AIM_DOWN,
	CharacterClips.PISTOL_SHOOT,
	CharacterClips.PISTOL_RELOAD,
]
const SAMPLES := 12
const FINGERS: Array[StringName] = [
	&"thumb_03_r", &"index_03_r", &"middle_03_r", &"ring_03_r", &"pinky_03_r"
]


func _initialize() -> void:
	for path in MODELS:
		var holder := Node3D.new()
		get_root().add_child(holder)
		var clearance := PistolClearance.new(holder, path)
		var triangles := _gun_triangles()
		for clip_name in CLIPS:
			var animation := clearance.clip(clip_name)
			var worst_in := 0.0
			var finger_gaps := {}
			for finger in FINGERS:
				finger_gaps[finger] = 0.0
			var left_near := INF
			var left_far := 0.0
			for step in SAMPLES:
				clearance.pose(animation, animation.length * step / SAMPLES)
				var globals: Array[Transform3D] = clearance._globals()
				var seat: Transform3D = (
					globals[clearance.skeleton.find_bone(&"hand_r")] * PistolClearance.SEAT
				)
				var hands := _hand_points(clearance, globals)
				for point: Vector3 in hands["right"]:
					var signed := _signed(seat.affine_inverse() * point, triangles)
					worst_in = maxf(worst_in, -signed)
				for finger in FINGERS:
					var nearest := INF
					for point: Vector3 in hands[finger]:
						nearest = minf(
							nearest, absf(_signed(seat.affine_inverse() * point, triangles))
						)
					finger_gaps[finger] = maxf(finger_gaps[finger], nearest)
				var left := INF
				for point: Vector3 in hands["left"]:
					left = minf(left, absf(_signed(seat.affine_inverse() * point, triangles)))
				left_near = minf(left_near, left)
				left_far = maxf(left_far, left)
			var gaps := PackedStringArray()
			for finger in FINGERS:
				gaps.append(
					"%s %.1f" % [String(finger).get_slice("_", 0), finger_gaps[finger] * 1000.0]
				)
			print(
				(
					"CONTACT %s %s right_in %.1f finger_gap_worst [%s] left_nearest %.1f left_farthest %.1f"
					% [
						path.get_file().get_basename().trim_prefix("mannequin_"),
						clip_name,
						worst_in * 1000.0,
						", ".join(gaps),
						left_near * 1000.0,
						left_far * 1000.0,
					]
				)
			)
		clearance.free_rig()
		holder.free()
	quit()


# The skin points of the right hand, of each finger's last joint and of the left hand, in the
# skeleton's space.
func _hand_points(clearance: PistolClearance, globals: Array[Transform3D]) -> Dictionary:
	var skeleton := clearance.skeleton
	var found := {"right": PackedVector3Array(), "left": PackedVector3Array()}
	var hand_r := skeleton.find_bone(&"hand_r")
	var hand_l := skeleton.find_bone(&"hand_l")
	var finger_bones := {}
	for finger in FINGERS:
		found[finger] = PackedVector3Array()
		finger_bones[skeleton.find_bone(finger)] = finger
	for part: Dictionary in clearance._body:
		var vertices: PackedVector3Array = part["vertices"]
		var bones: PackedInt32Array = part["bones"]
		var weights: PackedFloat32Array = part["weights"]
		var per: int = part["per"]
		var binds: Dictionary = part["binds"]
		for vertex in vertices.size():
			var position := Vector3.ZERO
			var strongest := 0.0
			var owner_bone := -1
			for slot in per:
				var weight := weights[vertex * per + slot]
				if weight <= 0.0:
					continue
				var entry: Array = binds[bones[vertex * per + slot]]
				position += (
					weight * ((globals[entry[0]] * (entry[1] as Transform3D)) * vertices[vertex])
				)
				if weight > strongest:
					strongest = weight
					owner_bone = entry[0]
			if owner_bone < 0:
				continue
			if _under(skeleton, owner_bone, hand_r):
				found["right"].append(position)
			elif _under(skeleton, owner_bone, hand_l):
				found["left"].append(position)
			if finger_bones.has(owner_bone):
				found[finger_bones[owner_bone]].append(position)
	return found


func _under(skeleton: Skeleton3D, bone: int, top: int) -> bool:
	var cursor := bone
	while cursor >= 0:
		if cursor == top:
			return true
		cursor = skeleton.get_bone_parent(cursor)
	return false


func _gun_triangles() -> PackedVector3Array:
	var gun := (load(PistolClearance.PISTOL) as PackedScene).instantiate() as Node3D
	var faces := PackedVector3Array()
	for node in gun.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var to_root := Transform3D.IDENTITY
		var cursor: Node = instance
		while cursor != null and cursor != gun:
			to_root = (cursor as Node3D).transform * to_root
			cursor = cursor.get_parent()
		for vertex in instance.mesh.get_faces():
			faces.append(to_root * vertex)
	gun.free()
	return faces


# The distance from `point` to the nearest triangle, negative behind that triangle's face.
func _signed(point: Vector3, faces: PackedVector3Array) -> float:
	var best := INF
	var side := 1.0
	for index in range(0, faces.size(), 3):
		var a := faces[index]
		var b := faces[index + 1]
		var c := faces[index + 2]
		var closest := _closest_on_triangle(point, a, b, c)
		var d := point.distance_squared_to(closest)
		if d < best:
			best = d
			var normal := (b - a).cross(c - a).normalized()
			side = 1.0 if (point - closest).dot(normal) >= 0.0 else -1.0
	return sqrt(best) * side


func _closest_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() > 0.0:
		var on_plane := p - normal * ((p - a).dot(normal) / normal.length_squared())
		var weights := Geometry3D.get_triangle_barycentric_coords(on_plane, a, b, c)
		if weights.x >= 0.0 and weights.y >= 0.0 and weights.z >= 0.0:
			return on_plane
	var best := Geometry3D.get_closest_point_to_segment(p, a, b)
	for edge: Vector3 in [
		Geometry3D.get_closest_point_to_segment(p, b, c),
		Geometry3D.get_closest_point_to_segment(p, c, a),
	]:
		if p.distance_squared_to(edge) < p.distance_squared_to(best):
			best = edge
	return best

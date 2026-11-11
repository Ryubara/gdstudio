extends SceneTree
## Measures both hands against the held pistol in every clip the pistol plays (the grip, the aim
## level, up and down, the shot and the reload), on both mannequins, from the skinned mesh worked
## out on the CPU (`PistolClearance`): for each hand the deepest skin point inside the gun, for
## each finger of the right hand its gap to it (its last joint's nearest skin point), and for the
## left hand the least and the most gap over the clip (does it reach the gun). A point's side is
## read from the nearest triangle's normal, so a point inside a thin part reads as outside the far
## face: the numbers are for comparing holds; the solved grip's own test comes with kit #1001.
##
## `godot --headless --path game -s res://tools/carry/measure_hand_contact.gd`
## It prints a `CONTACT` line a clip and model, in millimetres.
##
## With `-- rifle` after the command it measures the rifle's `TwoHandHold` instead (kit #889): the
## game's player given the rifle, its modifiers' final pose read in `skeleton_updated`, at the low
## ready, the aim level, up and down, on both mannequins; a `RIFLE` line a pose with each hand's
## deepest point inside the rifle and each finger's gap to it (its last joint's nearest skin point).

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
const SAMPLES := 8
const RIFLE := "res://assets/weapons/rifle/rifle.glb"
## The rifle's poses: how far it is up at the shoulder and the view's pitch in degrees.
const RIFLE_POSES: Array = [
	["low ready", 0.0, 0.0], ["aim", 1.0, 0.0], ["aim up", 1.0, 30.0], ["aim down", 1.0, -30.0]
]
const LEFT_FINGERS: Array[StringName] = [
	&"thumb_03_l", &"index_03_l", &"middle_03_l", &"ring_03_l", &"pinky_03_l"
]
const FINGERS: Array[StringName] = [
	&"thumb_03_r", &"index_03_r", &"middle_03_r", &"ring_03_r", &"pinky_03_r"
]


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("rifle"):
		_measure_rifle.call_deferred()
		return
	for path in MODELS:
		var holder := Node3D.new()
		get_root().add_child(holder)
		var clearance := PistolClearance.new(holder, path)
		var triangles := _gun_triangles()
		var model := path.get_file().get_basename().trim_prefix("mannequin_")
		for clip_name in CLIPS:
			_measure(clearance, triangles, model, clip_name)
		clearance.free_rig()
		holder.free()
	quit()


# One clip: the worst over its samples of each hand's depth into the gun and gap to it.
func _measure(
	clearance: PistolClearance, triangles: PackedVector3Array, model: String, clip_name: StringName
) -> void:
	var animation := clearance.clip(clip_name)
	var right_in := 0.0
	var left_in := 0.0
	var left_gap_least := INF
	var left_gap_most := 0.0
	var finger_gaps := {}
	for finger in FINGERS:
		finger_gaps[finger] = 0.0
	for step in SAMPLES:
		clearance.pose(animation, animation.length * step / SAMPLES)
		var globals: Array[Transform3D] = clearance._globals()
		var hand := globals[clearance.skeleton.find_bone(&"hand_r")]
		var to_gun := (hand * PistolClearance.SEAT).affine_inverse()
		var hands := _hand_points(clearance, globals)
		var right := _depth_and_gap(hands["right"], to_gun, triangles)
		right_in = maxf(right_in, right.x)
		for finger in FINGERS:
			var gap := _depth_and_gap(hands[finger], to_gun, triangles).y
			finger_gaps[finger] = maxf(finger_gaps[finger], gap)
		var left := _depth_and_gap(hands["left"], to_gun, triangles)
		left_in = maxf(left_in, left.x)
		left_gap_least = minf(left_gap_least, left.y)
		left_gap_most = maxf(left_gap_most, left.y)
	var gaps := PackedStringArray()
	for finger in FINGERS:
		gaps.append("%s %.1f" % [String(finger).get_slice("_", 0), finger_gaps[finger] * 1000.0])
	print(
		(
			"CONTACT %s %s right: in %.1f, finger gaps [%s]; left: in %.1f, gap %.1f to %.1f"
			% [
				model,
				clip_name,
				right_in * 1000.0,
				", ".join(gaps),
				left_in * 1000.0,
				left_gap_least * 1000.0,
				left_gap_most * 1000.0,
			]
		)
	)


# The deepest of `points` inside the gun (x) and the gap of the nearest one outside it (y; 0 when
# one is inside), in metres. Points more than 30 cm from the gun's origin are far from it anyway.
func _depth_and_gap(
	points: PackedVector3Array, to_gun: Transform3D, triangles: PackedVector3Array
) -> Vector2:
	var deepest := 0.0
	var gap := INF
	for point in points:
		var local := to_gun * point
		if local.length() > 0.3:
			continue
		var signed := _signed(local, triangles)
		deepest = maxf(deepest, -signed)
		gap = minf(gap, maxf(signed, 0.0))
	return Vector2(deepest, gap if gap < INF else 0.3)


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
			# Godot's front faces wind clockwise: this normal points out of the part.
			var normal := (c - a).cross(b - a).normalized()
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


# The rifle's two-handed hold on the game's player, on each mannequin and in each pose.
func _measure_rifle() -> void:
	var triangles := _triangles_of(RIFLE)
	for path in MODELS:
		var player := (
			(load("res://gameplay/player/player.tscn") as PackedScene).instantiate() as Player
		)
		player.start_at_spawn = false
		get_root().add_child(player)
		player.set_physics_process(false)
		var slot := player.model
		if not path.ends_with("female.glb"):
			var old := slot.rig()
			slot.remove_child(old)
			old.free()
			slot.add_child((load(path) as PackedScene).instantiate())
		for _frame in 3:
			await process_frame
		player.loadout.give(load("res://gameplay/weapon/rifle.tres") as WeaponDef, 0)
		for _tick in 4:
			player.loadout.tick(1.0)
		var hold := slot.get_node("RifleHeld") as TwoHandHold
		var clearance := PistolClearance.new(get_root(), path)
		var model := path.get_file().get_basename().trim_prefix("mannequin_")
		for pose: Array in RIFLE_POSES:
			player.aim_amount = pose[1]
			player.view_pitch = deg_to_rad(pose[2])
			for _frame in 30:
				await process_frame
			var skeleton := slot.skeleton()
			await skeleton.skeleton_updated
			var globals: Array[Transform3D] = []
			for bone in skeleton.get_bone_count():
				globals.append(skeleton.get_bone_global_pose(bone))
			var gun := hold.find_child("Near", true, false) as Node3D
			var to_gun := (
				(skeleton.global_transform.affine_inverse() * gun.global_transform).affine_inverse()
			)
			_report_rifle(model, pose[0], clearance, globals, to_gun, triangles)
		# Out of the signal's emission first: freeing the skeleton inside it crashes the engine.
		await process_frame
		clearance.free_rig()
		player.free()
	quit()


func _report_rifle(
	model: String,
	pose_name: String,
	clearance: PistolClearance,
	globals: Array[Transform3D],
	to_gun: Transform3D,
	triangles: PackedVector3Array
) -> void:
	var saved := FINGERS
	var hands := _hand_points(clearance, globals)
	var left_hands := _hand_points_of(clearance, globals, LEFT_FINGERS)
	var line := "RIFLE %s %s" % [model, pose_name]
	for side: Array in [["right", hands, saved], ["left", left_hands, LEFT_FINGERS]]:
		var points: Dictionary = side[1]
		var whole := _depth_and_gap(points[side[0]], to_gun, triangles)
		var gaps := PackedStringArray()
		for finger: StringName in side[2]:
			var finger_hit := _depth_and_gap(points[finger], to_gun, triangles)
			(
				gaps
				. append(
					(
						"%s %+.1f"
						% [
							String(finger).get_slice("_", 0),
							(finger_hit.y if finger_hit.x <= 0.0 else -finger_hit.x) * 1000.0,
						]
					)
				)
			)
		line += " | %s: in %.1f, fingers [%s]" % [side[0], whole.x * 1000.0, ", ".join(gaps)]
	print(line)


# `_hand_points` with another list of finger bones (the left hand's).
func _hand_points_of(
	clearance: PistolClearance, globals: Array[Transform3D], fingers: Array[StringName]
) -> Dictionary:
	var skeleton := clearance.skeleton
	var found := {"right": PackedVector3Array(), "left": PackedVector3Array()}
	var finger_bones := {}
	for finger in fingers:
		found[finger] = PackedVector3Array()
		finger_bones[skeleton.find_bone(finger)] = finger
	var all := _hand_points(clearance, globals)
	found["left"] = all["left"]
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
			if finger_bones.has(owner_bone):
				found[finger_bones[owner_bone]].append(position)
	return found


func _triangles_of(path: String) -> PackedVector3Array:
	var gun := (load(path) as PackedScene).instantiate() as Node3D
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

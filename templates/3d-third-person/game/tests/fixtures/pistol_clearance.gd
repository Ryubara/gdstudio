class_name PistolClearance
extends RefCounted
## Measures how far the held pistol sinks into the body in a pose, without a scene tree running:
## the mannequin's skinned vertices and the pistol's vertices are worked out on the CPU from the
## bone poses a clip (and the grip clip over the gripping hand) gives the skeleton. A pistol
## point is inside the body when it is behind the plane of the nearest body vertex (the dot of
## the offset with that vertex's normal is negative); the gripping arm is left out, since the hand
## is meant to touch the pistol.
##
## Used by `test_pistol_clearance.gd` and `tools/carry/measure_clearance.gd`.

const PISTOL := "res://assets/weapons/pistol/pistol.glb"
## The pistol on `hand_r` (its seat is the first child's transform) and the grip pose whose
## `turns` bend the wrist under it (kit #1001).
const HELD := "res://assets/weapons/pistol/pistol_held.tscn"
const GRIP_POSE := "res://gameplay/weapon/hold/pistol_grip_pose.tres"
## The hold scene, whose `carry_arm_out` holds the weapon's arm out from the thigh.
const HOLD := "res://gameplay/weapon/hold/weapon_hold.tscn"
const LIBRARIES: Dictionary[StringName, String] = {
	&"ual1": "res://assets/animation/universal/ual1.glb",
	&"ual2": "res://assets/animation/universal/ual2.glb",
}

var skeleton: Skeleton3D
var rig: Node3D

var _seat := Transform3D.IDENTITY
var _turns: Dictionary[StringName, Quaternion] = {}
var _carry_arm: StringName = &""
var _carry_arm_out := 0.0
var _body: Array[Dictionary] = []
var _pistol: PackedVector3Array = PackedVector3Array()
var _skip: PackedByteArray = PackedByteArray()
var _libraries := {}


## Builds the measurement for the model at `model_path`. `holder` is a node of a running tree.
func _init(holder: Node, model_path: String) -> void:
	rig = (load(model_path) as PackedScene).instantiate() as Node3D
	holder.add_child(rig)
	skeleton = rig.get_node("Armature/Skeleton3D") as Skeleton3D
	var held := (load(HELD) as PackedScene).instantiate()
	_seat = (held.get_child(0) as Node3D).transform
	held.free()
	if ResourceLoader.exists(GRIP_POSE):
		_turns = (load(GRIP_POSE) as HandPose).turns
	if ResourceLoader.exists(HOLD):
		var hold := (load(HOLD) as PackedScene).instantiate()
		_carry_arm = hold.get(&"carry_arm")
		_carry_arm_out = hold.get(&"carry_arm_out")
		hold.free()
	_collect_body()
	_collect_pistol()
	_skip.resize(skeleton.get_bone_count())
	var arm := skeleton.find_bone(&"clavicle_r")
	for bone in skeleton.get_bone_count():
		var cursor := bone
		while cursor >= 0 and cursor != arm:
			cursor = skeleton.get_bone_parent(cursor)
		_skip[bone] = 1 if cursor == arm else 0


func free_rig() -> void:
	rig.get_parent().remove_child(rig)
	rig.free()


## The clip (`ual1/Walk`) at `time`, as an animation.
func clip(name: StringName) -> Animation:
	var parts := String(name).split("/")
	if not _libraries.has(parts[0]):
		_libraries[parts[0]] = load(LIBRARIES[StringName(parts[0])]) as AnimationLibrary
	return (_libraries[parts[0]] as AnimationLibrary).get_animation(parts[1])


## Puts the pose of `animation` at `time` on the skeleton, then the pose of `grip` at `grip_time`
## on each of `grip_bones` and every bone under them (no grip clip: the clip alone).
func pose(
	animation: Animation,
	time: float,
	grip: Animation = null,
	grip_bones: Array[StringName] = [],
	grip_time := 0.0
) -> void:
	skeleton.reset_bone_poses()
	_apply(animation, time, null)
	if grip != null:
		var covered := {}
		for root in grip_bones:
			var start := skeleton.find_bone(root)
			for bone in skeleton.get_bone_count():
				var cursor := bone
				while cursor >= 0 and cursor != start:
					cursor = skeleton.get_bone_parent(cursor)
				if cursor == start and start >= 0:
					covered[bone] = true
		_apply(grip, grip_time, covered)
	if _carry_arm != &"" and grip != null:
		HandPoseModifier.swing_out(skeleton, _carry_arm, _carry_arm_out)
	for bone_name in _turns:
		var bone := skeleton.find_bone(bone_name)
		if bone >= 0:
			skeleton.set_bone_pose_rotation(
				bone, skeleton.get_bone_pose_rotation(bone) * _turns[bone_name]
			)


## The deepest a pistol point is inside the body in the pose now, in metres (0 or less: clear; -1
## when no point is within 10 cm of the body).
func depth() -> float:
	var globals := _globals()
	var skinned := _skin(globals)
	var seat: Transform3D = globals[skeleton.find_bone(&"hand_r")] * _seat
	var near_body: Array[int] = []
	for index in skinned.positions.size():
		if seat.origin.distance_squared_to(skinned.positions[index]) < 0.2:
			near_body.append(index)
	var worst := -1.0
	for point in _pistol:
		var at := seat * point
		var nearest := 0.01
		var inside := -1.0
		for index in near_body:
			var d := at.distance_squared_to(skinned.positions[index])
			if d < nearest:
				nearest = d
				inside = -(at - skinned.positions[index]).dot(skinned.normals[index])
		if nearest < 0.01:
			worst = maxf(worst, inside)
	return worst


## How deep a single point (in the skeleton's space) is inside the body in the pose now, in metres
## (negative: outside), for the nearest body vertex within 10 cm; -1 when none is that near.
func depth_at(point: Vector3) -> float:
	var skinned := _skin(_globals())
	var nearest := 0.01
	var inside := -1.0
	for index in skinned.positions.size():
		var d := point.distance_squared_to(skinned.positions[index])
		if d < nearest:
			nearest = d
			inside = -(point - skinned.positions[index]).dot(skinned.normals[index])
	return inside


func _apply(animation: Animation, time: float, only: Variant) -> void:
	for track in animation.get_track_count():
		var bone := skeleton.find_bone(
			String(animation.track_get_path(track).get_concatenated_subnames())
		)
		if bone < 0 or (only != null and not (only as Dictionary).has(bone)):
			continue
		match animation.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(
					bone, animation.rotation_track_interpolate(track, time)
				)
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(
					bone, animation.position_track_interpolate(track, time)
				)


# Every bone's pose in the skeleton's space, from the local poses up the chain (the skeleton works
# its own out later, not at once after a pose is set).
func _globals() -> Array[Transform3D]:
	var found: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(bone)
		var local := skeleton.get_bone_pose(bone)
		found.append(found[parent] * local if parent >= 0 else local)
	return found


func _collect_body() -> void:
	for instance in CharacterBodies.near_meshes(rig):
		var skin := instance.skin
		if skin == null or instance.mesh == null:
			continue
		var binds := {}
		for index in skin.get_bind_count():
			var bone := skeleton.find_bone(skin.get_bind_name(index))
			if bone < 0:
				bone = skin.get_bind_bone(index)
			binds[index] = [bone, skin.get_bind_pose(index)]
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / maxi(vertices.size(), 1)
			(
				_body
				. append(
					{
						"vertices": vertices,
						"normals": normals,
						"bones": bones,
						"weights": weights,
						"per": per,
						"binds": binds,
					}
				)
			)


func _collect_pistol() -> void:
	var gun := (load(PISTOL) as PackedScene).instantiate() as Node3D
	var holder := Node3D.new()
	holder.add_child(gun)
	for node in gun.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var to_root := _relative(instance, gun)
		var seen := {}
		for vertex in instance.mesh.get_faces():
			var key := Vector3i((vertex * 100.0).round())
			if not seen.has(key):
				seen[key] = true
				_pistol.append(to_root * vertex)
	holder.free()


func _relative(node: Node3D, root: Node3D) -> Transform3D:
	var found := Transform3D.IDENTITY
	var cursor := node
	while cursor != null and cursor != root:
		found = cursor.transform * found
		cursor = cursor.get_parent() as Node3D
	return found


# The body's vertices and normals in the skeleton's space in the pose now, the gripping arm's
# left out.
func _skin(globals: Array[Transform3D]) -> Dictionary:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	for part in _body:
		var vertices: PackedVector3Array = part["vertices"]
		var vertex_normals: PackedVector3Array = part["normals"]
		var bones: PackedInt32Array = part["bones"]
		var weights: PackedFloat32Array = part["weights"]
		var per: int = part["per"]
		var binds: Dictionary = part["binds"]
		var skins := {}
		for index in binds:
			var entry: Array = binds[index]
			skins[index] = globals[entry[0]] * (entry[1] as Transform3D)
		for vertex in vertices.size():
			var position := Vector3.ZERO
			var normal := Vector3.ZERO
			var strongest := 0.0
			var owner_bone := -1
			for slot in per:
				var weight := weights[vertex * per + slot]
				if weight <= 0.0:
					continue
				var bind_index := bones[vertex * per + slot]
				var transform: Transform3D = skins[bind_index]
				position += weight * (transform * vertices[vertex])
				normal += weight * (transform.basis * vertex_normals[vertex])
				if weight > strongest:
					strongest = weight
					owner_bone = (binds[bind_index] as Array)[0]
			if owner_bone >= 0 and _skip[owner_bone] == 1:
				continue
			positions.append(position)
			normals.append(normal.normalized())
	return {"positions": positions, "normals": normals}

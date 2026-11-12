## Measures each body part of the template's bodies in the rest pose (kit #1187), the numbers the
## hit zones (`character_dressed.tscn`) and the ragdoll's capsules (`RagdollBodies`) are sized
## from: for each part, the skin whose main bone is the part's bone (or a twist leaf under it), in
## that bone's own space (Y along the bone), as where along the bone it starts and ends and how
## far from the bone's line it reaches (the 90th percentile and the most), and the bone's length.
##
## `<godot> --headless --path game -s res://tools/mannequin/measure_segments.gd`
extends SceneTree

const BODIES: Dictionary[String, String] = {
	"quaternius_female": "res://assets/characters/mannequin/mannequin_female.glb",
	"quaternius_male": "res://assets/characters/mannequin/mannequin_male.glb",
	"form_female": "res://assets/characters/prototype/form_female.glb",
	"form_male": "res://assets/characters/prototype/form_male.glb",
}
## Each part: the bone its zone or capsule hangs on, and the bones whose skin counts as the part's.
const PARTS: Dictionary[String, Array] = {
	"head": [&"Head", [&"Head"]],
	"neck": [&"neck_01", [&"neck_01"]],
	"chest": [&"spine_03", [&"spine_03", &"spine_02"]],
	"pelvis": [&"pelvis", [&"pelvis", &"spine_01"]],
	"upperarm_l": [&"upperarm_l", [&"upperarm_l", &"upperarm_twist_01_l"]],
	"lowerarm_l": [&"lowerarm_l", [&"lowerarm_l", &"lowerarm_twist_01_l"]],
	"hand_l": [&"hand_l", [&"hand_l"]],
	"thigh_l": [&"thigh_l", [&"thigh_l", &"thigh_twist_01_l"]],
	"calf_l": [&"calf_l", [&"calf_l"]],
	"foot_l": [&"foot_l", [&"foot_l", &"ball_l"]],
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	for body: String in BODIES:
		var rig := (load(BODIES[body]) as PackedScene).instantiate() as Node3D
		root.add_child(rig)
		var skeleton := rig.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		print("== ", body, "  height ", snappedf(_top(skeleton), 0.001))
		for part: String in PARTS:
			_part(skeleton, part)
		rig.free()
	quit()


func _top(skeleton: Skeleton3D) -> float:
	var top := 0.0
	for mesh in _meshes(skeleton):
		top = maxf(top, mesh.get_aabb().end.y)
	return top


func _meshes(skeleton: Skeleton3D) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		# The prototype bodies carry three levels of detail; only the nearest is measured.
		if instance.name.contains("LOD") and not instance.name.ends_with("LOD0"):
			continue
		found.append(instance)
	return found


func _part(skeleton: Skeleton3D, part: String) -> void:
	var bone := skeleton.find_bone(PARTS[part][0])
	var members := {}
	for bone_name: StringName in PARTS[part][1]:
		if skeleton.find_bone(bone_name) >= 0:
			members[skeleton.find_bone(bone_name)] = true
	var to_bone := skeleton.get_bone_global_rest(bone).affine_inverse()
	var along := PackedFloat32Array()
	var out := PackedFloat32Array()
	var box := AABB()
	var boxed := false
	for instance in _meshes(skeleton):
		var to_skeleton := skeleton.global_transform.affine_inverse() * instance.global_transform
		var skin := instance.skin
		var bind_bones := PackedInt32Array()
		for bind in skin.get_bind_count():
			var found := skeleton.find_bone(skin.get_bind_name(bind))
			bind_bones.append(found if found >= 0 else skin.get_bind_bone(bind))
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var slots: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var shares: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := slots.size() / points.size()
			for vertex in points.size():
				var best := -1
				var best_share := 0.0
				for slot in per:
					if shares[vertex * per + slot] > best_share:
						best_share = shares[vertex * per + slot]
						best = bind_bones[slots[vertex * per + slot]]
				if not members.has(best):
					continue
				var local := to_bone * (to_skeleton * points[vertex])
				along.append(local.y)
				box = box.expand(local) if boxed else AABB(local, Vector3.ZERO)
				boxed = true
				out.append(Vector2(local.x, local.z).length())
	along.sort()
	out.sort()
	var length := 0.0
	for child in skeleton.get_bone_children(bone):
		length = maxf(length, skeleton.get_bone_rest(child).origin.length())
	if out.is_empty():
		print("  %-11s no skin" % part)
		return
	print(
		(
			"  %-11s bone %.3f  along %.3f..%.3f  radius p90 %.3f max %.3f  centre %s  (%d vertices)"
			% [
				part,
				length,
				along[0],
				along[along.size() - 1],
				out[int(out.size() * 0.9)],
				out[out.size() - 1],
				(box.get_center() * 1000.0).round() / 1000.0,
				out.size()
			]
		)
	)

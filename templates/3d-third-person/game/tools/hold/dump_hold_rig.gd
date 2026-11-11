## Writes what the pistol hold solver needs as one JSON file (kit #1001): for each mannequin the
## skeleton (names, parents, rests), the skin of both arms from the elbow down (rest vertices,
## bones, weights, bind poses, triangles) and every bone's pose in the clips the pistol is held
## in, as Godot plays them; and the pistol's triangles, sockets and seat. The solver
## (`solve_pistol_hold.py`) works on this dump, never on a clip opened in Blender, whose hand
## sits 2 to 3 cm from Godot's (kit docs, tools/blender/weapons.md).
##
## `<godot> --headless --path game -s res://tools/hold/dump_hold_rig.gd -- <out.json>`
extends SceneTree

const POSES: Array = [
	[&"ual1/Pistol_Idle", [0.0, 0.5, 1.0]],
	[&"ual1/Pistol_Aim_Neutral", [0.0, 0.16]],
	[&"ual1/Pistol_Aim_Up", [0.0, 0.16]],
	[&"ual1/Pistol_Aim_Down", [0.0, 0.16]],
	[&"ual1/Pistol_Shoot", [0.0, 0.05, 0.1, 0.2]],
	[&"ual1/Pistol_Reload", [0.0, 0.4, 0.8, 1.05, 1.2]],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var out := {"models": {}, "pistol": {}}
	for model: String in HoldStage.MODELS:
		var stage := HoldStage.make(root, model, false)
		out.models[model] = _model(stage)
		if model == "female":
			out.pistol = _pistol(stage)
		stage.free()
	var path := OS.get_cmdline_user_args()[0]
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(out))
	file.close()
	print("wrote ", path)
	quit()


func _model(stage: HoldStage) -> Dictionary:
	var skeleton := stage.skeleton
	var bones := []
	for bone in skeleton.get_bone_count():
		(
			bones
			. append(
				{
					"name": skeleton.get_bone_name(bone),
					"parent": skeleton.get_bone_parent(bone),
					"rest": _xf(skeleton.get_bone_rest(bone)),
				}
			)
		)
	var poses := {}
	for entry: Array in POSES:
		for time: float in entry[1]:
			stage.pose(entry[0], time)
			var locals := []
			for bone in skeleton.get_bone_count():
				locals.append(_xf(skeleton.get_bone_pose(bone)))
			poses["%s@%.2f" % [entry[0], time]] = locals
	return {"bones": bones, "poses": poses, "skin": _skin(skeleton)}


# The skin whose main bone is a forearm, a hand or a finger: vertices, four bones (as skeleton
# indices) and weights each, the bind pose of every bone, and the triangles among them.
func _skin(skeleton: Skeleton3D) -> Dictionary:
	var arm := {}
	for side in ["r", "l"]:
		var start := skeleton.find_bone("lowerarm_" + side)
		for bone in skeleton.get_bone_count():
			var cursor := bone
			while cursor >= 0 and cursor != start:
				cursor = skeleton.get_bone_parent(cursor)
			if cursor >= 0:
				arm[bone] = true
	var vertices := []
	var bone_ids := []
	var weights := []
	var triangles := []
	var binds := {}
	for node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var skin := instance.skin
		var bind_bones := PackedInt32Array()
		for bind in skin.get_bind_count():
			var bone := skeleton.find_bone(skin.get_bind_name(bind))
			bind_bones.append(bone if bone >= 0 else skin.get_bind_bone(bind))
			binds[str(bind_bones[bind])] = _xf(skin.get_bind_pose(bind))
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var slots: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var shares: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var per := slots.size() / points.size()
			var kept := {}
			for vertex in points.size():
				var best := -1
				var best_share := 0.0
				for slot in per:
					if shares[vertex * per + slot] > best_share:
						best_share = shares[vertex * per + slot]
						best = bind_bones[slots[vertex * per + slot]]
				if not arm.has(best):
					continue
				kept[vertex] = vertices.size()
				vertices.append([points[vertex].x, points[vertex].y, points[vertex].z])
				var four := []
				var four_shares := []
				for slot in 4:
					var used := slot < per and shares[vertex * per + slot] > 0.0
					four.append(bind_bones[slots[vertex * per + slot]] if used else 0)
					four_shares.append(shares[vertex * per + slot] if used else 0.0)
				bone_ids.append(four)
				weights.append(four_shares)
			for triangle in indices.size() / 3:
				var a := indices[triangle * 3]
				var b := indices[triangle * 3 + 1]
				var c := indices[triangle * 3 + 2]
				if kept.has(a) and kept.has(b) and kept.has(c):
					triangles.append([kept[a], kept[b], kept[c]])
	return {
		"vertices": vertices,
		"bones": bone_ids,
		"weights": weights,
		"triangles": triangles,
		"binds": binds,
	}


func _pistol(stage: HoldStage) -> Dictionary:
	var pistol := stage.pistol
	var inverse := pistol.global_transform.affine_inverse()
	var triangles := []
	for node in pistol.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var to_root := inverse * instance.global_transform
		for vertex in instance.mesh.get_faces():
			var at := to_root * vertex
			triangles.append([at.x, at.y, at.z])
	var sockets := {}
	for node in pistol.find_children("*", "Node3D", true, false):
		if not node is MeshInstance3D:
			sockets[node.name] = _xf(inverse * (node as Node3D).global_transform)
	return {"triangles": triangles, "sockets": sockets, "seat": _xf(pistol.transform)}


# A transform as twelve numbers: the basis' columns x, y, z, then the origin.
func _xf(xf: Transform3D) -> Array:
	var b := xf.basis
	var o := xf.origin
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, o.x, o.y, o.z]

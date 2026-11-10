# The assault rifle's files carry what the weapon code and the hold read from them: the hand
# sockets, the muzzle at the barrel's end pointing out of it, the magazine and bolt as their own
# nodes, one palette material, the triangle budgets, and a far level with every node at the near
# level's place (built by `assets/weapons/rifle/build_rifle.py`).
extends GdUnitTestSuite

const NEAR := "res://assets/weapons/rifle/rifle.glb"
const FAR := "res://assets/weapons/rifle/rifle_far.glb"
const SOCKETS: Array[StringName] = [&"Muzzle", &"Eject", &"Grip", &"Trigger", &"Support", &"Butt"]
const PARTS: Array[StringName] = [&"Magazine", &"Bolt"]
## Kit docs/tools/blender/optimisation.md#budgets: a held or world weapon, near and far.
const NEAR_BUDGET := 1500
const FAR_BUDGET := 500


func _load(path: String) -> Node3D:
	var scene: PackedScene = load(path)
	assert_object(scene).is_not_null()
	var root: Node3D = auto_free(scene.instantiate())
	return root


func _node(root: Node3D, node_name: StringName) -> Node3D:
	return root.find_child(String(node_name), true, false) as Node3D


# The transform of `node` in the space of the scene's root.
func _in_root(root: Node3D, node: Node3D) -> Transform3D:
	var xf := node.transform
	var parent := node.get_parent() as Node3D
	while parent != null and parent != root:
		xf = parent.transform * xf
		parent = parent.get_parent() as Node3D
	return xf


func _meshes(root: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		out.append(node as MeshInstance3D)
	return out


func _triangles(root: Node3D) -> int:
	var count := 0
	for mesh_instance in _meshes(root):
		var mesh := mesh_instance.mesh
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			count += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return count


func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh_instance in _meshes(root):
		var part := _in_root(root, mesh_instance) * mesh_instance.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


func test_every_socket_and_moving_part_is_in_both_levels() -> void:
	for path in [NEAR, FAR]:
		var root := _load(path)
		for socket in SOCKETS:
			(
				assert_object(_node(root, socket))
				. override_failure_message("%s has no %s" % [path, socket])
				. is_not_null()
			)
		for part in PARTS:
			var node := _node(root, part)
			(
				assert_object(node as MeshInstance3D)
				. override_failure_message("%s: %s is not a mesh of its own" % [path, part])
				. is_not_null()
			)


func test_the_triangle_counts_are_within_the_budgets() -> void:
	assert_int(_triangles(_load(NEAR))).is_between(1, NEAR_BUDGET)
	assert_int(_triangles(_load(FAR))).is_between(1, FAR_BUDGET)


func test_every_surface_uses_the_one_palette_material() -> void:
	for path in [NEAR, FAR]:
		var names := {}
		for mesh_instance in _meshes(_load(path)):
			for surface in mesh_instance.mesh.get_surface_count():
				names[mesh_instance.mesh.surface_get_material(surface).resource_name] = true
		(
			assert_array(names.keys())
			. override_failure_message("%s: %s" % [path, names.keys()])
			. contains_exactly([&"Weapons"])
		)


func test_the_muzzle_is_at_the_barrels_end_and_points_out_of_it() -> void:
	for path in [NEAR, FAR]:
		var root := _load(path)
		var muzzle := _in_root(root, _node(root, &"Muzzle"))
		var front := _bounds(root).position.x
		(
			assert_float(absf(muzzle.origin.x - front))
			. override_failure_message(
				"%s: muzzle %.4f from the front face" % [path, muzzle.origin.x - front]
			)
			. is_less(0.01)
		)
		assert_float((-muzzle.basis.z).normalized().dot(Vector3.LEFT)).is_greater(0.999)


func test_the_hands_and_the_butt_are_where_a_two_handed_hold_needs_them() -> void:
	var root := _load(NEAR)
	var grip := _in_root(root, _node(root, &"Grip"))
	var support := _in_root(root, _node(root, &"Support")).origin
	var butt := _in_root(root, _node(root, &"Butt")).origin
	var box := _bounds(root)
	assert_vector(grip.origin).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)
	# The grip's +Y runs up the handle (raked back 16 degrees), its -Z along the barrel (the fingers).
	assert_float(grip.basis.y.normalized().dot(Vector3.UP)).is_greater(0.9)
	assert_float((-grip.basis.z).normalized().dot(Vector3.LEFT)).is_greater(0.95)
	# The left hand holds the fore-end 0.2 to 0.4 m ahead of the grip, above it and under the bore.
	assert_float(-support.x).is_between(0.2, 0.4)
	assert_float(support.y).is_between(0.05, _in_root(root, _node(root, &"Muzzle")).origin.y)
	assert_float(absf(butt.x - box.end.x)).is_less(0.01)


func test_the_far_level_keeps_every_node_at_the_near_levels_place() -> void:
	var near := _load(NEAR)
	var far := _load(FAR)
	for node_name in SOCKETS + PARTS:
		var a := _in_root(near, _node(near, node_name))
		var b := _in_root(far, _node(far, node_name))
		(
			assert_vector(b.origin)
			. override_failure_message("%s moved in the far level" % node_name)
			. is_equal_approx(a.origin, Vector3.ONE * 0.001)
		)
		assert_bool(b.basis.is_equal_approx(a.basis)).is_true()

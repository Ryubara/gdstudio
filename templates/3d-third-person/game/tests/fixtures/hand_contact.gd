class_name HandContact
extends RefCounted
## Measures how the mannequin's hands meet the weapon they hold (kit #1001): for each part of a
## hand (every finger's three bones, the thumb's three and the palm), the signed distance in
## metres from its skin to the weapon's surface, negative where the skin is inside the weapon.
## The skin is the skinned mesh as drawn, worked out on the CPU from the bone poses that
## `snapshot()` copies; the weapon is its triangles, split into the closed pieces it is built from
## (a kitbashed gun is many overlapping closed parts, so inside means inside any piece). A hand
## that lies over the other one (the support hand of a two-handed grip) is measured against the
## other hand's skin too, which is closed pieces as well (a capsule a finger bone, a ball a joint):
## inside a piece is an odd number of crossings along most of three rays, never the side of the
## nearest face, which reads a thumb lying beside the other thumb as 5 mm inside it. A piece that
## is open where the hand's skin ends (the palm at the wrist) is closed there first, each ring of
## open edges joined to its middle: the forearm goes on at the wrist, so what lies in the opening
## is in the arm, and left open two of the three rays can leave through it (kit #1084: a thumb
## 2 mm off the other wrist read 19 mm inside the palm once the aim turned the hands up).
##
## Call `snapshot()` inside the skeleton's `skeleton_updated` signal: only there does
## `get_bone_global_pose()` hold what the modifiers (the finger pose, the arm's IK) made of the
## clip's pose. Ported from Deadnight's `HandContact` (Deadnight #460) to the universal rig.

## A finger's bones from the knuckle out, and the thumb's; `%s` is the side, `r` or `l`.
const PARTS: Dictionary[String, String] = {
	"index_base": "index_01_%s",
	"index_mid": "index_02_%s",
	"index_tip": "index_03_%s",
	"middle_base": "middle_01_%s",
	"middle_mid": "middle_02_%s",
	"middle_tip": "middle_03_%s",
	"ring_base": "ring_01_%s",
	"ring_mid": "ring_02_%s",
	"ring_tip": "ring_03_%s",
	"pinky_base": "pinky_01_%s",
	"pinky_mid": "pinky_02_%s",
	"pinky_tip": "pinky_03_%s",
	"thumb_base": "thumb_01_%s",
	"thumb_mid": "thumb_02_%s",
	"thumb_tip": "thumb_03_%s",
	"palm": "hand_%s",
}
## The deepest any part may go into the weapon (or the other hand), in metres.
const MAX_DEPTH := 0.002
## The farthest a part that holds the weapon may be off it, in metres.
const MAX_FLOAT := 0.005
## A vertex counts for a part when its main bone carries at least this share of its weight.
const MIN_WEIGHT := 0.5
## A part farther than this from every surface reads this, in metres.
const MARGIN := 0.03
const _CELL := 0.01
const _SKIN_DEPTH := 0.02

var _skeleton: Skeleton3D
var _surfaces: Array[Dictionary] = []
var _parts := {"r": {}, "l": {}}
var _hand_triangles := {"r": PackedInt32Array(), "l": PackedInt32Array()}
var _hand_pieces := {}
var _hand_rings := {}
var _poses: Array[Transform3D] = []
var _weapon: Node3D
var _to_weapon := Transform3D.IDENTITY
var _gun := TriangleField.new()
var _gun_pieces: Array[PackedInt32Array] = []
var _gun_piece_of := PackedInt32Array()
var _columns := {}


## A set of triangles in a hash grid, for the nearest one to a point.
class TriangleField:
	var points := PackedVector3Array()
	var cells := {}
	var _stamp := PackedInt32Array()
	var _query := 0

	func add(a: Vector3, b: Vector3, c: Vector3) -> void:
		var triangle := points.size() / 3
		points.append_array([a, b, c])
		_stamp.append(0)
		var low := Vector3i((a.min(b).min(c) / _CELL).floor())
		var high := Vector3i((a.max(b).max(c) / _CELL).floor())
		for x in range(low.x, high.x + 1):
			for y in range(low.y, high.y + 1):
				for z in range(low.z, high.z + 1):
					var key := Vector3i(x, y, z)
					if not cells.has(key):
						cells[key] = []
					(cells[key] as Array).append(triangle)

	## The nearest triangle to `at` within `MARGIN`: [distance, closest point, triangle], or
	## [MARGIN, at, -1] when none is that near.
	func nearest(at: Vector3) -> Array:
		_query += 1
		var best := MARGIN
		var best_point := at
		var best_triangle := -1
		var home := Vector3i((at / _CELL).floor())
		var reach := ceili(MARGIN / _CELL)
		for ring in range(0, reach + 1):
			if best <= (ring - 1) * _CELL:
				break
			for x in range(-ring, ring + 1):
				for y in range(-ring, ring + 1):
					var edge := absi(x) == ring or absi(y) == ring
					for z in range(-ring, ring + 1) if edge else [-ring, ring]:
						var list: Variant = cells.get(home + Vector3i(x, y, z))
						if list == null:
							continue
						for triangle: int in list as Array:
							if _stamp[triangle] == _query:
								continue
							_stamp[triangle] = _query
							var closest := HandContact.closest_on_triangle(
								at,
								points[triangle * 3],
								points[triangle * 3 + 1],
								points[triangle * 3 + 2]
							)
							var distance := at.distance_to(closest)
							if distance < best:
								best = distance
								best_point = closest
								best_triangle = triangle
		return [best, best_point, best_triangle]


## One hand's skin as posed: its triangles, and the closed pieces they make with their bounds.
class HandSkin:
	var field := TriangleField.new()
	var pieces: Array[PackedInt32Array] = []
	var bounds: Array[AABB] = []


func _init(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	for instance in CharacterBodies.near_meshes(skeleton):
		if instance.skin == null or instance.mesh == null:
			continue
		for surface in instance.mesh.get_surface_count():
			_add_surface(instance, surface)
	snapshot()


## Copies the skeleton's pose to measure; call it in `skeleton_updated`. The weapon's place is
## read when a hand is measured (a `BoneAttachment3D` moves in the same signal, maybe later).
func snapshot() -> void:
	_poses.clear()
	for bone in _skeleton.get_bone_count():
		_poses.append(_skeleton.get_bone_global_pose(bone))


## Sets the weapon measured against: every mesh under it, in its own space.
func set_weapon(weapon: Node3D) -> void:
	_weapon = weapon
	_gun = TriangleField.new()
	_gun_pieces.clear()
	_gun_piece_of = PackedInt32Array()
	_columns.clear()
	if weapon == null:
		return
	var inverse := weapon.global_transform.affine_inverse()
	for node in weapon.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null or not instance.is_visible_in_tree():
			continue
		var to_weapon := inverse * instance.global_transform
		for surface in instance.mesh.get_surface_count():
			_add_weapon_surface(instance.mesh.surface_get_arrays(surface), to_weapon)


## The signed distance from each part of the hand of `side` (`r` or `l`) to the weapon, and with
## `over_other_hand` to the other hand's skin too: {part: {"distance": the smaller of the two,
## "gun": float, "hand": float, "point": the part's skin point nearest a surface, in the
## skeleton's space}}.
func measure(side: String, over_other_hand := false) -> Dictionary:
	var found := {}
	_to_weapon = _weapon.global_transform.affine_inverse() * _skeleton.global_transform
	var other: HandSkin = null
	if over_other_hand:
		other = _hand_field("l" if side == "r" else "r")
	var cache := {}
	for part: String in _parts[side]:
		var list: Array = _parts[side][part]
		var entry := {"distance": INF, "gun": INF, "hand": INF, "point": Vector3.ZERO}
		for index in list.size() / 2:
			var at := _skinned(list[index * 2], list[index * 2 + 1], cache)
			var to_gun := _gun_distance(_to_weapon * at)
			var to_hand := _skin_distance(other, at) if other != null else INF
			entry.gun = minf(entry.gun, to_gun)
			entry.hand = minf(entry.hand, to_hand)
			if minf(to_gun, to_hand) < entry.distance:
				entry.distance = minf(to_gun, to_hand)
				entry.point = at
		found[part] = entry
	return found


## A bone's pose in the skeleton's space, as `snapshot()` copied it.
func bone_pose(bone_name: StringName) -> Transform3D:
	return _poses[_skeleton.find_bone(bone_name)]


## The least distance from the skin of one part of a hand to a point of the world, in metres.
func part_distance_to(side: String, part: String, point: Vector3) -> float:
	var at := _skeleton.global_transform.affine_inverse() * point
	var list: Array = _parts[side][part]
	var cache := {}
	var least := INF
	for index in list.size() / 2:
		least = minf(least, at.distance_to(_skinned(list[index * 2], list[index * 2 + 1], cache)))
	return least


## What is wrong with one hand's `parts` (from `measure`): a part more than `MAX_DEPTH` into a
## surface, or one of `contacts` more than `MAX_FLOAT` off every surface. One sentence each,
## starting with `tag`; empty when the hand holds.
static func failures(tag: String, parts: Dictionary, contacts: Array) -> Array[String]:
	var fails: Array[String] = []
	for part: String in parts:
		var distance: float = parts[part].distance
		if distance < -MAX_DEPTH:
			fails.append("%s %s %.1f mm inside" % [tag, part, -distance * 1000.0])
		elif part in contacts and distance > MAX_FLOAT:
			fails.append("%s %s %.1f mm off" % [tag, part, distance * 1000.0])
	return fails


## The deepest and the farthest of `parts`, in millimetres: "in 1.2 (ring_tip) off 3.4 (thumb_tip)"
## over `contacts`.
static func summary(parts: Dictionary, contacts: Array) -> String:
	var deepest := 0.0
	var deepest_part := "-"
	var farthest := -INF
	var farthest_part := "-"
	for part: String in parts:
		var distance: float = parts[part].distance
		if -distance > deepest:
			deepest = -distance
			deepest_part = part
		if part in contacts and distance > farthest:
			farthest = distance
			farthest_part = part
	return (
		"in %.1f (%s) off %.1f (%s)"
		% [deepest * 1000.0, deepest_part, farthest * 1000.0, farthest_part]
	)


## Both hands' skin as posed and the weapon, in the skeleton's space, as an OBJ file (objects
## `hand_r`, `hand_l` and `weapon`), for a close look in Blender.
func dump_obj(path: String) -> void:
	var lines := PackedStringArray()
	var cache := {}
	var count := 0
	for side: String in ["r", "l"]:
		lines.append("o hand_%s" % side)
		var list: PackedInt32Array = _hand_triangles[side]
		for index in list.size() / 2:
			var at := _skinned(list[index * 2], list[index * 2 + 1], cache)
			lines.append("v %f %f %f" % [at.x, at.y, at.z])
		for triangle in list.size() / 6:
			var first := count + triangle * 3
			lines.append("f %d %d %d" % [first + 1, first + 2, first + 3])
		count += list.size() / 2
	lines.append("o weapon")
	var back := _skeleton.global_transform.affine_inverse() * _weapon.global_transform
	for point in _gun.points:
		var at := back * point
		lines.append("v %f %f %f" % [at.x, at.y, at.z])
	for triangle in _gun.points.size() / 3:
		var first := count + triangle * 3
		lines.append("f %d %d %d" % [first + 1, first + 2, first + 3])
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")


## The closest point to `p` on the triangle `a b c` (Ericson, Real-Time Collision Detection 5.1.5).
static func closest_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denominator := 1.0 / (va + vb + vc)
	return a + ab * (vb * denominator) + ac * (vc * denominator)


func _add_surface(instance: MeshInstance3D, surface: int) -> void:
	var arrays := instance.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if bones.is_empty() or vertices.is_empty():
		return
	var per := bones.size() / vertices.size()
	var skin := instance.skin
	var bind_bones := PackedInt32Array()
	var bind_poses: Array[Transform3D] = []
	for bind in skin.get_bind_count():
		var bone := _skeleton.find_bone(skin.get_bind_name(bind))
		bind_bones.append(bone if bone >= 0 else skin.get_bind_bone(bind))
		bind_poses.append(skin.get_bind_pose(bind))
	var owners := _owners()
	var main := PackedInt32Array()
	var share := PackedFloat32Array()
	for vertex in vertices.size():
		var best := -1
		var best_weight := 0.0
		for slot in per:
			var weight := weights[vertex * per + slot]
			if weight <= 0.0:
				continue
			var owner := owners[bind_bones[bones[vertex * per + slot]]]
			# The weights of the other slots with the same owner (a fingertip's bone and its leaf).
			for other in slot:
				if owners[bind_bones[bones[vertex * per + other]]] == owner:
					weight += weights[vertex * per + other]
			if weight > best_weight:
				best_weight = weight
				best = owner
		main.append(best)
		share.append(best_weight)
	var index := _surfaces.size()
	var entry := {
		"vertices": vertices,
		"bones": bones,
		"weights": weights,
		"per": per,
		"bind_bones": bind_bones,
		"bind_poses": bind_poses,
	}
	_surfaces.append(entry)
	for side: String in ["r", "l"]:
		_collect_side(side, index, main, share, indices)


# The bone each bone's skin counts for: itself, or for a bone with no children that hangs under
# a part's bone (the leaf at a fingertip, which one mannequin's skin is weighted to) that bone.
func _owners() -> PackedInt32Array:
	var part_bones := {}
	for side: String in ["r", "l"]:
		for part: String in PARTS:
			part_bones[_skeleton.find_bone(PARTS[part] % side)] = true
	var owners := PackedInt32Array()
	for bone in _skeleton.get_bone_count():
		var parent := _skeleton.get_bone_parent(bone)
		var leaf := _skeleton.get_bone_children(bone).is_empty() and not part_bones.has(bone)
		owners.append(parent if leaf and part_bones.has(parent) else bone)
	return owners


func _collect_side(
	side: String,
	surface: int,
	main: PackedInt32Array,
	share: PackedFloat32Array,
	indices: PackedInt32Array
) -> void:
	var vertices: PackedVector3Array = _surfaces[surface].vertices
	var by_bone := {}
	for part: String in PARTS:
		by_bone[_skeleton.find_bone(PARTS[part] % side)] = part
	var seen := {}
	for vertex in vertices.size():
		if share[vertex] < MIN_WEIGHT or not by_bone.has(main[vertex]):
			continue
		# glTF splits a vertex at every seam; one copy is enough to measure.
		var key := Vector3i((vertices[vertex] * 1e5).round())
		if seen.has(key):
			continue
		seen[key] = true
		var part: String = by_bone[main[vertex]]
		if not _parts[side].has(part):
			_parts[side][part] = []
		(_parts[side][part] as Array).append_array([surface, vertex])
	var list: PackedInt32Array = _hand_triangles[side]
	for triangle in indices.size() / 3:
		var whole := true
		for corner in 3:
			whole = whole and by_bone.has(main[indices[triangle * 3 + corner]])
		if whole:
			for corner in 3:
				list.append_array([surface, indices[triangle * 3 + corner]])
	_hand_triangles[side] = list


func _skinned(surface: int, vertex: int, cache: Dictionary) -> Vector3:
	var key := Vector2i(surface, vertex)
	if cache.has(key):
		return cache[key]
	var entry: Dictionary = _surfaces[surface]
	var per: int = entry.per
	var bones: PackedInt32Array = entry.bones
	var weights: PackedFloat32Array = entry.weights
	var bind_bones: PackedInt32Array = entry.bind_bones
	var bind_poses: Array[Transform3D] = entry.bind_poses
	var rest: Vector3 = (entry.vertices as PackedVector3Array)[vertex]
	var sum := Vector3.ZERO
	for slot in per:
		var weight := weights[vertex * per + slot]
		if weight <= 0.0:
			continue
		var bind := bones[vertex * per + slot]
		sum += weight * (_poses[bind_bones[bind]] * bind_poses[bind] * rest)
	cache[key] = sum
	return sum


# The skin of one hand as posed, in the skeleton's space, in its closed pieces.
func _hand_field(side: String) -> HandSkin:
	var skin := HandSkin.new()
	var cache := {}
	var list: PackedInt32Array = _hand_triangles[side]
	var piece_of := _pieces_of(side)
	for triangle in list.size() / 6:
		var first := triangle * 6
		var corners: Array[Vector3] = [
			_skinned(list[first], list[first + 1], cache),
			_skinned(list[first + 2], list[first + 3], cache),
			_skinned(list[first + 4], list[first + 5], cache),
		]
		skin.field.add(corners[0], corners[1], corners[2])
		var piece := piece_of[triangle]
		while skin.pieces.size() <= piece:
			skin.pieces.append(PackedInt32Array())
			skin.bounds.append(AABB(corners[0], Vector3.ZERO))
		skin.pieces[piece].append(triangle)
		for corner in corners:
			skin.bounds[piece] = skin.bounds[piece].expand(corner)
	# Each open ring closed with a fan to its middle, as part of its piece.
	for ring: Array in _hand_rings[side]:
		var rim := PackedVector3Array()
		var middle := Vector3.ZERO
		for entry: int in ring[1]:
			var at := _skinned(list[entry * 2], list[entry * 2 + 1], cache)
			rim.append(at)
			middle += at
		middle /= rim.size()
		for edge in rim.size() / 2:
			skin.pieces[ring[0]].append(skin.field.points.size() / 3)
			skin.field.add(rim[edge * 2], rim[edge * 2 + 1], middle)
	return skin


# The piece of each triangle of a hand: triangles that share a vertex (welded by its place in the
# bind pose, since glTF splits a vertex at every seam) are one piece. Worked out once a side.
func _pieces_of(side: String) -> PackedInt32Array:
	if _hand_pieces.has(side):
		return _hand_pieces[side]
	var list: PackedInt32Array = _hand_triangles[side]
	var welded := {}
	var ids := PackedInt32Array()
	for index in list.size() / 2:
		var vertices: PackedVector3Array = _surfaces[list[index * 2]].vertices
		var key := Vector3i((vertices[list[index * 2 + 1]] * 1e5).round())
		if not welded.has(key):
			welded[key] = welded.size()
		ids.append(welded[key])
	var parent := PackedInt32Array(range(welded.size()))
	for triangle in ids.size() / 3:
		var a := _find(parent, ids[triangle * 3])
		for corner in [1, 2]:
			var b := _find(parent, ids[triangle * 3 + corner])
			if a != b:
				parent[b] = a
	var numbers := {}
	var piece_of := PackedInt32Array()
	for triangle in ids.size() / 3:
		var root := _find(parent, ids[triangle * 3])
		if not numbers.has(root):
			numbers[root] = numbers.size()
		piece_of.append(numbers[root])
	_hand_pieces[side] = piece_of
	_hand_rings[side] = _open_rings(ids, piece_of)
	return piece_of


# The rings of edges that only one triangle has, where a piece is open: [piece, the corners of its
# edges as indices into the hand's list of vertices, two an edge] each. `ids` is the welded vertex
# of every corner, `piece_of` the piece of every triangle.
static func _open_rings(ids: PackedInt32Array, piece_of: PackedInt32Array) -> Array:
	var users := {}
	var welded := 0
	for triangle in ids.size() / 3:
		for corner in 3:
			var first := triangle * 3 + corner
			var second := triangle * 3 + (corner + 1) % 3
			welded = maxi(welded, ids[first] + 1)
			var key := Vector2i(mini(ids[first], ids[second]), maxi(ids[first], ids[second]))
			users[key] = Vector2i(-1, -1) if users.has(key) else Vector2i(first, second)
	var parent := PackedInt32Array(range(welded))
	var lone: Array[Vector2i] = []
	for key: Vector2i in users:
		var edge: Vector2i = users[key]
		if edge.x < 0:
			continue
		lone.append(edge)
		var a := _find(parent, key.x)
		var b := _find(parent, key.y)
		if a != b:
			parent[b] = a
	var rings := {}
	for edge in lone:
		var root := _find(parent, ids[edge.x])
		if not rings.has(root):
			rings[root] = [piece_of[edge.x / 3], []]
		(rings[root][1] as Array).append_array([edge.x, edge.y])
	return rings.values()


# The signed distance to a skin: negative inside one of its pieces, by how far it is to that
# piece's surface. Nothing is deeper in a hand than `_SKIN_DEPTH`. Three rays vote on each piece,
# so that one ray along an edge or through a gap in a ring's fan decides nothing.
func _skin_distance(skin: HandSkin, at: Vector3) -> float:
	var hit := skin.field.nearest(at)
	if hit[2] < 0:
		return MARGIN
	var distance: float = hit[0]
	if distance >= _SKIN_DEPTH:
		return distance
	var depth := 0.0
	for piece in skin.pieces.size():
		if not skin.bounds[piece].has_point(at):
			continue
		var votes := 0
		for axis in 3:
			votes += _crossings(skin.field.points, skin.pieces[piece], at, axis) % 2
		if votes < 2:
			continue
		var to_surface := INF
		for triangle in skin.pieces[piece]:
			var closest := closest_on_triangle(
				at,
				skin.field.points[triangle * 3],
				skin.field.points[triangle * 3 + 1],
				skin.field.points[triangle * 3 + 2]
			)
			to_surface = minf(to_surface, at.distance_to(closest))
		depth = maxf(depth, to_surface)
	return -depth if depth > 0.0 else distance


func _add_weapon_surface(arrays: Array, to_weapon: Transform3D) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		indices = PackedInt32Array(range(vertices.size()))
	# Weld split vertices by place, then join triangles that share one into closed pieces.
	var welded := {}
	var ids := PackedInt32Array()
	for vertex in vertices.size():
		var key := Vector3i(((to_weapon * vertices[vertex]) * 1e5).round())
		if not welded.has(key):
			welded[key] = welded.size()
		ids.append(welded[key])
	var parent := PackedInt32Array(range(welded.size()))
	for triangle in indices.size() / 3:
		var a := _find(parent, ids[indices[triangle * 3]])
		for corner in [1, 2]:
			var b := _find(parent, ids[indices[triangle * 3 + corner]])
			if a != b:
				parent[b] = a
	var piece_of := {}
	for triangle in indices.size() / 3:
		var root := _find(parent, ids[indices[triangle * 3]])
		if not piece_of.has(root):
			piece_of[root] = _gun_pieces.size()
			_gun_pieces.append(PackedInt32Array())
		var piece: int = piece_of[root]
		var corners: Array[Vector3] = []
		for corner in 3:
			corners.append(to_weapon * vertices[indices[triangle * 3 + corner]])
		var id := _gun.points.size() / 3
		_gun.add(corners[0], corners[1], corners[2])
		_gun_piece_of.append(piece)
		_gun_pieces[piece].append(id)
		_add_to_columns(id, piece, corners)


# A triangle joins every column (a cell of the weapon's XY plane) its bounds touch, per piece, for
# the inside test's ray along Z.
func _add_to_columns(id: int, piece: int, corners: Array[Vector3]) -> void:
	var low := corners[0].min(corners[1]).min(corners[2]) / _CELL
	var high := corners[0].max(corners[1]).max(corners[2]) / _CELL
	for x in range(floori(low.x), floori(high.x) + 1):
		for y in range(floori(low.y), floori(high.y) + 1):
			var key := Vector3i(x, y, piece)
			if not _columns.has(key):
				_columns[key] = []
			(_columns[key] as Array).append(id)


static func _find(parent: PackedInt32Array, index: int) -> int:
	while parent[index] != index:
		parent[index] = parent[parent[index]]
		index = parent[index]
	return index


# The signed distance from `at` (in the weapon's space) to the weapon: negative inside a piece, by
# how far it is to that piece's surface.
func _gun_distance(at: Vector3) -> float:
	var hit := _gun.nearest(at)
	var depth := 0.0
	var column := Vector2i(floori(at.x / _CELL), floori(at.y / _CELL))
	for piece in _gun_pieces.size():
		var list: Variant = _columns.get(Vector3i(column.x, column.y, piece))
		if list == null or not _inside(at, list as Array):
			continue
		var to_surface := INF
		for triangle in _gun_pieces[piece]:
			var closest := closest_on_triangle(
				at,
				_gun.points[triangle * 3],
				_gun.points[triangle * 3 + 1],
				_gun.points[triangle * 3 + 2]
			)
			to_surface = minf(to_surface, at.distance_to(closest))
		depth = maxf(depth, to_surface)
	return -depth if depth > 0.0 else (hit[0] as float)


# Whether `at` is inside the closed piece whose triangles over this column are `list`: an odd
# number of crossings along +Z.
func _inside(at: Vector3, list: Array) -> bool:
	return _crossings(_gun.points, list, at, Vector3.AXIS_Z) % 2 == 1


# How many of the triangles `list` (indices into `points`, three corners each) a ray from `at`
# along the positive `axis` crosses.
static func _crossings(points: PackedVector3Array, list: Variant, at: Vector3, axis: int) -> int:
	var i := (axis + 1) % 3
	var j := (axis + 2) % 3
	var crossings := 0
	for triangle: int in list:
		var a := points[triangle * 3]
		var b := points[triangle * 3 + 1]
		var c := points[triangle * 3 + 2]
		var area := (b[i] - a[i]) * (c[j] - a[j]) - (c[i] - a[i]) * (b[j] - a[j])
		if absf(area) < 1e-12:
			continue
		var u := ((at[i] - a[i]) * (c[j] - a[j]) - (c[i] - a[i]) * (at[j] - a[j])) / area
		var v := ((b[i] - a[i]) * (at[j] - a[j]) - (at[i] - a[i]) * (b[j] - a[j])) / area
		if u < 0.0 or v < 0.0 or u + v > 1.0:
			continue
		if a[axis] + u * (b[axis] - a[axis]) + v * (c[axis] - a[axis]) > at[axis]:
			crossings += 1
	return crossings

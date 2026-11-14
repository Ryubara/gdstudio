# The butt's push along a way (`TorsoSkin._push_along()`, kit #1346) finds the push every point
# of the torso's skin allows (kit #1433): on both bodies, in the low ready and through the whole
# pitch range standing, crouched and walking, and with the gun moved deeper into the chest and
# out of it (so a push far from the last one is looked for again over the whole reach), it is
# the push of a plain pass over every point with no box met first, as `main` worked it out
# before the push only went through the points the stock passes over. The push along the barrel
# (`TorsoSkin.push()` with no way) is a plain pass's too, and a skin that takes the spine's poses
# from the stance (`TorsoSkin.use_spine()`, kit #1347) finds the push of one that works them out.
extends GdUnitTestSuite

const MODELS: Array[String] = ["female", "male"]
## The clips the hold is posed in, at a time each.
const CLIPS: Dictionary[StringName, float] = {
	CharacterClips.IDLE: 0.0,
	CharacterClips.CROUCH_IDLE: 0.0,
	CharacterClips.WALK: 0.3,
}
## The game's pitch range and the step through it, in degrees.
const PITCH_RANGE := 45.0
const PITCH_STEP := 15.0
## Where the gun is moved from the hold's pocket, in the gun's space, one after another: deeper
## in the chest needs a push well past the last one (the whole reach is gone through again).
const MOVES: Array[Vector3] = [
	Vector3.ZERO,
	Vector3(0.0, 0.0, -0.06),
	Vector3(0.0, 0.0, 0.03),
	Vector3(0.0, 0.02, -0.03),
	Vector3(0.0, -0.02, -0.08),
	Vector3(0.015, 0.0, 0.0),
]
## How far the push may be from the plain pass's, in metres (the same points, the products in
## another order in single precision).
const SAME := 1e-5
## The least share of a move along the barrel (`TorsoSkin._LEAST_ALONG`).
const LEAST_ALONG := 0.1
## The most the push looks along its way, in metres (`TorsoSkin._PUSH_MOST`).
const PUSH_MOST := 0.25

var _holder: Node3D


func before_test() -> void:
	_holder = auto_free(Node3D.new())
	add_child(_holder)


func test_the_push_along_a_way_is_the_push_of_every_point() -> void:
	var along := 0
	for model in MODELS:
		var stage := RifleStage.make_rifle(_holder, model)
		var held := stage.hold as TwoHandHold
		var skin := TorsoSkin.new()
		skin.measure(
			stage.skeleton,
			stage.skeleton.find_bone(held.chest_bone),
			held.torso_bones,
			held.skin_spacing
		)
		for clip_name in CLIPS:
			var poses: Array[Vector2] = [Vector2(0.0, 0.0)]
			var pitch := -PITCH_RANGE
			while pitch <= PITCH_RANGE:
				poses.append(Vector2(1.0, pitch))
				pitch += PITCH_STEP
			for pose in poses:
				stage.pose_rifle(clip_name, CLIPS[clip_name], pose.x, pose.y)
				await stage.settle()
				var pivot := held.get_node(^"Pivot") as Node3D
				var turn := pivot.transform.basis
				var way := _way(turn, held.push_level)
				var pocket := pivot.transform.origin - way * held.butt_push()
				var to_here := (
					held.global_transform.affine_inverse() * stage.skeleton.global_transform
				)
				for move in MOVES:
					var gun := Transform3D(turn, pocket + turn * move)
					var local := turn.inverse() * way
					if absf(local.y) <= 1e-4:
						continue
					along += 1
					var found := skin.push(
						stage.skeleton,
						gun,
						to_here,
						held.butt_pad,
						held.butt_depth,
						held.butt_margin,
						way
					)
					var plain := _plain_push(skin, stage.skeleton, gun, to_here, held, local)
					# Past the most the push looks (`TorsoSkin._PUSH_MOST`) `main` stopped too.
					if plain >= PUSH_MOST:
						continue
					var tag := (
						"%s %s aim %.0f pitch %.0f moved %s"
						% [model, clip_name, pose.x, pose.y, move]
					)
					(
						assert_float(absf(found - plain))
						. override_failure_message(
							(
								"%s: the push is %.4f mm, every point's %.4f mm"
								% [tag, found * 1e3, plain * 1e3]
							)
						)
						. is_less_equal(SAME)
					)
		stage.free()
	# The low ready and every pitch down take the way along (the level way, kit #1346).
	assert_int(along).is_greater(40)


func test_the_push_along_the_barrel_and_from_the_stance_s_spine_is_every_point_s() -> void:
	var checked := 0
	for model in MODELS:
		var stage := RifleStage.make_rifle(_holder, model)
		var held := stage.hold as TwoHandHold
		var chest := stage.skeleton.find_bone(held.chest_bone)
		var skin := TorsoSkin.new()
		skin.measure(stage.skeleton, chest, held.torso_bones, held.skin_spacing)
		# The same skin with the spine's poses handed over as the stance hands them.
		var shared := TorsoSkin.new()
		shared.measure(stage.skeleton, chest, held.torso_bones, held.skin_spacing)
		var spine := PackedInt32Array()
		for bone_name in held.spine_bones:
			spine.append(stage.skeleton.find_bone(bone_name))
		var spine_poses: Array[Transform3D] = []
		spine_poses.resize(spine.size())
		var from := HoldBones.new()
		from.read(stage.skeleton)
		from.top = spine[-1]
		shared.use_spine(from, spine, spine_poses)
		for clip_name in CLIPS:
			for pose in [Vector2(0.0, 0.0), Vector2(1.0, -PITCH_RANGE), Vector2(1.0, PITCH_RANGE)]:
				stage.pose_rifle(clip_name, CLIPS[clip_name], pose.x, pose.y)
				await stage.settle()
				for index in spine.size():
					spine_poses[index] = from.global_pose(stage.skeleton, spine[index])
				var pivot := held.get_node(^"Pivot") as Node3D
				var turn := pivot.transform.basis
				var level := _way(turn, held.push_level)
				var pocket := pivot.transform.origin - level * held.butt_push()
				var to_here := (
					held.global_transform.affine_inverse() * stage.skeleton.global_transform
				)
				for move in MOVES:
					var gun := Transform3D(turn, pocket + turn * move)
					var tag := (
						"%s %s aim %.0f pitch %.0f moved %s"
						% [model, clip_name, pose.x, pose.y, move]
					)
					var found := skin.push(
						stage.skeleton,
						gun,
						to_here,
						held.butt_pad,
						held.butt_depth,
						held.butt_margin
					)
					var plain := _plain_barrel_push(skin, stage.skeleton, gun, to_here, held)
					(
						assert_float(absf(found - plain))
						. override_failure_message(
							(
								"%s: the push along the barrel is %.4f mm, every point's %.4f mm"
								% [tag, found * 1e3, plain * 1e3]
							)
						)
						. is_less_equal(SAME)
					)
					for way in [Vector3.ZERO, level]:
						var alone := skin.push(
							stage.skeleton,
							gun,
							to_here,
							held.butt_pad,
							held.butt_depth,
							held.butt_margin,
							way
						)
						var given := shared.push(
							stage.skeleton,
							gun,
							to_here,
							held.butt_pad,
							held.butt_depth,
							held.butt_margin,
							way
						)
						checked += 1
						(
							assert_float(absf(given - alone))
							. override_failure_message(
								(
									"%s way %s: with the stance's spine %.4f mm, without %.4f mm"
									% [tag, way, given * 1e3, alone * 1e3]
								)
							)
							. is_less_equal(SAME)
						)
		stage.free()
	assert_int(checked).is_greater(100)


# `TwoHandHold._push_way()`: the barrel, its fall taken out by `push_level` while it points down.
func _way(turn: Basis, push_level: float) -> Vector3:
	var barrel := turn.z.normalized()
	var level := Vector3(barrel.x, 0.0, barrel.z)
	if push_level <= 0.0 or barrel.y >= 0.0 or level.length_squared() < 1e-6:
		return barrel
	return barrel.slerp(level.normalized(), push_level)


# The push along the way `local` (in the gun's space) as `main` worked it out, over every point
# of the skin with no box met first, each bone's pose from every local pose up to the root.
func _plain_push(
	skin: TorsoSkin,
	skeleton: Skeleton3D,
	gun: Transform3D,
	to_here: Transform3D,
	held: TwoHandHold,
	local: Vector3
) -> float:
	var move := Vector2(local.y, maxf(local.z, LEAST_ALONG)).normalized()
	var to_gun := gun.affine_inverse() * to_here
	var wide := held.butt_pad.x * 0.5 + held.butt_margin
	var high := held.butt_pad.y * 0.5 + held.butt_margin
	var runs := PackedVector2Array()
	for at_bone in skin._torso_bones.size():
		var bone := skin._torso_bones[at_bone]
		var posed := skeleton.get_bone_pose(bone)
		var parent := skeleton.get_bone_parent(bone)
		while parent >= 0:
			posed = skeleton.get_bone_pose(parent) * posed
			parent = skeleton.get_bone_parent(parent)
		var pose := to_gun * posed
		for group in range(skin._torso_starts[at_bone], skin._torso_starts[at_bone + 1]):
			for index in range(skin._skin_starts[group], skin._skin_starts[group + 1]):
				var at := pose * skin._skin_points[index]
				if absf(at.x) >= wide:
					continue
				var one := (at.y - high) / move.x
				var other := (at.y + high) / move.x
				var low := maxf((at.z - held.butt_depth) / move.y, minf(one, other))
				var top := minf((at.z + held.butt_margin) / move.y, maxf(one, other))
				if top > maxf(low, 0.0):
					runs.append(Vector2(low, top))
	runs.sort()
	var pushed := 0.0
	for run in runs:
		if run.x >= pushed:
			break
		pushed = maxf(pushed, run.y)
	return pushed


# The push along the barrel as `main` worked it out, over every point of the skin with no box met
# first: the deepest point inside the stock, each bone's pose from every local pose up to the root.
func _plain_barrel_push(
	skin: TorsoSkin, skeleton: Skeleton3D, gun: Transform3D, to_here: Transform3D, held: TwoHandHold
) -> float:
	var to_gun := gun.affine_inverse() * to_here
	var wide := held.butt_pad.x * 0.5 + held.butt_margin
	var high := held.butt_pad.y * 0.5 + held.butt_margin
	var deepest := 0.0
	for at_bone in skin._torso_bones.size():
		var bone := skin._torso_bones[at_bone]
		var posed := skeleton.get_bone_pose(bone)
		var parent := skeleton.get_bone_parent(bone)
		while parent >= 0:
			posed = skeleton.get_bone_pose(parent) * posed
			parent = skeleton.get_bone_parent(parent)
		var pose := to_gun * posed
		for group in range(skin._torso_starts[at_bone], skin._torso_starts[at_bone + 1]):
			for index in range(skin._skin_starts[group], skin._skin_starts[group + 1]):
				var at := pose * skin._skin_points[index]
				if absf(at.x) > wide or absf(at.y) > high:
					continue
				if at.z < -held.butt_margin or at.z > held.butt_depth:
					continue
				deepest = maxf(deepest, at.z + held.butt_margin)
	return deepest

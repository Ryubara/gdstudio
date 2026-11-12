# The prone reload clip (kit #1185) with the game's hold on it, on the skinned mesh of both
# bodies, each playing its own file (`prone_reload.glb` on `form_female`, `prone_reload_male.glb`
# on `form_male`), after the hold's modifiers ran (`HoldStage`, `HandContact`): the clip starts and
# ends on the prone aim's pose, the right hand holds the pistol throughout, the left hand is on
# the pistol at the clip's ends and under the magazine while it goes in within the hold's limits
# (2 mm in, 5 mm off) and passes through nothing between, the clip has the left hand where the
# hold wants it (so the hold's reach moves next to nothing), and the hands and the pistol stay
# over the floor.
extends GdUnitTestSuite

const CLIP := CharacterClips.PRONE_RELOAD
const MODELS: Array[String] = ["female", "male"]
## The shares of the clip that are measured: every 2 hundredths, and every hundredth of the spans
## in which the hold moves the left hand near the pistol (`test_pistol_hold.gd` has the reason).
const STEP := 0.02
const MOVING: Array[Vector2] = [Vector2(0.0, 0.12), Vector2(0.3, 0.56), Vector2(0.69, 0.92)]
## The shares in which the left hand is on the pistol (to the first, from the second) and under
## the magazine (between the third and the fourth): the standing reload's, which the clip keeps.
const ON_GUN_UNTIL := 0.02
const ON_GUN_FROM := 0.9
const MAGAZINE_FROM := 0.54
const MAGAZINE_UNTIL := 0.71
## The shares in which the hold has the left hand all the way (to the first, from the second).
const HOLD_HAS_IT: Array[float] = [0.06, 0.4]
## How far the left hand's bone may stop from its marker, in metres.
const REACH := 0.005
## How far the hold may move the left hand's bone and its elbow from where the clip has them
## while the hold has the hand, in metres: next to nothing on either body, since each plays the
## clip solved on its own arms with its own hold (one clip for both left the male's pistol 7 to
## 9 cm from where the clip's left hand went).
const HAND_KEPT := 0.004
const ELBOW_KEPT := 0.01
## How far a bone of the clip's first and last pose may be turned from the prone aim's, degrees.
const JOINS := 0.5
## The lowest a hand or finger bone may be over the floor, in metres, and the pistol's parts.
const BONE_FLOOR: Dictionary[String, float] = {"female": 0.008, "male": 0.004}
const PISTOL_FLOOR := 0.0
## The lowest the new magazine in the left hand may be over the floor, in metres, and how far off
## its line up the grip it may be while it goes in (`test_reload_magazine.gd`'s, standing).
const MAGAZINE_FLOOR := 0.005
const ON_LINE := 0.0015

var _holder: Node3D


func before_test() -> void:
	_holder = auto_free(Node3D.new())
	add_child(_holder)


func _shares() -> Array[float]:
	var hundredths := {}
	for step in ceili(1.0 / STEP) + 1:
		hundredths[roundi(step * STEP * 100.0)] = true
	for span in MOVING:
		for step in range(roundi(span.x * 100.0), roundi(span.y * 100.0) + 1):
			hundredths[step] = true
	var steps := hundredths.keys()
	steps.sort()
	var shares: Array[float] = []
	for step: int in steps:
		shares.append(step * 0.01)
	return shares


# The clip at `share` of its length with the hold told the reload is that far in, lying and
# aiming (the clip's own elbow kept).
func _pose(stage: HoldStage, share: float) -> void:
	if stage.hold != null:
		stage.hold.set(&"support_keep_elbow", 1.0)
	var length := stage.clip(CLIP).length
	stage.pose(CLIP, minf(share * length, length - 0.001), 1.0, &"", [], share)
	await stage.settle()


func test_the_clip_starts_and_ends_on_the_prone_aim() -> void:
	for model in MODELS:
		var stage := HoldStage.make(_holder, model, false)
		var reload := stage.clip(CLIP)
		var aim := stage.clip(CharacterClips.PRONE_AIM)
		assert_float(reload.length).is_equal_approx(50.0 / 30.0, 0.001)
		assert_int(reload.loop_mode).is_equal(Animation.LOOP_NONE)
		for track in reload.get_track_count():
			if reload.track_get_type(track) != Animation.TYPE_ROTATION_3D:
				continue
			var path := reload.track_get_path(track)
			var other := aim.find_track(path, Animation.TYPE_ROTATION_3D)
			var missing := "%s: %s is not in the aim" % [model, path]
			assert_int(other).override_failure_message(missing).is_not_equal(-1)
			var joined := aim.rotation_track_interpolate(other, 0.0)
			for time: float in [0.0, reload.length]:
				var turned := reload.rotation_track_interpolate(track, time).angle_to(joined)
				(
					assert_float(rad_to_deg(turned))
					. override_failure_message(
						(
							"%s: %s at %.2f s is %.2f deg off the prone aim"
							% [model, path, time, rad_to_deg(turned)]
						)
					)
					. is_less(JOINS)
				)
		stage.free()


func test_each_body_plays_its_own_file() -> void:
	var files := {}
	for model in MODELS:
		var stage := HoldStage.make(_holder, model, false)
		files[model] = stage.clip(CLIP)
		stage.free()
	assert_object(files["female"]).is_not_same(files["male"])


func test_the_right_hand_holds_the_pistol_through_the_prone_reload() -> void:
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		for step in ceili(1.0 / STEP) + 1:
			var share := minf(step * STEP, 1.0)
			await _pose(stage, share)
			# Against the gun and the other hand: the right thumb rests on the left thumb's root
			# while that hand is on the pistol (kit #1171), as standing.
			var parts := stage.contact.measure("r", true)
			var tag := "%s prone reload at %.2f r:" % [model, share]
			# The thumb holds only on the frame (no room asked) or with the left hand closed under
			# it: between the two it is in the air, as `test_pistol_hold.gd` has it standing.
			var contacts := HoldStage.RIGHT_CONTACTS
			var plan := (stage.hold as WeaponHold).left_hand()
			var under := plan.room >= 1.0 and plan.off <= 0.0 and plan.opened <= 0.0
			if plan.room > 0.0 and not under:
				contacts = contacts.filter(func(part: String) -> bool: return part != "thumb_tip")
			var fails := HandContact.failures(tag, parts, contacts)
			assert_array(fails).override_failure_message("\n".join(fails)).is_empty()
		stage.free()


func test_the_left_hand_follows_the_prone_reload() -> void:
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		for share in _shares():
			await _pose(stage, share)
			var tag := "%s prone reload at %.2f" % [model, share]
			var contacts: Array[String] = []
			var marker := ^""
			if share <= ON_GUN_UNTIL or share >= ON_GUN_FROM:
				contacts = HoldStage.LEFT_CONTACTS
				marker = ^"SupportHand"
			elif share >= MAGAZINE_FROM and share <= MAGAZINE_UNTIL:
				contacts = HoldStage.MAGAZINE_CONTACTS
				marker = ^"MagazineHand"
			var parts := stage.contact.measure("l", true)
			if marker.is_empty():
				for part: String in parts:
					var depth: float = -parts[part].distance
					(
						assert_float(depth)
						. override_failure_message(
							"%s l: %s %.1f mm inside on the way" % [tag, part, depth * 1e3]
						)
						. is_less_equal(HandContact.MAX_DEPTH)
					)
				continue
			var fails := HandContact.failures(tag + " l:", parts, contacts)
			assert_array(fails).override_failure_message("\n".join(fails)).is_empty()
			var at := (stage.pistol.get_node(marker) as Node3D).global_position
			var gap := stage.bone_origin(&"hand_l").distance_to(at)
			(
				assert_float(gap)
				. override_failure_message(
					"%s: the left hand is %.1f mm from %s" % [tag, gap * 1e3, marker]
				)
				. is_less(REACH)
			)
		stage.free()


# The clip is solved with the left hand on the hold's own places, so the hold's reach finds the
# hand there already and keeps the clip's elbow.
func test_the_clip_has_the_left_hand_where_the_hold_wants_it() -> void:
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		var bare := HoldStage.make(_holder, model, false)
		for step in ceili(1.0 / STEP) + 1:
			var share := minf(step * STEP, 1.0)
			if share > HOLD_HAS_IT[0] and share < HOLD_HAS_IT[1]:
				continue
			await _pose(stage, share)
			await _pose(bare, share)
			for entry: Array in [[&"hand_l", HAND_KEPT], [&"lowerarm_l", ELBOW_KEPT]]:
				var bone: StringName = entry[0]
				var moved := stage.bone_origin(bone).distance_to(bare.bone_origin(bone))
				(
					assert_float(moved)
					. override_failure_message(
						(
							"%s prone reload at %.2f: the hold moves %s %.1f mm"
							% [model, share, bone, moved * 1e3]
						)
					)
					. is_less(entry[1] as float)
				)
		stage.free()
		bare.free()


func test_the_hands_and_the_pistol_stay_over_the_floor() -> void:
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		for step in ceili(1.0 / STEP) + 1:
			var share := minf(step * STEP, 1.0)
			await _pose(stage, share)
			var lowest := 1.0
			var lowest_bone := ""
			for bone in stage.skeleton.get_bone_count():
				var bone_name := stage.skeleton.get_bone_name(bone)
				var cursor := bone
				var in_hand := false
				while cursor >= 0:
					in_hand = in_hand or stage.skeleton.get_bone_name(cursor).begins_with("hand_")
					cursor = stage.skeleton.get_bone_parent(cursor)
				if in_hand and stage.bone_origin(bone_name).y < lowest:
					lowest = stage.bone_origin(bone_name).y
					lowest_bone = bone_name
			(
				assert_float(lowest)
				. override_failure_message(
					"%s at %.2f: %s is %.1f mm up" % [model, share, lowest_bone, lowest * 1e3]
				)
				. is_greater(BONE_FLOOR[model])
			)
			for part: String in ["Magazine", "Muzzle"]:
				var node := stage.pistol.find_child(part, true, false) as Node3D
				(
					assert_float(node.global_position.y)
					. override_failure_message(
						(
							"%s at %.2f: the pistol's %s is %.1f mm up"
							% [model, share, part, node.global_position.y * 1e3]
						)
					)
					. is_greater(PISTOL_FLOOR)
				)
		stage.free()


# The new magazine (kit #1052) rides the left hand through the prone reload as it does standing:
# in the hand from the belt, over the floor all the way, and up the grip's own line as it goes in.
func test_the_new_magazine_stays_over_the_floor_and_goes_up_the_grips_line() -> void:
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		var hold := stage.hold as WeaponHold
		await _pose(stage, 0.0)
		var gun_magazine := stage.pistol.get_node("Pistol/Magazine") as Node3D
		var rest := WeaponHold._in(gun_magazine, stage.pistol)
		var line := hold.magazine_approach.normalized()
		var held := hold.held_magazine()
		var mesh := held.get_child(0) as MeshInstance3D
		var box := mesh.mesh.get_aabb()
		var carried := 0
		for step in 101:
			var share := step * 0.01
			await _pose(stage, share)
			var tag := "%s prone reload at %.2f" % [model, share]
			assert_bool(held.visible).override_failure_message(tag).is_equal(
				share >= hold.reload_take and share < hold.reload_insert.y
			)
			if not held.visible:
				continue
			carried += 1
			var lowest := INF
			for corner in 8:
				lowest = minf(lowest, (mesh.global_transform * box.get_endpoint(corner)).y)
			(
				assert_float(lowest)
				. override_failure_message(
					"%s: the new magazine is %.1f mm over the floor" % [tag, lowest * 1e3]
				)
				. is_greater(MAGAZINE_FLOOR)
			)
			if share < hold.reload_insert.x:
				continue
			var place := stage.pistol.global_transform.affine_inverse() * mesh.global_transform
			var off := place.origin - rest.origin
			var aside := (off - line * off.dot(line)).length()
			(
				assert_float(aside)
				. override_failure_message(
					"%s: the magazine %.1f mm off the grip's line" % [tag, aside * 1e3]
				)
				. is_less(ON_LINE)
			)
		assert_int(carried).override_failure_message("%s: never carried" % model).is_greater(20)
		stage.free()

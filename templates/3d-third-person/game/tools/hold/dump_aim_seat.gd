## Writes what a clip build needs to pose the hands for the pistol (kit #1111) as one JSON file:
## for each body the two hand bones' rests in the model's space as Godot plays them, and that
## body's own hold (`HoldFit`, or the hold scene's own for the default body): the pistol's seat
## on `hand_r`, the left hand's `SupportHand` marker and the wrist turn the grip pose adds
## (`HandPose.turns`), the finger rotations of the grip, trigger and support poses, and every
## bone's rest rotation (the build checks its own rig against them); and, once, the muzzle and
## the grip's foot in the pistol.
## `assets/animation/prone/build_prone_aim_clips.py` reads it, so no number of the hold is typed
## there. For a clip that reloads (kit #1185, `build_prone_reload_clip.py`) it also writes, for
## each body, the `MagazineHand` marker, the way its opened hand leaves the weapon (`way`) and the
## magazine and open finger poses, and once the rest of the left hand's way through a reload as
## `WeaponHold` has it (`reload`: the way down off the seated magazine, the bow of the way back,
## the four pairs of shares and the share at which the hand takes the new magazine). Since the new
## magazine rides the left hand (kit #1052) it writes each body's approach under the magazine, its
## carry poses (closed on the new magazine, and opened to take it) and the shares of the way in
## over which the fingers let go of it, and once the corners of the magazine's mesh in the pistol.
##
## `<godot> --headless --path game -s res://tools/hold/dump_aim_seat.gd -- <out.json>`
extends SceneTree

const MODELS: Dictionary = {
	"form_female": CharacterBodies.FEMALE,
	"form_male": CharacterBodies.MALE,
	"female": CharacterBodies.QUATERNIUS_FEMALE,
	"male": CharacterBodies.QUATERNIUS_MALE,
}
const HELD := "res://assets/weapons/pistol/pistol_held.tscn"
const HOLD := "res://gameplay/weapon/hold/weapon_hold.tscn"


func _initialize() -> void:
	var out := {"models": {}}
	var held := (load(HELD) as PackedScene).instantiate() as BoneAttachment3D
	var pistol := held.get_child(0) as Node3D
	var hold := (load(HOLD) as PackedScene).instantiate() as WeaponHold
	var bone := StringName(held.bone_name)
	for model: String in MODELS:
		var rig := (load(MODELS[model]) as PackedScene).instantiate() as Node3D
		var skeleton := rig.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var to_model := _within(skeleton, rig)
		var body := {}
		for hand: String in ["hand_r", "hand_l"]:
			body[hand] = _xf(to_model * skeleton.get_bone_global_rest(skeleton.find_bone(hand)))
		# The body's own fit, or the scene's hold (solved on the default body).
		var seat := pistol.transform
		var support := (pistol.get_node("SupportHand") as Node3D).transform
		var grip := hold.grip_pose
		var trigger := hold.trigger_pose
		var left := hold.support_pose
		var magazine_node := pistol.get_node_or_null(hold.magazine_marker) as Node3D
		var magazine := magazine_node.transform if magazine_node != null else Transform3D.IDENTITY
		var way := hold.support_way
		var under := hold.magazine_pose
		var open := hold.open_pose
		var carry := hold.carry_pose
		var carry_open := hold.carry_open_pose
		var approach := hold.magazine_approach
		var release := hold.carry_release
		var arrive := hold.carry_arrive
		for fit in hold.fits:
			if fit != null and fit.body == (MODELS[model] as String).get_file():
				seat = fit.seat
				support = fit.support_hand
				grip = fit.grip_pose
				trigger = fit.trigger_pose
				left = fit.support_pose
				magazine = fit.magazine_hand
				way = fit.support_way
				under = fit.magazine_pose
				open = fit.open_pose
				carry = fit.carry_pose
				carry_open = fit.carry_open_pose
				approach = fit.magazine_approach
				release = fit.carry_release
				arrive = fit.carry_arrive
		body["seat"] = _xf(seat)
		body["support"] = _xf(support)
		if magazine_node != null:
			body["magazine"] = _xf(magazine)
			body["way"] = _v(way)
			body["approach"] = _v(approach)
			body["carry_release"] = [release.x, release.y]
			body["carry_arrive"] = [arrive.x, arrive.y]
		var turn: Quaternion = grip.turns[bone]
		body["turn"] = [turn.x, turn.y, turn.z, turn.w]
		body["poses"] = {"grip": _quats(grip), "trigger": _quats(trigger), "support": _quats(left)}
		if under != null and open != null:
			body["poses"]["magazine"] = _quats(under)
			body["poses"]["open"] = _quats(open)
		if carry != null and carry_open != null:
			body["poses"]["carry"] = _quats(carry)
			body["poses"]["carry_open"] = _quats(carry_open)
		var rests := {}
		for index in skeleton.get_bone_count():
			rests[skeleton.get_bone_name(index)] = _quat(skeleton.get_bone_rest(index).basis)
		body["rests"] = rests
		out.models[model] = body
		rig.free()
	out["bone"] = held.bone_name
	var muzzle := pistol.find_child("Muzzle", true, false) as Node3D
	out["muzzle"] = _xf(_within(muzzle, pistol))
	# The magazine's origin is its foot: the lowest point of the grip.
	var magazine_mesh := pistol.find_child("Magazine", true, false) as MeshInstance3D
	out["foot"] = _xf(_within(magazine_mesh, pistol))
	# The eight corners of the magazine's mesh in the pistol, for the new one in the left hand.
	var box := magazine_mesh.mesh.get_aabb()
	var corners := []
	for index in 8:
		corners.append(_v(_within(magazine_mesh, pistol) * box.get_endpoint(index)))
	out["magazine_box"] = corners
	out["reload"] = {
		"return_down": _v(hold.return_down),
		"take": hold.reload_take,
		"clearance": _v(hold.return_clearance),
		"leave": [hold.reload_leave.x, hold.reload_leave.y],
		"reach": [hold.reload_reach.x, hold.reload_reach.y],
		"insert": [hold.reload_insert.x, hold.reload_insert.y],
		"back": [hold.reload_return.x, hold.reload_return.y],
	}
	held.free()
	hold.free()
	var file := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	file.store_string(JSON.stringify(out, " "))
	file.close()
	print("wrote ", OS.get_cmdline_user_args()[0])
	quit()


# A hand pose's finger rotations (each in its parent bone's space), by bone.
func _quats(pose: HandPose) -> Dictionary:
	var found := {}
	for bone: StringName in pose.rotations:
		var turn := pose.rotations[bone]
		found[String(bone)] = [turn.x, turn.y, turn.z, turn.w]
	return found


func _quat(basis: Basis) -> Array:
	var turn := basis.get_rotation_quaternion()
	return [turn.x, turn.y, turn.z, turn.w]


# A node's transform in the space of `above`, a node over it (neither needs to be in the tree).
func _within(node: Node3D, above: Node3D) -> Transform3D:
	var found := Transform3D.IDENTITY
	var cursor := node
	while cursor != above:
		found = cursor.transform * found
		cursor = cursor.get_parent() as Node3D
	return found


func _v(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


# A transform as twelve numbers: the basis' columns x, y, z, then the origin.
func _xf(xf: Transform3D) -> Array:
	var b := xf.basis
	var o := xf.origin
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, o.x, o.y, o.z]

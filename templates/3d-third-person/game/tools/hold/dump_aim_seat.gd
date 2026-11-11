## Writes what a clip build needs to pose the hands for the pistol (kit #1111) as one JSON file:
## for each mannequin the two hand bones' rests in the model's space as Godot plays them, and the
## pistol's seat on `hand_r`, the left hand's `SupportHand` marker, the muzzle, the grip's foot
## and the wrist turn the grip pose adds (`HandPose.turns`).
## `assets/animation/prone/build_prone_aim_clips.py` reads it, so no number of the hold is typed
## there. For a clip that reloads (kit #1185, `build_prone_reload_clip.py`) it also writes the
## `MagazineHand` marker and the left hand's way through a reload as `WeaponHold` has it
## (`reload`: the way off the weapon, the approach under the magazine, the bow of the way back and
## the four pairs of shares).
##
## `<godot> --headless --path game -s res://tools/hold/dump_aim_seat.gd -- <out.json>`
extends SceneTree

const MODELS: Dictionary = {
	"female": "res://assets/characters/mannequin/mannequin_female.glb",
	"male": "res://assets/characters/mannequin/mannequin_male.glb",
}
const HELD := "res://assets/weapons/pistol/pistol_held.tscn"
const GRIP := "res://gameplay/weapon/hold/pistol_grip_pose.tres"
const HOLD := "res://gameplay/weapon/hold/weapon_hold.tscn"


func _initialize() -> void:
	var out := {"models": {}}
	for model: String in MODELS:
		var rig := (load(MODELS[model]) as PackedScene).instantiate() as Node3D
		var skeleton := rig.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var to_model := _within(skeleton, rig)
		var hands := {}
		for bone: String in ["hand_r", "hand_l"]:
			hands[bone] = _xf(to_model * skeleton.get_bone_global_rest(skeleton.find_bone(bone)))
		out.models[model] = hands
		rig.free()
	var held := (load(HELD) as PackedScene).instantiate() as BoneAttachment3D
	var pistol := held.get_child(0) as Node3D
	out["bone"] = held.bone_name
	out["seat"] = _xf(pistol.transform)
	out["support"] = _xf((pistol.get_node("SupportHand") as Node3D).transform)
	var muzzle := pistol.find_child("Muzzle", true, false) as Node3D
	out["muzzle"] = _xf(_within(muzzle, pistol))
	# The magazine's origin is its foot: the lowest point of the grip.
	out["foot"] = _xf(_within(pistol.find_child("Magazine", true, false) as Node3D, pistol))
	var turn: Quaternion = (load(GRIP) as HandPose).turns[StringName(held.bone_name)]
	out["turn"] = [turn.x, turn.y, turn.z, turn.w]
	var hold := (load(HOLD) as PackedScene).instantiate() as WeaponHold
	var magazine := pistol.get_node_or_null(hold.magazine_marker) as Node3D
	if magazine != null:
		out["magazine"] = _xf(magazine.transform)
		out["reload"] = {
			"way": _v(hold.support_way),
			"approach": _v(hold.magazine_approach),
			"clearance": _v(hold.return_clearance),
			"leave": [hold.reload_leave.x, hold.reload_leave.y],
			"reach": [hold.reload_reach.x, hold.reload_reach.y],
			"insert": [hold.reload_insert.x, hold.reload_insert.y],
			"back": [hold.reload_return.x, hold.reload_return.y],
		}
	hold.free()
	held.free()
	var file := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	file.store_string(JSON.stringify(out, " "))
	file.close()
	print("wrote ", OS.get_cmdline_user_args()[0])
	quit()


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

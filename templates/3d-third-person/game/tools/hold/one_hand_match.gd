## Measures where each body's right hand holds the pistol in the one-handed aim (kit #1085), in
## the gun's own space (muzzle -X, up +Y, its left +Z), in millimetres: each finger's three joints
## and its tip (the skin's farthest point along the last bone), the palm's bone, and each part's
## distance to the gun. The bodies hold the pistol with one finger placement (the female body's,
## kit #1274), so the same point on each body should land on the same place of the gun:
## `test_one_handed_hold.gd` holds them to `PLACEMENT`. Nothing is written.
##
## `<godot> --headless --path game -s res://tools/hold/one_hand_match.gd`
extends SceneTree

const FINGERS: Array[String] = ["index", "middle", "ring", "pinky", "thumb"]
const MODELS: Array[String] = ["female", "male"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var found := {}
	for model in MODELS:
		var stage := HoldStage.make(root, model)
		stage.hold.set(&"one_handed", true)
		await process_frame
		stage.pose(CharacterClips.PISTOL_AIM, 0.0, 1.0, &"ual1/Idle", [WeaponDef.FREE_ARM_BONE])
		await stage.settle()
		found[model] = places(stage)
		var parts := stage.contact.measure("r", false)
		var text := PackedStringArray()
		for part: String in parts:
			text.append("%s %.1f" % [part, parts[part].gun * 1e3])
		print("GAP %s | %s" % [model, ", ".join(text)])
		stage.free()
	for point: String in found["female"]:
		var a: Vector3 = found["female"][point] * 1e3
		var b: Vector3 = found["male"][point] * 1e3
		print(
			(
				"AT %-10s female (%6.1f %6.1f %6.1f)  male (%6.1f %6.1f %6.1f)  apart %5.1f"
				% [point, a.x, a.y, a.z, b.x, b.y, b.z, a.distance_to(b)]
			)
		)
	quit()


## Each finger's joints and tip and the palm's bone in the gun's space, in metres:
## {"index_1": Vector3, ..., "index_tip": Vector3, "palm": Vector3}.
static func places(stage: HoldStage) -> Dictionary:
	var to_gun := stage.pistol.global_transform.affine_inverse() * stage.skeleton.global_transform
	var found := {"palm": to_gun * stage.contact.bone_pose(&"hand_r").origin}
	for finger in FINGERS:
		for joint in 3:
			var bone := StringName("%s_0%d_r" % [finger, joint + 1])
			found["%s_%d" % [finger, joint + 1]] = to_gun * stage.contact.bone_pose(bone).origin
		found[finger + "_tip"] = to_gun * tip(stage, StringName(finger + "_03_r"))
	return found


## A finger's tip in the skeleton's space: its last bone's skin vertex farthest along the bone.
static func tip(stage: HoldStage, bone: StringName) -> Vector3:
	var pose := stage.contact.bone_pose(bone)
	var along := pose.basis.y.normalized()
	var part := "%s_tip" % String(bone).get_slice("_", 0)
	var list: Array = stage.contact.get(&"_parts")["r"][part]
	var cache := {}
	var best := pose.origin
	var reach := 0.0
	for index in list.size() / 2:
		var at: Vector3 = stage.contact.call(
			&"_skinned", list[index * 2], list[index * 2 + 1], cache
		)
		var out := (at - pose.origin).dot(along)
		if out > reach:
			reach = out
			best = at
	return best

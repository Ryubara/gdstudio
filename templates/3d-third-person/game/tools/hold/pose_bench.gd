## The bench a finger pose is set by hand on (kit #1084): it lays the angles of an authored file
## (`authored_pose.gd`) over the hold the project has, on `HoldStage` as the tests build it, and
## prints what the game's own measure (`HandContact`) makes of it, in the words of
## `tests/gameplay/test_pistol_hold.gd`: what fails, and with `PARTS=1` every part of both hands
## against the gun (`g`) and the other hand (`h`), in millimetres. Nothing is written:
## `write_hold.gd` does that.
##
## `<godot> --headless --path game -s res://tools/hold/pose_bench.gd -- <body> <authored.json>
## <cases>`
##
## The cases, separated by commas: `aim` (the four aim and shoot clips with both hands on the gun;
## `neutral` is the first alone),
## `idle` (one hand), `reload:<from>:<to>:<step>` (shares of the reload while aiming, the right
## thumb's way among them), `carry:<from>:<to>:<step>` (the same with the pistol carried) and
## `room:<steps>` (the right thumb between its two poses in equal steps, the left hand held out at
## the far end of its way, as while the aim comes up). `OBJ=<folder>` writes each case's hands and
## gun as an OBJ file for a look in Blender, and
## `JOINTS=<bone,bone>` prints where those bones are in the gun's own space.
extends SceneTree

const Authored := preload("res://tools/hold/authored_pose.gd")
const AIM: Array[StringName] = [
	&"ual1/Pistol_Aim_Neutral", &"ual1/Pistol_Aim_Up", &"ual1/Pistol_Aim_Down", &"ual1/Pistol_Shoot"
]
const OVER_RIGHT_HAND: Array[String] = [
	"middle_mid", "middle_tip", "ring_mid", "ring_tip", "pinky_mid", "pinky_tip"
]

var _stage: HoldStage
var _body := "female"


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() < 3:
		printerr("pose_bench: <body> <authored.json> <cases>")
		quit(1)
		return
	_body = arguments[0]
	_run.call_deferred(arguments[1], arguments[2])


func _run(authored: String, cases: String) -> void:
	_stage = HoldStage.make(root, _body)
	await process_frame
	await process_frame
	var fit: HoldFit = _stage.hold.fit()
	var poses := Authored.poses(_stage.skeleton, _body, authored)
	for key: String in poses:
		var pose := fit.get(key + "_pose") as HandPose
		if pose == null:
			pose = HandPose.new()
			fit.set(key + "_pose", pose)
		var rotations := pose.rotations.duplicate()
		rotations.merge(poses[key], true)
		pose.rotations = rotations
	_stage.hold.call(&"_build")
	await process_frame
	for case in cases.split(","):
		var words := case.split(":")
		match words[0]:
			"aim":
				for clip in AIM:
					_stage.pose(clip, 0.0, 1.0)
					await _stage.settle()
					_report("%s %s" % [_body, clip], true, true)
			"neutral":
				_stage.pose(AIM[0], 0.0, 1.0)
				await _stage.settle()
				_report("%s neutral" % _body, true, true)
			"idle":
				_stage.pose(&"ual1/Pistol_Idle", 0.5)
				await _stage.settle()
				_report("%s idle" % _body, false, false)
			"reload", "carry":
				var length := _stage.clip(&"ual1/Pistol_Reload").length
				var share := words[1].to_float()
				while share <= words[2].to_float() + 1e-6:
					var aim := 1.0 if words[0] == "reload" else 0.0
					_stage.pose(&"ual1/Pistol_Reload", share * length, aim, &"", [], share)
					await _stage.settle()
					_report("%s %s %.4f" % [_body, words[0], share], true, false)
					share += words[3].to_float()
			"room":
				var steps := words[1].to_int()
				for step in steps + 1:
					var on := lerpf(
						SupportHandPlan.ARM_UNTIL, SupportHandPlan.WAY_FROM, float(step) / steps
					)
					_stage.pose(&"ual1/Pistol_Aim_Neutral", 0.0, on)
					await _stage.settle()
					_report("%s room %.2f" % [_body, float(step) / steps], true, false)
	quit()


func _report(tag: String, two_handed: bool, held: bool) -> void:
	var right := _stage.contact.measure("r", two_handed)
	var plan: SupportHandPlan = _stage.hold.call(&"left_hand")
	var fails: Array[String] = []
	var contacts := HoldStage.RIGHT_CONTACTS
	if two_handed:
		var under := plan.room >= 1.0 and plan.off <= 0.0 and plan.opened <= 0.0
		if plan.room > 0.0 and not under:
			contacts = contacts.filter(func(part: String) -> bool: return part != "thumb_tip")
	fails.append_array(HandContact.failures("r", right, contacts))
	var left := {}
	if two_handed:
		left = _stage.contact.measure("l", true)
		var holding: Array[String] = []
		if held:
			holding = HoldStage.LEFT_CONTACTS
		fails.append_array(HandContact.failures("l", left, holding))
	if held:
		for part in OVER_RIGHT_HAND:
			if left[part].hand > HandContact.MAX_FLOAT:
				fails.append("l %s %.1f off the right hand" % [part, left[part].hand * 1e3])
		if minf(left.index_base.gun, left.index_mid.gun) > HandContact.MAX_FLOAT:
			fails.append("l index off the gun")
		if left.index_tip.hand > HandContact.MAX_FLOAT:
			fails.append("l index_tip %.1f off the right hand" % (left.index_tip.hand * 1e3))
		if left.palm.hand > HandContact.MAX_FLOAT:
			fails.append("l palm %.1f off the right hand" % (left.palm.hand * 1e3))
		if left.thumb_tip.gun > HandContact.MAX_FLOAT:
			fails.append("l thumb %.1f off the gun" % (left.thumb_tip.gun * 1e3))
		if right.thumb_tip.hand > HandContact.MAX_FLOAT:
			fails.append("r thumb %.1f off the left hand" % (right.thumb_tip.hand * 1e3))
		var rests := _stage.skeleton.global_transform * (right.thumb_tip.point as Vector3)
		var from_root := _stage.contact.part_distance_to("l", "thumb_base", rests)
		fails.append("(r thumb %.1f from the left thumb's root)" % (from_root * 1e3))
	print(
		(
			"BENCH %s | room %.2f opened %.2f off %.2f | %s"
			% [tag, plan.room, plan.opened, plan.off, "; ".join(fails)]
		)
	)
	if OS.get_environment("PARTS") == "1":
		print("  r ", _parts(right))
		if two_handed:
			print("  l ", _parts(left))
	if OS.get_environment("JOINTS") != "":
		# Where the named bones are in the gun's own space (muzzle -X, up +Y, its left +Z), in mm.
		var to_gun := _stage.pistol.global_transform.affine_inverse()
		var places := PackedStringArray()
		for bone in OS.get_environment("JOINTS").split(","):
			var at := to_gun * _stage.bone_origin(StringName(bone)) * 1e3
			places.append("%s (%.0f, %.0f, %.0f)" % [bone, at.x, at.y, at.z])
		print("  j ", ", ".join(places))
	if OS.get_environment("OBJ") != "":
		var file := tag.replace(" ", "_").replace("/", "_") + ".obj"
		_stage.contact.dump_obj(OS.get_environment("OBJ").path_join(file))
		# The gun's place in the skeleton's space beside it, for a camera set by the gun's axes.
		var gun := (
			_stage.skeleton.global_transform.affine_inverse() * _stage.pistol.global_transform
		)
		var rows := [gun.basis.x, gun.basis.y, gun.basis.z, gun.origin]
		var place := FileAccess.open(
			OS.get_environment("OBJ").path_join(file + ".json"), FileAccess.WRITE
		)
		place.store_string(
			JSON.stringify(rows.map(func(v: Vector3) -> Array: return [v.x, v.y, v.z]))
		)


func _parts(parts: Dictionary) -> String:
	var text := PackedStringArray()
	for part: String in parts:
		text.append("%s g%.1f h%.1f" % [part, parts[part].gun * 1e3, parts[part].hand * 1e3])
	return ", ".join(text)

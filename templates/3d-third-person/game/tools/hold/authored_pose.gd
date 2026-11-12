extends RefCounted
## Finger poses set by hand (kit #1084), read from `tools/hold/pistol_authored.json`: where the
## solver's search ends in a pose that does not read as a hand (a little finger that reaches under
## the other hand, a thumb whose way crosses the frame), an artist sets the finger's angles, looks
## at it and measures it with `tools/hold/pose_bench.gd`, and `write_hold.gd` lays the result over
## the solved hold, so a new solve keeps it. The one-handed poses (`one_hand`, `one_hand_way`) are
## not set by hand: `fit_one_hand.gd` writes them, every body's fitted to the default body's
## placement on the gun (kit #1274).
##
## The file is `{body: {pose: {finger: [angles]}}}`, in degrees, as `hold_hand.py` takes them: a
## finger's spread at the knuckle and its three bends from the knuckle out; the thumb's root about
## its own Y, Z and X, its middle joint's lean and bend, and its tip's bend. Each is a turn on top
## of the bone's rest. A pose is one of `write_hold.gd`'s keys; it names a hand by `SIDES`.

const FILE := "res://tools/hold/pistol_authored.json"
## The hand each pose of the hold belongs to.
const SIDES: Dictionary[String, String] = {
	"grip": "r",
	"trigger": "r",
	"trigger_way": "r",
	"thumb": "r",
	"thumb_way": "r",
	"one_hand": "r",
	"one_hand_way": "r",
	"support": "l",
	"magazine": "l",
	"open": "l",
}


## The poses set by hand for `body`: {pose: {finger: [angles]}}, empty when the file has none.
static func of_body(body: String, path := FILE) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	return (parsed as Dictionary).get(body, {})


## The rotations of a finger's three bones for `angles`, each in its parent's space as a
## `HandPose` holds them: {bone name: Quaternion}.
static func rotations(
	skeleton: Skeleton3D, side: String, finger: String, angles: Array
) -> Dictionary[StringName, Quaternion]:
	var turns: Array[Basis] = []
	if finger == "thumb":
		var root := _turn(Vector3.UP, angles[0]) * _turn(Vector3.BACK, angles[1])
		turns = [
			root * _turn(Vector3.RIGHT, angles[2]),
			_turn(Vector3.BACK, angles[3]) * _turn(Vector3.RIGHT, angles[4]),
			_turn(Vector3.RIGHT, angles[5]),
		]
	else:
		turns = [
			_turn(Vector3.BACK, angles[0]) * _turn(Vector3.RIGHT, angles[1]),
			_turn(Vector3.RIGHT, angles[2]),
			_turn(Vector3.RIGHT, angles[3]),
		]
	var found: Dictionary[StringName, Quaternion] = {}
	for joint in 3:
		var bone := StringName("%s_0%d_%s" % [finger, joint + 1, side])
		var rest := skeleton.get_bone_rest(skeleton.find_bone(bone)).basis.orthonormalized()
		found[bone] = (rest * turns[joint]).get_rotation_quaternion()
	return found


## Every bone's rotation of the poses set by hand for `body`, on its skeleton:
## {pose: {bone name: Quaternion}}.
static func poses(skeleton: Skeleton3D, body: String, path := FILE) -> Dictionary:
	var found := {}
	var authored := of_body(body, path)
	for pose: String in authored:
		if not SIDES.has(pose):
			continue
		var bones: Dictionary[StringName, Quaternion] = {}
		for finger: String in authored[pose]:
			bones.merge(rotations(skeleton, SIDES[pose], finger, authored[pose][finger]), true)
		found[pose] = bones
	return found


static func _turn(axis: Vector3, degrees: float) -> Basis:
	return Basis(axis, deg_to_rad(degrees))

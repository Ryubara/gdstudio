class_name GaitClips
extends RefCounted
## What the tree needs to know of GDStudio's own clips (gdstudio #1158): the `clips.json` the clip
## build writes beside each shipped file (`assets/animation/own/locomotion.json`), read once for
## every character. Per clip: its speed on the reference body (m/s), its length, its contacts per
## foot, the foot it starts and ends on, its travel and turn curves, and for a transition the gait
## it hands over to and at what phase. A clip it has no record of (a library clip put back as a
## stand-in) is played as the library's always were: at its own pace, at the tuning's speed.
##
## The reference body is the one whose pelvis rests `reference_hips` metres up (0.9166); a body
## with longer legs covers more ground a stride, so a speed is that body's leg length over the
## reference's times the record's (`leg_scale()`).

## The records of each library of our own: the clips of `gds/` come from these files.
const SOURCES := {
	&"gds": ["res://assets/animation/own/locomotion.json"],
}
## The pelvis's rest height of the body the clips are made on, when a file does not say (m).
const REFERENCE_HIPS := 0.9166
## Frames a second of a record's frame numbers, when a file does not say.
const FPS := 30.0

static var _records: Dictionary = {}
static var _loaded: Dictionary = {}
## The clips already looked for: a frame asks again without working out the library's name.
static var _looked: Dictionary = {}
## `contacts()` worked out once per clip and foot (`{clip: {foot: shares}}`), asked every frame.
static var _contacts: Dictionary = {}
static var _hips := REFERENCE_HIPS


## The record of `clip` (`gds/Walk`), or an empty dictionary when there is none.
static func record(clip: StringName) -> Dictionary:
	if not _looked.has(clip):
		_load(clip)
		_looked[clip] = true
	return _records.get(clip, {})


## True when `clip` has a record.
static func has(clip: StringName) -> bool:
	return not record(clip).is_empty()


## The ground speed `clip` covers at its own pace on the reference body, in m/s; `fallback` when it
## has no record or its record has no speed (a clip that stands).
static func speed(clip: StringName, fallback: float) -> float:
	var found: float = record(clip).get("speed", 0.0)
	return found if found > 0.0 else fallback


## The length of `clip` in seconds from its record, or 0.
static func seconds(clip: StringName) -> float:
	return float(record(clip).get("seconds", 0.0))


## The share of `clip`'s cycle (0 to 1) at which `foot` (`"l"` or `"r"`) is down in every
## contact, as `[from, to]` pairs; empty without a record.
## Read-only: the list is worked out once and shared.
static func contacts(clip: StringName, foot: String) -> Array:
	var cache: Dictionary = _contacts.get(clip, {})
	if cache.has(foot):
		return cache[foot]
	var found := record(clip)
	var frames: float = found.get("frames", 0.0)
	var shares: Array = []
	if frames > 0.0:
		for contact: Array in found.get("contacts", {}).get(foot, []):
			var share := [contact[0] / frames, contact[1] / frames]
			share.make_read_only()
			shares.append(share)
	shares.make_read_only()
	cache[foot] = shares
	_contacts[clip] = cache
	return shares


## The foot that is down at `phase` (0 to 1) of a gait's cycle and has been down the longest: `"l"`,
## `"r"` or `""` when neither is (in the air) or the clip has no record.
static func planted_foot(clip: StringName, phase: float) -> String:
	var best := ""
	var longest := -1.0
	for foot: String in ["l", "r"]:
		for window: Array in contacts(clip, foot):
			if phase >= window[0] and phase <= window[1] and phase - window[0] > longest:
				longest = phase - window[0]
				best = foot
	return best


## The distance travelled along the clip's forward axis at `time` seconds, from its travel curve
## (frame, forward, left), in metres on the reference body; 0 without a record.
static func travel_at(clip: StringName, time: float) -> float:
	var curve: Array = record(clip).get("travel", [])
	if curve.is_empty():
		return 0.0
	var frame := time * FPS
	for index in range(curve.size() - 1):
		var a: Array = curve[index]
		var b: Array = curve[index + 1]
		if frame <= b[0]:
			var share := clampf((frame - a[0]) / maxf(b[0] - a[0], 0.001), 0.0, 1.0)
			return lerpf(a[1], b[1], share)
	return curve[-1][1]


## The time in seconds at which `clip`'s travel curve first reaches `distance` metres (on the
## reference body), held to the clip's length: a transition is played by the ground the body
## really covered. -1 without a record or a curve that never moves.
static func time_at_travel(clip: StringName, distance: float) -> float:
	var curve: Array = record(clip).get("travel", [])
	if curve.size() < 2 or is_zero_approx(curve[-1][1] - curve[0][1]):
		return -1.0
	for index in range(curve.size() - 1):
		var a: Array = curve[index]
		var b: Array = curve[index + 1]
		if distance <= b[1] or index == curve.size() - 2:
			var share := clampf((distance - a[1]) / maxf(b[1] - a[1], 0.0001), 0.0, 1.0)
			return lerpf(a[0], b[0], share) / FPS
	return float(curve[-1][0]) / FPS


## The time in seconds at which `clip`'s turn curve (frame, degrees) has turned `degrees` (either
## way), held to the clip's length. -1 without a record or a curve that never turns.
static func time_at_turn(clip: StringName, degrees: float) -> float:
	var curve: Array = record(clip).get("turn", [])
	if curve.size() < 2 or is_zero_approx(curve[-1][1] - curve[0][1]):
		return -1.0
	for index in range(curve.size() - 1):
		var a: float = absf(curve[index][1])
		var b: float = absf(curve[index + 1][1])
		if degrees <= b or index == curve.size() - 2:
			var share := clampf((degrees - a) / maxf(b - a, 0.0001), 0.0, 1.0)
			return lerpf(curve[index][0], curve[index + 1][0], share) / FPS
	return float(curve[-1][0]) / FPS


## The leg length of the body `skeleton` draws, in the space of `owner` (the character, whose
## speed is measured), over the reference body's: 1 for the template's bodies, more for a body with
## longer legs or a model drawn larger. 1 when the skeleton has no `pelvis`.
static func leg_scale(skeleton: Skeleton3D, owner: Node3D) -> float:
	if skeleton == null or owner == null or not skeleton.is_inside_tree():
		return 1.0
	var pelvis := skeleton.find_bone(&"pelvis")
	if pelvis < 0:
		return 1.0
	var into_owner := owner.global_transform.affine_inverse() * skeleton.global_transform
	var hips := (into_owner * skeleton.get_bone_global_rest(pelvis).origin).y
	return hips / _hips if hips > 0.0 else 1.0


## Gives `clip` a record of its own (a game's clip, a test's), in the form of `clips.json`.
static func register(clip: StringName, data: Dictionary) -> void:
	_records[clip] = data
	_contacts.erase(clip)


## Takes away a record `register()` gave.
static func forget(clip: StringName) -> void:
	_records.erase(clip)
	_contacts.erase(clip)


static func _load(clip: StringName) -> void:
	var library := StringName(String(clip).get_slice("/", 0))
	if _loaded.has(library) or not SOURCES.has(library):
		return
	_loaded[library] = true
	for path: String in SOURCES[library]:
		if not FileAccess.file_exists(path):
			push_warning("GaitClips: no %s: its clips play at their own pace" % path)
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary:
			push_warning("GaitClips: %s is not a clips.json" % path)
			continue
		_hips = float(parsed.get("reference_hips", REFERENCE_HIPS))
		var clips: Dictionary = parsed.get("clips", {})
		for name: String in clips:
			var key := StringName("%s/%s" % [library, name])
			if not _records.has(key):
				_records[key] = clips[name]

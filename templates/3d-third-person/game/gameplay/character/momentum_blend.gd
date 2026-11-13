class_name MomentumBlend
extends SkeletonModifier3D
## The momentum blend between body states (gdstudio #1158): when the body machine changes state
## (or a transition clip begins or ends), the new state's pose is shown at once, plus the
## difference between it and the pose the last frame showed, and that difference dies away like a
## critically damped spring that starts with the speed the old pose was moving at. A cross-fade
## plays both states for its whole length and drags the old motion's speed to nothing; this plays
## only the new one, and the body goes on moving the way it moved (Bollo's inertialization, GDC
## 2018; the research: kit `docs/tools/blender/animation-research.md#research-layers`).
##
## The first modifier of the skeleton, so the weapon hold, the aim and the rest work on the pose
## it hands on. Each frame it keeps the pose it handed on and the one before; at a change it takes
## each bone's turn from the new pose to the last one shown (`x0`, an axis times an angle) and the
## turn's speed (`v0`, from the last two frames, held to `speed_limit`), and adds
## `exp(x(t)) * pose` with `x(t) = (x0 + (v0 + x0 y) t) e^(-y t)`, `y = 2 ln 2 / half_life`, to
## every bone that differed, and the same to the pelvis's place. Nothing while the tree is off (a
## ragdoll holds the skeleton). Cosmetic, never sent.
##
## The new state's pose reaches the skeleton a frame or two after the key changes (the state
## machine reports its new node in the frame it travels, and the tree draws it on a later update),
## so the blend starts again from the pose last shown on each of `SETTLE_FRAMES` frames after a
## change: each start keeps the drawn pose and its speed, and the one on the frame the new pose
## arrives takes the whole jump (gdstudio #1416).

## Parts of the bone names it leaves to the clip alone.
const SKIPPED: Array[String] = [
	"thumb", "index", "middle", "ring", "pinky", "twist", "socket", "ik_", "root"
]

## Frames after a change of key on which the blend starts again from the pose last shown.
const SETTLE_FRAMES := 3

## The node whose body state it follows (`CharacterGait.pose_key()`).
var animation: CharacterAnimation
## Seconds in which the difference halves.
var half_life := 0.05
## The fastest a bone's turn is carried over, in radians a second.
var speed_limit := deg_to_rad(720.0)

var _key: Variant = null
var _count := -1
var _followed := PackedInt32Array()
var _last: Array[Quaternion] = []
var _before: Array[Quaternion] = []
var _last_pelvis := Vector3.ZERO
var _before_pelvis := Vector3.ZERO
var _seen := 0
var _bones := PackedInt32Array()
var _x0 := PackedVector3Array()
var _j0 := PackedVector3Array()
var _pelvis := -1
var _pelvis_x0 := Vector3.ZERO
var _pelvis_j0 := Vector3.ZERO
var _t := 0.0
var _blending := false
var _settle := 0


## True while a difference is dying away.
func is_blending() -> bool:
	return _blending


## How far the drawn pose is from the state's own now, in radians: the largest turn of a bone the
## blend adds (0 when it adds none).
func largest_offset() -> float:
	if not _blending:
		return 0.0
	var largest := 0.0
	var decay := exp(-_damping() * _t)
	for index in _bones.size():
		largest = maxf(largest, ((_x0[index] + _j0[index] * _t) * decay).length())
	return largest


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_forget()
	_count = -1


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or animation == null or animation.tree == null or not animation.tree.active:
		_forget()
		return
	if _count != skeleton.get_bone_count():
		_forget()
		_follow(skeleton)
	var key: Variant = animation.gait.pose_key(animation)
	if key != _key and _seen >= 2:
		_settle = SETTLE_FRAMES
	_key = key
	if _settle > 0 and delta > 0.0:
		_settle -= 1
		_begin(skeleton, delta)
	if _blending:
		_apply(skeleton, delta)
	_remember(skeleton)


func _begin(skeleton: Skeleton3D, delta: float) -> void:
	_bones.clear()
	_x0.clear()
	_j0.clear()
	var y := _damping()
	for slot in _followed.size():
		var bone := _followed[slot]
		var now := skeleton.get_bone_pose_rotation(bone)
		var x0 := _turn(_last[slot] * now.inverse())
		var v0 := (_turn(_last[slot] * _before[slot].inverse()) / delta).limit_length(speed_limit)
		if x0.length() < 0.002 and v0.length() < 0.05:
			continue
		_bones.append(bone)
		_x0.append(x0)
		_j0.append(v0 + x0 * y)
	if _pelvis >= 0:
		var place := skeleton.get_bone_pose_position(_pelvis)
		_pelvis_x0 = _last_pelvis - place
		var speed := (_last_pelvis - _before_pelvis) / delta
		_pelvis_j0 = speed.limit_length(4.0) + _pelvis_x0 * y
	_t = 0.0
	_blending = true


func _apply(skeleton: Skeleton3D, delta: float) -> void:
	_t += delta
	var decay := exp(-_damping() * _t)
	for index in _bones.size():
		var bone := _bones[index]
		var offset := (_x0[index] + _j0[index] * _t) * decay
		var turn := (
			Quaternion(offset.normalized(), offset.length())
			if offset.length() > 1e-6
			else Quaternion.IDENTITY
		)
		skeleton.set_bone_pose_rotation(bone, turn * skeleton.get_bone_pose_rotation(bone))
	if _pelvis >= 0:
		var moved := (_pelvis_x0 + _pelvis_j0 * _t) * decay
		skeleton.set_bone_pose_position(_pelvis, skeleton.get_bone_pose_position(_pelvis) + moved)
	if _t > 8.0 * half_life:
		_blending = false


func _remember(skeleton: Skeleton3D) -> void:
	var swap := _before
	_before = _last
	_last = swap
	for slot in _followed.size():
		_last[slot] = skeleton.get_bone_pose_rotation(_followed[slot])
	if _pelvis >= 0:
		_before_pelvis = _last_pelvis
		_last_pelvis = skeleton.get_bone_pose_position(_pelvis)
	_seen += 1


# The bones it carries: the body's, without the fingers, the twist bones, the sockets and the
# `ik_` targets (a clip turns few of them, and each bone read every frame costs).
func _follow(skeleton: Skeleton3D) -> void:
	_count = skeleton.get_bone_count()
	_followed.clear()
	for bone in _count:
		var bone_name := String(skeleton.get_bone_name(bone)).to_lower()
		if not SKIPPED.any(func(part: String) -> bool: return bone_name.contains(part)):
			_followed.append(bone)
	_last.resize(_followed.size())
	_before.resize(_followed.size())
	_pelvis = skeleton.find_bone(&"pelvis")


func _forget() -> void:
	_seen = 0
	_settle = 0
	_blending = false
	_key = null


func _damping() -> float:
	return 2.0 * log(2.0) / maxf(half_life, 0.001)


# `turn` as an axis times its angle (radians), the short way round.
static func _turn(turn: Quaternion) -> Vector3:
	var q := turn.normalized()
	if q.w < 0.0:
		q = -q
	var angle := 2.0 * acos(clampf(q.w, -1.0, 1.0))
	var axis := Vector3(q.x, q.y, q.z)
	return axis.normalized() * angle if axis.length() > 1e-7 else Vector3.ZERO

class_name ArmCarrySteady
extends SkeletonModifier3D
## Keeps the arms of a character that carries a weapon in one hand on one readable carry
## (gdstudio #1577). With the pistol carried the arms follow the locomotion clips (`HAND_ONLY`),
## and the gun rides the forearm: a jog's swing turned it 90 degrees a stride (down by the thigh,
## then level forward), a sprint's put it up by the head, a reversal's look flung it out sideways,
## and the gait blend's dip on a turn (the run's bent arm to the walk's hanging one and back in
## four ticks) moved the hand 0.2 m a tick. Each arm bone's carry follows the clip's own rotation
## slowly (`ArmCarry.follow_half_life`), and the bone is drawn at that carry turned by a share of
## the clip's swing about it (`stride_share`, eased under `limit`), so the arm still moves with the
## stride and a gait's carry still comes in, but a swing never throws the gun about; a swing that
## turns about in a tick or two is drawn over a few (`swing_half_life`). Made and
## weighed by the hold's `HoldArmCarry` node: all of it while the weapon is carried, none as it is
## aimed, reloaded or let go, so it fades with the aim's own blend. Before the grip, which turns
## the wrist and holds the arm out after it. Cosmetic, never sent; a few quaternion steps for six
## bones.

const NAME := &"HoldArmSteady"

## The numbers.
var settings: ArmCarry

var _bones := PackedInt32Array()
# Whether each bone is the other arm's (its share and limit are the free ones).
var _free: Array[bool] = []
var _carry: Array[Quaternion] = []
var _swing := PackedVector3Array()
var _count := -1
var _last_frame := -1


## The modifier on `skeleton` for `numbers`, made in place of `made` (the last one, or null),
## right before `before` (the grip) when there is one.
static func attach(
	skeleton: Skeleton3D, numbers: ArmCarry, made: ArmCarrySteady, before: Node
) -> ArmCarrySteady:
	if made != null and is_instance_valid(made):
		made.get_parent().remove_child(made)
		made.queue_free()
	if skeleton == null or numbers == null:
		return null
	var steady := ArmCarrySteady.new()
	steady.name = NAME
	steady.settings = numbers
	steady.active = false
	steady.influence = 0.0
	skeleton.add_child(steady)
	if before != null and before.get_parent() == skeleton:
		skeleton.move_child(steady, before.get_index())
	return steady


## Sets the weight (0 off), written only when it changes, since the setters make the skeleton work.
func weigh(weight: float) -> void:
	if not is_equal_approx(influence, weight):
		influence = weight
	if active != (weight > 0.0):
		active = weight > 0.0


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_count = -1


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or settings == null:
		return
	if _count != skeleton.get_bone_count():
		_find(skeleton)
	var frame := Engine.get_process_frames()
	# Off for a while (aimed, put away): the carry starts again from the clip's arm.
	var fresh := _last_frame < 0 or frame - _last_frame > 2
	_last_frame = frame
	# Fading out (the aim, a reload coming in) the carry and its swing close on the pose under them
	# as fast as the weight goes: held back, the arm stayed down until the aim was nearly up and
	# then went the rest in a tick (0.23 m).
	var keep := clampf(influence, 0.0, 1.0)
	var follow := 1.0 - pow(0.5, delta / maxf(settings.follow_half_life, 0.001)) * keep
	var settle := 1.0 - pow(0.5, delta / maxf(settings.swing_half_life, 0.001)) * keep
	var shares := Vector2(settings.stride_share, settings.free_share)
	var limits := Vector2(deg_to_rad(settings.limit), deg_to_rad(settings.free_limit))
	for slot in _bones.size():
		var bone := _bones[slot]
		var clip := skeleton.get_bone_pose_rotation(bone)
		var carry := clip if fresh else _carry[slot].slerp(clip, follow)
		_carry[slot] = carry
		var swing := _turn(clip * carry.inverse())
		var angle := swing.length()
		var kept := Vector3.ZERO
		if angle > 1e-6:
			var limit := limits.y if _free[slot] else limits.x
			var share := shares.y if _free[slot] else shares.x
			kept = swing / angle * share * limit * tanh(angle / limit)
		_swing[slot] = kept if fresh else _swing[slot].lerp(kept, settle)
		var drawn := _swing[slot]
		if drawn.length() > 1e-6:
			carry = Quaternion(drawn.normalized(), drawn.length()) * carry
		skeleton.set_bone_pose_rotation(bone, carry)


func _find(skeleton: Skeleton3D) -> void:
	_count = skeleton.get_bone_count()
	_bones.clear()
	_free.clear()
	for bones: Array[StringName] in [settings.carry_bones, settings.free_bones]:
		for bone_name in bones:
			var bone := skeleton.find_bone(bone_name)
			if bone >= 0:
				_bones.append(bone)
				_free.append(bones == settings.free_bones)
	_carry.resize(_bones.size())
	_swing.resize(_bones.size())
	_last_frame = -1


# `turn` as an axis times its angle (radians), the short way round.
static func _turn(turn: Quaternion) -> Vector3:
	var q := turn.normalized()
	if q.w < 0.0:
		q = -q
	var angle := 2.0 * acos(clampf(q.w, -1.0, 1.0))
	var axis := Vector3(q.x, q.y, q.z)
	return axis.normalized() * angle if axis.length() > 1e-7 else Vector3.ZERO

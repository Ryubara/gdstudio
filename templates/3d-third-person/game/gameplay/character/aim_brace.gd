class_name AimBrace
extends SkeletonModifier3D
## Holds the upper body's turn while the character aims, whatever the legs' clip does to the
## pelvis (kit #1154). The weapon layer of `CharacterAnimation` puts the aim poses on the upper
## body only, so they ride the pelvis of the clip under them, and they were made on one stance:
## the library's pistol poses stand on a pelvis turned 13 degrees and tipped back 6. Over any
## other pelvis (the library's own walk, an idle of ours that stands square) the whole upper body
## was turned by the difference, and the pistol pointed 13 to 18 degrees off the view.
##
## It turns `bone`, the first bone of the upper body, so that it stands on `stance`, the turn its
## parent has in the aim clip, instead of on the turn its parent has now. Only the turn is held:
## the upper body still goes where the pelvis goes, so a step or a weight shift moves it.
## `CharacterAnimation` makes it on the model's skeleton, first of its modifiers, and fades it
## with the aim (`influence`) through a `Driver`; it is a pose worked out on each machine and
## never sent over a network.

## The first bone of the upper body.
@export var bone: StringName = &"spine_01":
	set(value):
		bone = value
		_bone = -2
## The turn of `bone`'s parent, in the skeleton's space, in the stance the aim poses were made
## on (`stance_of()`).
@export var stance := Quaternion.IDENTITY

var _bone := -2


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_bone = -2


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if _bone == -2:
		_bone = skeleton.find_bone(bone)
	var parent := skeleton.get_bone_parent(_bone) if _bone >= 0 else -1
	if parent < 0:
		return
	var above := HandPoseModifier.global_pose(skeleton, parent).basis.orthonormalized()
	# The bone keeps its own pose, on the stance's turn instead of its parent's.
	var held := above.inverse().get_rotation_quaternion() * stance
	skeleton.set_bone_pose_rotation(_bone, held * skeleton.get_bone_pose_rotation(_bone))


## The turn, in the skeleton's space, that `bone`'s parent has at the start of `animation` (a
## bone the clip has no rotation track for is at rest), or the identity when the skeleton has no
## such bone or it has no parent. `tracks` is the clips' path to the skeleton
## (`Armature/Skeleton3D`).
static func stance_of(
	skeleton: Skeleton3D, animation: Animation, bone_name: StringName, tracks: String
) -> Quaternion:
	var chain: Array[int] = []
	var cursor := skeleton.get_bone_parent(skeleton.find_bone(bone_name))
	while cursor >= 0:
		chain.push_front(cursor)
		cursor = skeleton.get_bone_parent(cursor)
	var turn := Quaternion.IDENTITY
	for index in chain:
		var path := NodePath("%s:%s" % [tracks, skeleton.get_bone_name(index)])
		var track := animation.find_track(path, Animation.TYPE_ROTATION_3D)
		if track >= 0 and animation.track_get_key_count(track) > 0:
			turn = turn * animation.rotation_track_interpolate(track, 0.0)
		else:
			turn = turn * skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
	return turn.normalized()


## What `CharacterAnimation` does with the brace, kept here so the tree's script stays one size:
## makes it on the model's skeleton, weighs it by the aim and holds the arm up after a shot. The
## brace holds on the ground state only: the crouch, the air and the other states keep the aim on
## their own pelvis. It weighs the legs' stance under the aim too (`stance`, kit #1206).
class Driver:
	extends RefCounted
	## The brace on the model's skeleton now, or null: it is made the first time the character
	## aims, so a character that never aims (most of a crowd) carries no node for it.
	var modifier: AimBrace
	## The still legs under a standing aim: the ground state's idle point, held by the aim.
	var stance := AimStance.new()

	# How far the body is on the ground state's clips, whose stance the aim poses were made on.
	var _share := 1.0
	# Seconds the arm has left up after a shot, and how far the shot alone holds it up.
	var _shot_hold := 0.0
	var _shot_arm := 0.0

	## How far the arm is up (the aim the brace and the aim pose follow): the character's aim
	## amount, or the shot's own hold when that is more. After a shot it goes on rising for
	## `shot_hold_time` and then comes down at the speed of the aim (`aim_pose_time`).
	func arm(animation: CharacterAnimation, delta: float) -> float:
		var tuning := animation.character.tuning
		var aim_time := tuning.aim_pose_time if tuning != null else 0.15
		_shot_hold = maxf(_shot_hold - delta, 0.0)
		var target := 1.0 if _shot_hold > 0.0 else 0.0
		_shot_arm = move_toward(_shot_arm, target, delta / maxf(aim_time, 0.001))
		return maxf(animation.character.aim_amount, _shot_arm)

	## A shot: the arm stays up `shot_hold_time` from where it is now.
	func shot(animation: CharacterAnimation) -> void:
		_shot_hold = animation.shot_hold_time
		_shot_arm = maxf(_shot_arm, animation.character.aim_amount)

	## Frees the brace, so the next aim makes it again from the model, the bone and the aim clip
	## there are then; called whenever the tree is built.
	func build(_animation: CharacterAnimation) -> void:
		if is_instance_valid(modifier):
			# Out of the tree at once, so the new one can take the name.
			modifier.get_parent().remove_child(modifier)
			modifier.queue_free()
		modifier = null

	# Makes the brace on the skeleton of `animation`'s model, first of its modifiers (the hands
	# close on the weapon after it), from the held definition's aim clip.
	func _make(animation: CharacterAnimation) -> void:
		var hold := animation.held_definition()
		var model := animation.model
		var skeleton := model.skeleton() if is_instance_valid(model) else null
		var clips := animation.animation_player
		if skeleton == null or hold == null or hold.aim_clip == &"":
			return
		if not clips.has_animation(hold.aim_clip):
			return
		modifier = AimBrace.new()
		modifier.name = &"AimBrace"
		modifier.bone = animation.upper_body_bone
		modifier.stance = AimBrace.stance_of(
			skeleton,
			clips.get_animation(hold.aim_clip),
			animation.upper_body_bone,
			String(model.rig().get_path_to(skeleton))
		)
		modifier.influence = 0.0
		modifier.active = false
		skeleton.add_child(modifier)
		skeleton.move_child(modifier, 0)

	## Weighs the brace by `aim`, how much of the upper body the aim pose holds: on the ground
	## state only, the share following a change of state over the states' own blend time, and
	## not at all with `aim_brace` off.
	func drive(animation: CharacterAnimation, aim: float, delta: float) -> void:
		var standing := 1.0 if animation.body_state() == CharacterAnimation.GROUND else 0.0
		_share = move_toward(_share, standing, delta / maxf(animation.blend_time, 0.001))
		var weight := aim * _share if animation.aim_brace else 0.0
		stance.drive(animation.tree, aim, animation.aim_stance)
		if weight > 0.0 and not is_instance_valid(modifier):
			_make(animation)
		weigh(weight)

	## The brace's weight; written only when it changes, since the setters make the skeleton
	## work.
	func weigh(weight: float) -> void:
		if not is_instance_valid(modifier):
			return
		if not is_equal_approx(modifier.influence, weight):
			modifier.influence = weight
		if modifier.active != (weight > 0.0):
			modifier.active = weight > 0.0

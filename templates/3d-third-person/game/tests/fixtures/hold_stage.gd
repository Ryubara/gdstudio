class_name HoldStage
extends Node3D
## A mannequin holding the pistol the way the player's scene builds it (kit #1001), posed by hand:
## the model slot (`CharacterModel`) with a mannequin, `pistol_held.tscn` on its hand and the hold
## scene that closes the hands on it (`weapon_hold.tscn`, when the project has one), with no
## `Player` and no animation tree, so a test or a capture puts an exact frame of a clip on the
## skeleton and measures the hands on the weapon (`HandContact`) after the hold's modifiers ran.

const PISTOL_HELD := "res://assets/weapons/pistol/pistol_held.tscn"
const HOLD := "res://gameplay/weapon/hold/weapon_hold.tscn"
const MODELS: Dictionary[String, String] = {
	"female": "res://assets/characters/mannequin/mannequin_female.glb",
	"male": "res://assets/characters/mannequin/mannequin_male.glb",
}
const LIBRARIES: Dictionary[String, String] = {
	"ual1": "res://assets/animation/universal/ual1.glb",
	"ual2": "res://assets/animation/universal/ual2.glb",
}

## The parts that hold the weapon in each hand: none may be more than `HandContact.MAX_FLOAT` off
## it (the left hand lies over the right one, so its surfaces are the gun and the right hand).
const RIGHT_CONTACTS: Array[String] = [
	"index_tip",
	"middle_mid",
	"middle_tip",
	"ring_mid",
	"ring_tip",
	"pinky_mid",
	"pinky_tip",
	"thumb_tip",
	"palm",
]
const LEFT_CONTACTS: Array[String] = [
	"index_mid",
	"index_tip",
	"middle_mid",
	"middle_tip",
	"ring_mid",
	"ring_tip",
	"pinky_mid",
	"pinky_tip",
	"thumb_tip",
	"palm",
]

var slot: CharacterModel
var skeleton: Skeleton3D
var seat: BoneAttachment3D
var pistol: Node3D
## The hold scene's root, or null in a project that has none.
var hold: Node
var contact: HandContact

var _libraries := {}
var _updates := 0


## Builds the stage under `holder` (a node of a running tree) with the mannequin `model`
## (`female` or `male`); `with_hold` false leaves the hold scene out (the clips' own fist),
## `measured` false the contact measure (a bench that only plays the figures).
static func make(holder: Node, model: String, with_hold := true, measured := true) -> HoldStage:
	var stage := HoldStage.new()
	holder.add_child(stage)
	stage.slot = CharacterModel.new()
	stage.add_child(stage.slot)
	stage.slot.add_child((load(MODELS[model]) as PackedScene).instantiate())
	stage.seat = (load(PISTOL_HELD) as PackedScene).instantiate() as BoneAttachment3D
	stage.slot.add_child(stage.seat)
	stage.skeleton = stage.slot.skeleton()
	stage.seat.use_external_skeleton = true
	stage.seat.external_skeleton = stage.seat.get_path_to(stage.skeleton)
	stage.pistol = stage.seat.get_child(0) as Node3D
	if with_hold and ResourceLoader.exists(HOLD):
		stage.hold = (load(HOLD) as PackedScene).instantiate()
		stage.hold.set(&"model", stage.slot)
		stage.hold.set(&"seat", stage.seat)
		stage.add_child(stage.hold)
	if measured:
		stage.contact = HandContact.new(stage.skeleton)
		stage.contact.set_weapon(stage.pistol)
		stage.skeleton.skeleton_updated.connect(stage._on_skeleton_updated)
	return stage


## The clip `clip_name` (`ual1/Walk`) as an animation.
func clip(clip_name: StringName) -> Animation:
	var parts := String(clip_name).split("/")
	if not _libraries.has(parts[0]):
		_libraries[parts[0]] = load(LIBRARIES[parts[0]]) as AnimationLibrary
	return (_libraries[parts[0]] as AnimationLibrary).get_animation(parts[1])


## Puts `clip_name` at `time` on the skeleton, then `grip` at its start on each of `grip_bones` and
## every bone under it (the hand-only carry over a locomotion clip); `aim` is how far the hold is
## in its aim (0 carried, 1 aiming).
func pose(
	clip_name: StringName,
	time: float,
	aim := 0.0,
	grip: StringName = &"",
	grip_bones: Array[StringName] = []
) -> void:
	skeleton.reset_bone_poses()
	_apply(clip(clip_name), time, {})
	if grip != &"":
		var covered := {}
		for root in grip_bones:
			var start := skeleton.find_bone(root)
			for bone in skeleton.get_bone_count():
				var cursor := bone
				while cursor >= 0 and cursor != start:
					cursor = skeleton.get_bone_parent(cursor)
				if cursor >= 0:
					covered[bone] = true
		_apply(clip(grip), 0.0, covered)
	if hold != null:
		hold.set(&"aim_weight", aim)
		hold.call(&"refresh")
	_updates = 0


## Waits until the skeleton has run its modifiers on the pose and `contact` holds the result. A
## modifier that was just switched on (the arm's IK) takes a second update to act, so the pose is
## put again once.
func settle() -> void:
	while _updates < 1:
		await get_tree().process_frame
	skeleton.set_bone_pose_position(0, skeleton.get_bone_pose_position(0))
	while _updates < 2:
		await get_tree().process_frame


## Where a bone is in the world, in the pose `settle()` waited for.
func bone_origin(bone_name: StringName) -> Vector3:
	return skeleton.global_transform * contact.bone_pose(bone_name).origin


func _on_skeleton_updated() -> void:
	contact.snapshot()
	_updates += 1


func _apply(animation: Animation, time: float, only: Dictionary) -> void:
	for track in animation.get_track_count():
		var bone := skeleton.find_bone(
			String(animation.track_get_path(track).get_concatenated_subnames())
		)
		if bone < 0 or (not only.is_empty() and not only.has(bone)):
			continue
		match animation.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(
					bone, animation.rotation_track_interpolate(track, time)
				)
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(
					bone, animation.position_track_interpolate(track, time)
				)

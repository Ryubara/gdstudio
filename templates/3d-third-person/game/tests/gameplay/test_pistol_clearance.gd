# The pistol sits in the hand without sinking into the leg or the body in every clip the character
# carries it in, on both mannequins: the grip pose on the gripping hand over the locomotion clip,
# measured on the skinned body (`PistolClearance`), with no scene running.
extends GdUnitTestSuite

const MODELS := [
	CharacterBodies.FEMALE,
	CharacterBodies.MALE,
]
const CLIPS: Array[StringName] = [
	CharacterClips.IDLE,
	CharacterClips.WALK,
	CharacterClips.RUN,
	CharacterClips.SPRINT,
	CharacterClips.CROUCH_IDLE,
	CharacterClips.CROUCH_WALK,
	CharacterClips.JUMP_START,
	CharacterClips.AIR,
	CharacterClips.LAND,
	CharacterClips.PUSH,
]
const SAMPLES := 24
## How far a pistol point may be inside the body, in metres (none).
const TOLERANCE := 0.0


func _worst(model: String, bones: Array[StringName], grip_clip: StringName) -> Dictionary:
	var holder := Node3D.new()
	add_child(holder)
	var clearance := PistolClearance.new(holder, model)
	var grip := clearance.clip(grip_clip)
	var found := {}
	for clip_name in CLIPS:
		var animation := clearance.clip(clip_name)
		var worst := -1.0
		for step in SAMPLES:
			clearance.pose(animation, animation.length * step / SAMPLES, grip, bones)
			worst = maxf(worst, clearance.depth())
		found[clip_name] = worst
	clearance.free_rig()
	holder.free()
	return found


func test_the_pistol_stays_out_of_the_body_in_every_locomotion_clip_on_both_mannequins() -> void:
	var pistol := load("res://gameplay/weapon/pistol.tres") as WeaponDef
	var bones := pistol.grip_bones
	var grip_clip := pistol.grip_clip
	for model: String in MODELS:
		var worst := _worst(model, bones, grip_clip)
		for clip_name: StringName in worst:
			(
				assert_float(worst[clip_name])
				. override_failure_message("%s in %s" % [model.get_file(), clip_name])
				. is_less_equal(TOLERANCE)
			)


# The measure itself works: with the pistol seat moved into the torso, a point is found inside.
# The point is the middle of the torso in the pose (the spine's second bone), wherever the idle
# stands: a place fixed in the model's space was the library idle's torso, and our own idle
# stands 65 mm further forward (kit #1154).
func test_the_measure_finds_a_pistol_inside_the_body() -> void:
	var holder := Node3D.new()
	add_child(holder)
	var clearance := PistolClearance.new(holder, MODELS[0])
	for clip: StringName in [CharacterClips.IDLE, CharacterClips.stand_in(CharacterClips.IDLE)]:
		clearance.pose(clearance.clip(clip), 0.0)
		var skeleton := clearance.skeleton
		var torso := HandPoseModifier.global_pose(skeleton, skeleton.find_bone(&"spine_02")).origin
		assert_float(clearance.depth_at(torso)).override_failure_message(clip).is_greater(0.01)
		(
			assert_float(clearance.depth_at(torso + Vector3(0.0, 0.0, 0.6)))
			. override_failure_message(clip)
			. is_less(0.0)
		)
	clearance.free_rig()
	holder.free()

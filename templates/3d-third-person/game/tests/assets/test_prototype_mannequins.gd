# GDStudio's prototype mannequins (`assets/characters/prototype/`, kit #1149): nine bodies (a
# male, a female and a chibi in three looks) on one skeleton. Every body holds the Universal
# Animation Library's 65 bones with their rest rotations, so every library clip finds every bone;
# the import script sets the hips' scale, the twist modifier and the levels of detail; and the
# clips keep the feet on the floor and the limbs out of each other as they do on the Quaternius
# mannequins, which are measured beside them.
extends GdUnitTestSuite

const FOLDER := "res://assets/characters/prototype/"
const LOOKS: Array[String] = ["form", "joint", "facet"]
const BODIES: Array[String] = ["male", "female", "chibi"]
const REFERENCES: Array[String] = [
	"res://assets/characters/mannequin/mannequin_male.glb",
	"res://assets/characters/mannequin/mannequin_female.glb",
]
const LIBRARIES := {
	&"ual1": "res://assets/animation/universal/ual1.glb",
	&"ual2": "res://assets/animation/universal/ual2.glb",
}
const CLIPS: Array[StringName] = [
	&"ual1/Idle",
	&"ual1/Walk",
	&"ual1/Jog_Fwd",
	&"ual1/Sprint",
	&"ual1/Crouch_Fwd",
	&"ual1/Pistol_Aim_Neutral",
	&"ual1/Sitting_Idle",
	&"ual2/Slide",
]
## The hips height the libraries key (m), and each body's share of it.
const REFERENCE_HIPS := 0.916607
const MOTION_SCALE := {"male": 1.0, "female": 1.0, "chibi": 0.545}
## Triangles of each level of detail a body may have (the build's budget).
const BUDGET: Array[int] = [8000, 4000, 2200]
## How far under the reference mannequins' feet a body's feet may go in a clip (m): the shoes
## differ in shape, the legs do not.
const FEET_UNDER := 0.012
## How much deeper than on the reference mannequins two limbs may overlap (m). The chibi's short
## thick limbs rest a forearm 4 to 5 cm into a thigh where the adults' hands lie on it: a body
## that far from the reference needs the clips' contacts fixed by IK (the rig page says how).
const OVERLAP_OVER := {"male": 0.02, "female": 0.02, "chibi": 0.06}
const ADDED: Array[String] = [
	"upperarm_twist_01_l",
	"lowerarm_twist_01_l",
	"thigh_twist_01_l",
	"upperarm_twist_01_r",
	"lowerarm_twist_01_r",
	"thigh_twist_01_r",
	"socket_hand_r",
	"socket_hand_l",
	"socket_back",
	"socket_hip_l",
	"socket_hip_r",
	"socket_head",
	"socket_camera",
	"ik_foot_l",
	"ik_foot_r",
	"ik_hand_l",
	"ik_hand_r",
]


func _paths() -> Array[String]:
	var out: Array[String] = []
	for look in LOOKS:
		for body in BODIES:
			out.append("%s%s_%s.glb" % [FOLDER, look, body])
	return out


func _skeleton(path: String) -> Skeleton3D:
	var model: Node3D = auto_free((load(path) as PackedScene).instantiate())
	add_child(model)
	return model.find_children("*", "Skeleton3D", true, false)[0]


func test_every_body_holds_the_library_rig_and_the_seventeen_added_bones() -> void:
	var library := _skeleton(REFERENCES[0])
	for path in _paths():
		var skeleton := _skeleton(path)
		assert_int(skeleton.get_bone_count()).override_failure_message(path).is_equal(82)
		for bone in library.get_bone_count():
			var bone_name := library.get_bone_name(bone)
			var own := skeleton.find_bone(bone_name)
			(
				assert_int(own)
				. override_failure_message("%s: no %s" % [path, bone_name])
				. is_greater_equal(0)
			)
			var parent := library.get_bone_parent(bone)
			var own_parent := skeleton.get_bone_parent(own)
			assert_str(skeleton.get_bone_name(own_parent) if own_parent >= 0 else "").is_equal(
				library.get_bone_name(parent) if parent >= 0 else ""
			)
			var turn := (
				library.get_bone_rest(bone).basis.get_rotation_quaternion().inverse()
				* skeleton.get_bone_rest(own).basis.get_rotation_quaternion()
			)
			(
				assert_float(rad_to_deg(turn.get_angle()))
				. override_failure_message("%s: %s rests turned" % [path, bone_name])
				. is_less(0.05)
			)
		for bone_name in ADDED:
			(
				assert_int(skeleton.find_bone(bone_name))
				. override_failure_message("%s: no %s" % [path, bone_name])
				. is_greater_equal(0)
			)
		# The model's root and skeleton are named as the library's tracks address them.
		assert_str(String(skeleton.owner.get_path_to(skeleton))).is_equal("Armature/Skeleton3D")


func test_the_import_sets_the_hips_scale_the_twist_and_the_levels_of_detail() -> void:
	for path in _paths():
		var skeleton := _skeleton(path)
		var body: String = path.get_file().get_basename().split("_")[1]
		assert_float(skeleton.motion_scale).override_failure_message(path).is_equal_approx(
			MOTION_SCALE[body], 0.001
		)
		var hips := skeleton.get_bone_global_rest(skeleton.find_bone("pelvis")).origin.y
		assert_float(hips / REFERENCE_HIPS).is_equal_approx(skeleton.motion_scale, 0.0005)
		(
			assert_object(skeleton.get_node_or_null("MannequinTwist"))
			. override_failure_message(path)
			. is_not_null()
		)
		var begins: Array[float] = [0.0, 9.0, 22.0]
		for level in 3:
			var mesh: MeshInstance3D = skeleton.get_node("Body_LOD%d" % level)
			assert_float(mesh.visibility_range_begin).is_equal(begins[level])
			assert_float(mesh.visibility_range_end).is_equal(
				begins[level + 1] if level < 2 else 0.0
			)
			# No margins: a body that starts in the band between two levels would be drawn at neither.
			(
				assert_float(mesh.visibility_range_begin_margin + mesh.visibility_range_end_margin)
				. is_equal(0.0)
			)
			assert_int(mesh.mesh.get_surface_count()).is_equal(1)
			var indices: PackedInt32Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
			var triangles := indices.size() / 3
			(
				assert_int(triangles)
				. override_failure_message("%s LOD%d: %d triangles" % [path, level, triangles])
				. is_less_equal(BUDGET[level])
			)


func test_the_sockets_rest_on_the_models_axes_and_the_hand_sockets_on_the_weapons() -> void:
	for path in _paths():
		var skeleton := _skeleton(path)
		for socket: String in [
			"socket_back", "socket_hip_l", "socket_hip_r", "socket_head", "socket_camera"
		]:
			var basis := skeleton.get_bone_global_rest(skeleton.find_bone(socket)).basis
			(
				assert_bool(basis.is_equal_approx(Basis.IDENTITY))
				. override_failure_message("%s: %s" % [path, socket])
				. is_true()
			)
		# A kit weapon points its muzzle along -X with its top at +Y: in the T rest the right
		# hand's fingers point to the character's right (-X) and its thumb side forward (+Z).
		var right := skeleton.get_bone_global_rest(skeleton.find_bone("socket_hand_r")).basis
		assert_vector(-right.x).is_equal_approx(Vector3.LEFT, Vector3.ONE * 0.001)
		assert_vector(right.y).is_equal_approx(Vector3.BACK, Vector3.ONE * 0.001)
		var left := skeleton.get_bone_global_rest(skeleton.find_bone("socket_hand_l")).basis
		assert_vector(-left.x).is_equal_approx(Vector3.RIGHT, Vector3.ONE * 0.001)
		assert_vector(left.y).is_equal_approx(Vector3.BACK, Vector3.ONE * 0.001)
		# The IK targets rest on the limbs they stand for.
		for pair: Array in [["ik_foot_l", "foot_l"], ["ik_hand_r", "hand_r"]]:
			var target := skeleton.get_bone_global_rest(skeleton.find_bone(pair[0]))
			var limb := skeleton.get_bone_global_rest(skeleton.find_bone(pair[1]))
			(
				assert_bool(target.is_equal_approx(limb))
				. override_failure_message("%s: %s" % [path, pair[0]])
				. is_true()
			)


func test_every_clip_of_both_libraries_finds_every_bone_on_every_body() -> void:
	for path in _paths():
		var body := BodyMeasure.stage(self, path, LIBRARIES)
		var missing := PackedStringArray()
		for clip in body.player.get_animation_list():
			missing.append_array(body.missing_tracks(clip))
		assert_array(missing).override_failure_message("%s: %s" % [path, missing]).is_empty()
		body.free_nodes()


func test_the_clips_keep_the_feet_and_the_limbs_as_on_the_reference_mannequins() -> void:
	var feet := {}
	var overlap := {}
	for path in REFERENCES:
		var reference := BodyMeasure.stage(self, path, LIBRARIES)
		for clip in CLIPS:
			var row := reference.measure_clip(clip)
			feet[clip] = minf(feet.get(clip, 0.0), row["deepest"])
			overlap[clip] = maxf(overlap.get(clip, 0.0), row["overlap"])
		reference.free_nodes()
	for path in _paths():
		var name_parts := path.get_file().get_basename().split("_")
		var body := BodyMeasure.stage(self, path, LIBRARIES)
		var scale := body.skeleton.motion_scale
		for clip in CLIPS:
			var row := body.measure_clip(clip)
			var under: float = feet[clip] * scale - row["deepest"]
			(
				assert_float(under)
				. override_failure_message(
					"%s %s: feet %.1f mm under the reference's" % [path, clip, under * 1000.0]
				)
				. is_less(FEET_UNDER)
			)
			var over: float = row["overlap"] - overlap[clip]
			(
				assert_float(over)
				. override_failure_message(
					(
						"%s %s: %s overlap %.1f mm more than the reference"
						% [path, clip, row["pair"], over * 1000.0]
					)
				)
				. is_less(OVERLAP_OVER[name_parts[1]])
			)
		body.free_nodes()


func test_the_twist_bones_take_the_roll_of_the_hand_and_give_back_the_upper_arms() -> void:
	var skeleton := _skeleton(FOLDER + "form_male.glb")
	var twist: MannequinTwist = skeleton.get_node("MannequinTwist")
	var hand := skeleton.find_bone("hand_l")
	var forearm_twist := skeleton.find_bone("lowerarm_twist_01_l")
	var upperarm := skeleton.find_bone("upperarm_l")
	var shoulder_twist := skeleton.find_bone("upperarm_twist_01_l")
	# The hand rolls 80 degrees about the forearm's length (the forearm's Y) and bends 30.
	var roll := Quaternion(Vector3.UP, deg_to_rad(80.0))
	var bend := Quaternion(Vector3.RIGHT, deg_to_rad(30.0))
	skeleton.set_bone_pose_rotation(
		hand, roll * bend * skeleton.get_bone_rest(hand).basis.get_rotation_quaternion()
	)
	# The upper arm swings 40 degrees and rolls 60 about its own length.
	var swing := Quaternion(Vector3.FORWARD, deg_to_rad(40.0))
	var arm_roll := Quaternion(Vector3.UP, deg_to_rad(60.0))
	skeleton.set_bone_pose_rotation(
		upperarm,
		skeleton.get_bone_rest(upperarm).basis.get_rotation_quaternion() * swing * arm_roll
	)
	twist.apply(skeleton)
	var taken := skeleton.get_bone_pose_rotation(forearm_twist)
	assert_float(rad_to_deg(taken.get_angle())).is_equal_approx(80.0, 0.5)
	assert_float(absf(taken.get_axis().dot(Vector3.UP))).is_greater(0.999)
	# The shoulder end of the upper arm keeps the swing and loses the roll: its world turn is the
	# upper arm's with the 60 degrees taken back out.
	var back := skeleton.get_bone_pose_rotation(shoulder_twist)
	assert_float(rad_to_deg(back.get_angle())).is_equal_approx(60.0, 0.5)
	assert_bool((arm_roll * back).is_equal_approx(Quaternion.IDENTITY)).is_true()
	twist.rest(skeleton)
	(
		assert_bool(
			skeleton.get_bone_pose_rotation(forearm_twist).is_equal_approx(Quaternion.IDENTITY)
		)
		. is_true()
	)


func test_twist_about_y_splits_a_turn_into_its_roll() -> void:
	var roll := Quaternion(Vector3.UP, 1.1)
	var swing := Quaternion(Vector3(1, 0, 1).normalized(), 0.7)
	assert_bool(MannequinTwist.twist_about_y(swing * roll).is_equal_approx(roll)).is_true()
	(
		assert_bool(
			MannequinTwist.twist_about_y(Quaternion(Vector3.RIGHT, PI)).is_equal_approx(
				Quaternion.IDENTITY
			)
		)
		. is_true()
	)

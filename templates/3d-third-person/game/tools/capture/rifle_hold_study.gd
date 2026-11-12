## The rifle hold study (kit #886): five ways to hold `assets/weapons/rifle/rifle.glb` on the
## template's body with the clips the template has (the Universal Animation Library has pistol clips
## only), side by side, for the weapon work to choose from:
##
## - A: a pistol clip (`Pistol_Aim_Neutral`) with the rifle seated in the right fist the way the
##   pistol is (its `Grip` on the pistol's `Grip`);
## - B: A with a two-bone IK pulling the left hand to the rifle's `Support`;
## - C: shouldered: the rifle placed in the model's space with its `Butt` in the right shoulder's
##   pocket and the barrel along the facing, both hands brought to `Grip` and `Support` by IK,
##   the chest turned 30 degrees (left shoulder forward), over `Idle`;
## - D: C aimed 30 degrees up (the rifle turned about the pocket);
## - E: low ready: the butt in the pocket, the muzzle 35 degrees down and 20 across the body.
##
## Each hand's target is the right hand's place on the pistol's grip (the pistol's seat), moved
## onto the rifle's `Grip`, and mirrored onto its `Support` for the left hand (the rig is an
## exact mirror). Run headless, it prints one `HOLD` line a figure: how far each hand stopped
## from its target and the barrel's direction. Run with a window and `HOLD_OUT=<folder>`, it
## also saves the renders (a front, a left and a game-camera view of each figure):
## `HOLD_OUT=<abs folder> gds godot -- --path game --resolution 1200x900
## res://tools/capture/rifle_hold_study.tscn` (`MODEL=male` studies the template's male body,
## `MODEL=quaternius_female` or `quaternius_male` a Quaternius mannequin: `study_body.gd`).
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node3D

const STUDY_BODY := preload("res://tools/capture/study_body.gd")
const UAL1 := "res://assets/animation/universal/ual1.glb"
const RIFLE := "res://assets/weapons/rifle/rifle.glb"
const PISTOL := "res://assets/weapons/pistol/pistol.glb"
const SPINE_TURN := preload("res://tools/capture/spine_turn.gd")
## The pistol on `hand_r`: its seat (the first child's transform) gives the fist's place on a grip.
const PISTOL_HELD := "res://assets/weapons/pistol/pistol_held.tscn"
## The mirror across the model's YZ plane: the left bones' rests are the right ones' through it.
const MIRROR := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
## The rifle's axes in the model's space: muzzle (-X) along the facing (+Z), up up, left (+Z)
## to the model's left (+X).
const RIFLE_FORWARD := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
## Where the butt sits, in the model's space: the right shoulder's pocket, and the low ready's.
const POCKET := Vector3(-0.13, 1.39, 0.06)
const LOW_POCKET := Vector3(-0.12, 1.33, 0.06)
## Where each elbow points, in the model's space.
const POLE_RIGHT := Vector3(-0.6, -0.6, -0.4)
const POLE_LEFT := Vector3(0.6, -0.8, -0.2)
const FIGURES: Array[Dictionary] = [
	{"tag": "A", "name": "A pistol clip, rifle in hand", "clip": "Pistol_Aim_Neutral"},
	{"tag": "B", "name": "B pistol clip + left IK", "clip": "Pistol_Aim_Neutral", "left": true},
	{"tag": "C", "name": "C shouldered aim", "clip": "Idle", "place": "shoulder", "turn": -30.0},
	{
		"tag": "D",
		"name": "D aim up 30",
		"clip": "Idle",
		"place": "shoulder",
		"turn": -30.0,
		"pitch": 30.0,
	},
	{"tag": "E", "name": "E low ready", "clip": "Idle", "place": "low", "turn": -30.0},
]

var _figures: Array[Dictionary] = []


func _ready() -> void:
	var mannequin := STUDY_BODY.path()
	var held := (load(PISTOL_HELD) as PackedScene).instantiate()
	var pistol_seat := (held.get_child(0) as Node3D).transform
	held.free()
	var hand_in_grip := (pistol_seat * _socket(PISTOL, "Grip")).affine_inverse()
	var targets := {
		"seat": pistol_seat * _socket(PISTOL, "Grip") * _socket(RIFLE, "Grip").affine_inverse(),
		"right": _socket(RIFLE, "Grip") * hand_in_grip,
		"left": _socket(RIFLE, "Support") * _mirrored(hand_in_grip),
		"butt": _socket(RIFLE, "Butt").origin,
	}
	_stage()
	for i in FIGURES.size():
		_figures.append(_figure(FIGURES[i], mannequin, Vector3(-3.2 + 1.6 * i, 0, 0), targets))
	_report.call_deferred()


static func _mirrored(xf: Transform3D) -> Transform3D:
	return Transform3D(MIRROR * xf.basis * MIRROR, MIRROR * xf.origin)


# A socket's transform in the space of its file's root.
static func _socket(path: String, socket: String) -> Transform3D:
	var root: Node3D = (load(path) as PackedScene).instantiate()
	var node := root.find_child(socket, true, false) as Node3D
	var xf := node.transform
	var parent := node.get_parent()
	while parent != root:
		xf = (parent as Node3D).transform * xf
		parent = parent.get_parent()
	root.free()
	return xf


func _stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.36, 0.39, 0.44)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	ground.mesh = plane
	add_child(ground)


func _figure(spec: Dictionary, mannequin: String, at: Vector3, targets: Dictionary) -> Dictionary:
	var holder := Node3D.new()
	holder.name = spec.tag
	holder.position = at
	add_child(holder)
	var model: Node3D = (load(mannequin) as PackedScene).instantiate()
	holder.add_child(model)
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var player := AnimationPlayer.new()
	holder.add_child(player)
	player.root_node = player.get_path_to(model)
	player.add_animation_library(&"ual1", load(UAL1))
	player.play(StringName("ual1/" + spec.clip))
	player.seek(0.16 if spec.clip.begins_with("Pistol") else 0.5, true)
	player.pause()
	if spec.has("turn"):
		var turn := SPINE_TURN.new()
		turn.degrees = spec.turn
		skeleton.add_child(turn)
	var rifle: Node3D = (load(RIFLE) as PackedScene).instantiate()
	var place: String = spec.get("place", "hand")
	if place == "hand":
		var seat := BoneAttachment3D.new()
		seat.bone_name = "hand_r"
		skeleton.add_child(seat)
		seat.add_child(rifle)
		rifle.transform = targets.seat
	else:
		var frame := RIFLE_FORWARD
		var pocket := POCKET
		if place == "low":
			frame = Basis(Vector3.RIGHT, deg_to_rad(35)) * Basis(Vector3.UP, deg_to_rad(20)) * frame
			pocket = LOW_POCKET
		frame = Basis(Vector3.RIGHT, deg_to_rad(-spec.get("pitch", 0.0))) * frame
		model.add_child(rifle)
		rifle.transform = Transform3D(frame, pocket - frame * (targets.butt as Vector3))
		_arm(skeleton, "r", _target(rifle, "RightHandTarget", targets.right), POLE_RIGHT)
	if spec.get("left", place != "hand"):
		_arm(skeleton, "l", _target(rifle, "LeftHandTarget", targets.left), POLE_LEFT)
	var label := Label3D.new()
	label.text = spec.name
	label.font_size = 40
	label.pixel_size = 0.0025
	label.position = Vector3(0, 1.95, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	holder.add_child(label)
	return {"spec": spec, "skeleton": skeleton, "holder": holder, "rifle": rifle}


func _target(rifle: Node3D, target_name: String, xf: Transform3D) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = target_name
	rifle.add_child(marker)
	marker.transform = xf
	return marker


# A two-bone IK on one arm toward `target`, then the hand turned to the target's rotation; the
# elbow points at `pole`, in the model's space.
func _arm(skeleton: Skeleton3D, side: String, target: Node3D, pole: Vector3) -> void:
	var pole_node := Marker3D.new()
	pole_node.name = "Pole_" + side
	skeleton.get_parent().add_child(pole_node)
	pole_node.position = pole
	var ik := TwoBoneIK3D.new()
	ik.name = "ArmIK_" + side
	skeleton.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, "upperarm_" + side)
	ik.set_middle_bone_name(0, "lowerarm_" + side)
	ik.set_end_bone_name(0, "hand_" + side)
	ik.set_target_node(0, ik.get_path_to(target))
	ik.set_pole_node(0, ik.get_path_to(pole_node))
	var turn := CopyTransformModifier3D.new()
	turn.name = "HandTurn_" + side
	skeleton.add_child(turn)
	turn.setting_count = 1
	turn.set_apply_bone_name(0, "hand_" + side)
	turn.set_reference_type(0, BoneConstraint3D.REFERENCE_TYPE_NODE)
	turn.set_reference_node(0, turn.get_path_to(target))
	turn.set_copy_flags(0, CopyTransformModifier3D.TRANSFORM_FLAG_ROTATION)


# The final pose (after the modifiers) is readable only in `skeleton_updated`; a figure with no
# IK has no modifier that dirties the skeleton, so it never emits and is read on the next frame.
func _report() -> void:
	for _i in 10:
		await get_tree().process_frame
	for f: Dictionary in _figures:
		var skeleton: Skeleton3D = f.skeleton
		if skeleton.find_children("*", "IKModifier3D", false, false).is_empty():
			await get_tree().process_frame
		else:
			await skeleton.skeleton_updated
		print("HOLD ", _measure(f))
	var out := OS.get_environment("HOLD_OUT")
	if out.is_empty() or DisplayServer.get_name() == "headless":
		get_tree().quit()
		return
	await _shoot(out)
	get_tree().quit()


func _measure(f: Dictionary) -> String:
	var skeleton: Skeleton3D = f.skeleton
	var rifle: Node3D = f.rifle
	var line: String = f.spec.name
	for side in ["l", "r"]:
		var target_name := "LeftHandTarget" if side == "l" else "RightHandTarget"
		var target := rifle.find_child(target_name, false, false) as Node3D
		if target == null:
			continue
		var hand_bone := skeleton.find_bone("hand_" + side)
		var hand := skeleton.global_transform * skeleton.get_bone_global_pose(hand_bone)
		var shoulder_bone := skeleton.find_bone("upperarm_" + side)
		var shoulder := skeleton.global_transform * skeleton.get_bone_global_pose(shoulder_bone)
		var turn := hand.basis.get_rotation_quaternion().angle_to(
			target.global_basis.get_rotation_quaternion()
		)
		line += (
			" | %s: hand %.1f cm from target, %.0f deg, shoulder to target %.3f m"
			% [
				side,
				hand.origin.distance_to(target.global_position) * 100.0,
				rad_to_deg(turn),
				shoulder.origin.distance_to(target.global_position),
			]
		)
	var aim := -(rifle.find_child("Muzzle", true, false) as Node3D).global_basis.z
	line += (
		" | barrel %.0f deg up, %.0f deg to the left"
		% [rad_to_deg(asin(aim.y)), rad_to_deg(atan2(aim.x, aim.z))]
	)
	return line


# A front (from the figure's right), a left and a game-camera view of each figure, the others
# hidden. The game camera is the aim view (1.1 m behind the 1.55 m target, 0.5 m right, 50
# degrees), the low ready's the rest view (1.7 m, 62 degrees).
func _shoot(out: String) -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	for f: Dictionary in _figures:
		var at: Vector3 = (f.holder as Node3D).position
		var low: bool = f.spec.get("place", "") == "low"
		for other: Dictionary in _figures:
			(other.holder as Node3D).visible = other == f
		var game_eye := Vector3(-0.5, 1.55, -1.7 if low else -1.1)
		var shots := {
			"front": [Vector3(-1.5, 1.6, 1.8), Vector3(-0.1, 1.3, 0.3), 35.0],
			"left": [Vector3(2.3, 1.45, 0.35), Vector3(0, 1.3, 0.35), 35.0],
			"game": [game_eye, Vector3(-0.5, 1.55, 3.0), 62.0 if low else 50.0],
		}
		for shot: String in shots:
			cam.fov = shots[shot][2]
			cam.look_at_from_position(at + shots[shot][0], at + shots[shot][1])
			for _i in 4:
				await RenderingServer.frame_post_draw
			var path := out.path_join("hold_%s_%s.png" % [f.spec.tag, shot])
			get_viewport().get_texture().get_image().save_png(path)

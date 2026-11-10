@tool
class_name PlayerRagdoll
extends Node
## The character's ragdoll: physical bones on the skeleton of the model in the `Model` slot, limp
## while the `Player` is dead and idle (no collision, no cost) while it is alive.
##
## The bones are made from the skeleton each time the model changes, because a model swap deletes
## the old model and everything inside it. They are made in the editor too, so their shapes show
## in the viewport (with Visible Collision Shapes on in the Debug menu, or by selecting a bone in
## the remote tree), but they are never saved in a scene. `BODIES` lists them for the Quaternius
## universal rig (both mannequins).
##
## The `Player` calls `start()` when it dies and `stop()` when it gets up; the rest of the game
## listens to the player's `died` and `revived`.
##
## What makes it look like a body: every joint has the range of its human joint (hinges for the
## elbows and knees, cones for the rest; the death pose is pushed inside them at once), the
## bones collide with each other except with the one they hang from, each bone leaves with the
## velocity the animation gave it (so a death in the air goes on moving where the clip did) and
## the limbs are let drop for a third of a second. What it costs, and how it stays cheap on the
## web (a cap on how many lie limp at once, settling to sleep), is on the Ragdoll node's exports.

## The ragdoll took over the skeleton.
signal started
## The skeleton is the animation's again (the get-up blend finished).
signal stopped
## Every bone fell asleep after `settle_time` seconds: the body costs the physics engine nothing
## from here (Jolt; Godot Physics never puts a jointed body to sleep).
signal settled

## Each physical bone: `bone` is the skeleton bone it moves, `from` and `to` the bones (or, for
## `to`, a length along the bone, in metres) between which its capsule lies, `radius` the
## capsule's radius in metres and `share` its share of the body's mass in per cent (the
## Dempster/Winter segment masses). A body's frame has X along the bone and Z across it, toward
## `side` (in the skeleton's space, which holds a T-pose facing +Z) or else up or to the right.
##
## `joint` is how it hangs on the body above it: `&""` (the root, no joint); `&"cone"`, a ball
## joint that swings up to `swing` degrees from `centre` (a turn from the rest pose, Euler
## degrees, the pose a person stands in) and twists `twist` degrees either way around the bone;
## or `&"hinge"`, a knee or an elbow, that bends about `axis` (in the body's frame) through
## `range` (degrees, the lowest and the highest, from the straight limb) and does nothing else.
##
## The limits are a person's (the sources are in docs/engines/godot/ragdoll.md#limits), the same
## on the left and the right. A clip can hold a joint outside them; the pose is pushed inside
## when the body goes limp (`_clamped_world`), so no joint starts out of range and is thrown.
## `tools/ragdoll/measure_joints.gd` prints how far the clips go past them.
const BODIES := [
	{
		bone = &"pelvis",
		from = &"pelvis",
		to = &"spine_01",
		radius = 0.12,
		share = 14.2,
		joint = &""
	},
	{
		bone = &"spine_01",
		from = &"spine_01",
		to = &"spine_03",
		radius = 0.12,
		share = 13.9,
		joint = &"cone",
		centre = Vector3.ZERO,
		swing = 20.0,
		twist = 12.0
	},
	{
		bone = &"spine_03",
		from = &"spine_03",
		to = &"neck_01",
		radius = 0.13,
		share = 20.1,
		joint = &"cone",
		centre = Vector3(0.7, -0.1, 34.6),
		swing = 30.0,
		twist = 20.0
	},
	{
		bone = &"Head",
		from = &"neck_01",
		to = 0.26,
		radius = 0.1,
		share = 8.1,
		joint = &"cone",
		centre = Vector3(-0.9, -1.4, -14.7),
		swing = 45.0,
		twist = 60.0
	},
	{
		bone = &"upperarm_l",
		from = &"upperarm_l",
		to = &"lowerarm_l",
		radius = 0.05,
		share = 2.8,
		joint = &"cone",
		centre = Vector3(25.8, 33.6, -31.9),
		swing = 100.0,
		twist = 60.0
	},
	{
		bone = &"lowerarm_l",
		from = &"lowerarm_l",
		to = &"hand_l",
		radius = 0.045,
		share = 1.6,
		side = Vector3.DOWN,
		joint = &"hinge",
		axis = Vector3(0.0, 0.181, 0.983),
		range = Vector2(-5.0, 150.0)
	},
	{
		bone = &"hand_l",
		from = &"hand_l",
		to = 0.17,
		radius = 0.04,
		share = 0.6,
		joint = &"cone",
		centre = Vector3(-10.4, -4.4, -6.4),
		swing = 60.0,
		twist = 60.0
	},
	{
		bone = &"upperarm_r",
		from = &"upperarm_r",
		to = &"lowerarm_r",
		radius = 0.05,
		share = 2.8,
		joint = &"cone",
		centre = Vector3(-27.8, 39.8, 21.5),
		swing = 100.0,
		twist = 60.0
	},
	{
		bone = &"lowerarm_r",
		from = &"lowerarm_r",
		to = &"hand_r",
		radius = 0.045,
		share = 1.6,
		side = Vector3.UP,
		joint = &"hinge",
		axis = Vector3(0.0, -0.109, 0.994),
		range = Vector2(-5.0, 150.0)
	},
	{
		bone = &"hand_r",
		from = &"hand_r",
		to = 0.17,
		radius = 0.04,
		share = 0.6,
		joint = &"cone",
		centre = Vector3(17.6, -0.8, 10.6),
		swing = 60.0,
		twist = 60.0
	},
	{
		bone = &"thigh_l",
		from = &"thigh_l",
		to = &"calf_l",
		radius = 0.075,
		share = 10.0,
		joint = &"cone",
		centre = Vector3(-8.9, -20.4, -39.2),
		swing = 70.0,
		twist = 35.0
	},
	{
		bone = &"calf_l",
		from = &"calf_l",
		to = &"foot_l",
		radius = 0.06,
		share = 4.65,
		side = Vector3.RIGHT,
		joint = &"hinge",
		axis = Vector3(0.0, 0.12, 0.993),
		range = Vector2(-5.0, 140.0)
	},
	{
		bone = &"foot_l",
		from = &"foot_l",
		to = &"ball_leaf_l",
		radius = 0.045,
		share = 1.45,
		joint = &"cone",
		centre = Vector3(-0.8, -5.8, -9.7),
		swing = 35.0,
		twist = 15.0
	},
	{
		bone = &"thigh_r",
		from = &"thigh_r",
		to = &"calf_r",
		radius = 0.075,
		share = 10.0,
		joint = &"cone",
		centre = Vector3(6.7, 10.0, -22.5),
		swing = 70.0,
		twist = 35.0
	},
	{
		bone = &"calf_r",
		from = &"calf_r",
		to = &"foot_r",
		radius = 0.06,
		share = 4.65,
		side = Vector3.RIGHT,
		joint = &"hinge",
		axis = Vector3(0.0, -0.114, 0.994),
		range = Vector2(-5.0, 140.0)
	},
	{
		bone = &"foot_r",
		from = &"foot_r",
		to = &"ball_leaf_r",
		radius = 0.045,
		share = 1.45,
		joint = &"cone",
		centre = Vector3(1.2, -8.0, 14.8),
		swing = 35.0,
		twist = 15.0
	},
]

## The name of the node that holds the bones, under the skeleton.
const SIMULATOR := &"RagdollBones"

## The limbs pulled down by `relax_gravity`, and how much of it each takes (the ends of a limb
## most, its root half).
const RELAXED := {
	&"upperarm_l": 0.5,
	&"upperarm_r": 0.5,
	&"lowerarm_l": 1.0,
	&"lowerarm_r": 1.0,
	&"hand_l": 1.0,
	&"hand_r": 1.0,
	&"thigh_l": 0.5,
	&"thigh_r": 0.5,
	&"calf_l": 1.0,
	&"calf_r": 1.0,
	&"foot_l": 1.0,
	&"foot_r": 1.0,
	&"Head": 0.6,
}

## A pose that moved faster than this between two ticks was a jump of the character, not a motion.
const MAX_POSE_SPEED := 40.0

## Ragdolls limp now, in the whole game (what `max_active` caps).
static var _counted := 0

@export_group("Nodes")
## The slot that holds the character's model; the bones go on its skeleton.
@export var model: PlayerModel:
	set(value):
		if model != null and model.rig_changed.is_connected(_on_rig_changed):
			model.rig_changed.disconnect(_on_rig_changed)
		model = value
		if model != null and is_inside_tree():
			model.rig_changed.connect(_on_rig_changed)
		_rebuild()

@export_group("Body")
## The weight of the whole body, shared out between the bones by their size.
@export_range(5.0, 300.0, 0.5, "suffix:kg") var mass := 70.0:
	set(value):
		mass = value
		_apply_materials()
## How thick the bones' capsules are: 1 fits the mannequins, more for a heavier model.
@export_range(0.25, 3.0, 0.01) var thickness := 1.0:
	set(value):
		thickness = value
		_rebuild()
## How far the joints let the limbs swing, as a share of a person's range: under 1 is stiffer,
## over 1 floppier.
@export_range(0.1, 2.0, 0.01) var joint_range := 1.0:
	set(value):
		joint_range = value
		_rebuild()
## How many times the physics solver holds each elbow and knee in its range per step: 1 is the
## joint alone, more keeps a straight or bent limb from giving way when the body lands on it (an
## elbow folded 30 degrees past its range, or bent 50 backwards, in 10 deaths of 70 with 1). Each
## one past the first is another hinge between the same two bones, solved only while limp.
@export_range(1, 8, 1) var hinge_passes := 4:
	set(value):
		hinge_passes = value
		_rebuild()
## The same for every cone (shoulders, hips, spine, neck, wrists, ankles): with 1 a shoulder the
## body lands on twists 50 to 115 degrees past its range, and a hip or a wrist 30 to 70 past.
@export_range(1, 8, 1) var cone_passes := 4:
	set(value):
		cone_passes = value
		_rebuild()
## How much the bones slow down moving through the air (0 keeps their speed).
@export_range(0.0, 10.0, 0.01) var linear_damp := 0.1:
	set(value):
		linear_damp = value
		_apply_materials()
## How fast the limbs stop turning: low flails, high settles quickly.
@export_range(0.0, 20.0, 0.01) var angular_damp := 2.0:
	set(value):
		angular_damp = value
		_apply_materials()
## How much the bones grip the ground (0 slides like ice).
@export_range(0.0, 1.0, 0.01) var friction := 0.8:
	set(value):
		friction = value
		_apply_materials()
## How much the bones bounce off the ground.
@export_range(0.0, 1.0, 0.01) var bounce := 0.0:
	set(value):
		bounce = value
		_apply_materials()

@export_group("Death and getting up")
## The share of the velocity (the character's, or with `pose_velocity` each bone's own, spin
## included) the body keeps when it goes limp: 1 keeps a run's momentum, 0 drops on the spot.
@export_range(0.0, 2.0, 0.01) var carry_velocity := 1.0
## Every bone leaves with the velocity the animation gave it over the last physics tick (a limb
## swinging in a stride goes on swinging), not all with the character's. Off: one velocity for
## the whole body, and no per-tick cost while alive.
@export var pose_velocity := true
## How hard the limbs are pulled down (m/s squared, on top of gravity) for `relax_time` after the
## death, so a body that dies in the air goes limp there: a body in free fall with every bone
## at one velocity keeps its pose until it lands. 0 turns it off.
@export_range(0.0, 40.0, 0.1, "suffix:m/s²") var relax_gravity := 12.0
## Seconds the limbs are pulled down after the death.
@export_range(0.0, 1.0, 0.01, "suffix:s") var relax_time := 0.35
## Seconds the pose takes to blend from lying to the animation when the character gets up.
@export_range(0.0, 2.0, 0.01, "suffix:s") var get_up_time := 0.4

@export_group("Cost")
## How many ragdolls may lie limp at once in the whole game (one that has settled, or got up,
## stops counting); a death over the cap is not a ragdoll (`can_start()` is false, the `Player`
## plays its death clip). 0: no cap.
@export_range(0, 32, 1) var max_active := 4
## Seconds after which a body whose bones are all asleep is `settled` (the signal, `is_settled()`),
## and stops counting toward `max_active`. A game with many bodies lying about frees them there.
@export_range(1.0, 60.0, 0.5, "suffix:s") var settle_time := 8.0
## A death farther than this from the camera (metres) is not a ragdoll but the death clip: nobody
## sees the difference and the physics is saved. 0: any distance.
@export_range(0.0, 200.0, 1.0, "suffix:m") var ragdoll_range := 0.0

@export_group("Collision")
## The physics layers the bones are on while limp. Their own layer by default (5), so nothing that
## looks for the level or the characters (the camera's walls, a door, a shot, the player's own
## ground probes) finds them. Adding layer 1 here makes all of those see the bones.
@export_flags_3d_physics var collision_layer := 16:
	set(value):
		collision_layer = value
		_apply_materials()
## The layers the bones fall onto and collide with: the level (1) and their own (5), so the limbs
## rest on the body and on each other (never on the bone they hang from, which is excepted).
## Take the own layer out and the limbs pass through each other.
@export_flags_3d_physics var collision_mask := 17:
	set(value):
		collision_mask = value
		_apply_materials()

var _simulator: PhysicalBoneSimulator3D
var _bones: Dictionary[StringName, PhysicalBone3D] = {}
var _blend := 0.0
var _limp := false
var _ignored: Array[CollisionObject3D] = []
# Where each body is in the skeleton's space when its joint is made: the neutral pose.
var _posed: Dictionary[StringName, Transform3D] = {}
# Where each body was in the animated pose, this physics tick and the one before.
var _pose_now: Dictionary[StringName, Transform3D] = {}
var _pose_before: Dictionary[StringName, Transform3D] = {}
var _since_start := 0.0
var _counts := false
var _settled := false
# The extra joints beside each bone's own (`hinge_passes`, `cone_passes`).
var _braces := RagdollBraces.new()


func _ready() -> void:
	if model != null and not model.rig_changed.is_connected(_on_rig_changed):
		model.rig_changed.connect(_on_rig_changed)
	_build()


func _notification(what: int) -> void:
	# The bones live under the skeleton, not under this node: take them away with it.
	if what == NOTIFICATION_PREDELETE:
		_clear()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _simulator == null:
		return
	if _limp:
		_while_limp(delta)
	elif _blend <= 0.0 and pose_velocity:
		_sample_pose()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _simulator == null or _limp or _blend <= 0.0:
		return
	_blend = maxf(_blend - delta / maxf(get_up_time, 0.001), 0.0)
	_simulator.influence = _blend
	if _blend <= 0.0:
		_end()


## True while the bones hold the skeleton (limp, or blending back to the animation).
func is_active() -> bool:
	return _simulator != null and _simulator.is_simulating_physics()


## True while the body is limp (from `start()` to `stop()`).
func is_limp() -> bool:
	return _limp


## The physical bone that moves `bone` (`&"pelvis"`, `&"Head"`, ...), or null.
func body(bone: StringName) -> PhysicalBone3D:
	return _bones.get(bone)


## How many physical bones the skeleton has now.
func body_count() -> int:
	return _bones.size()


## The bones never collide with `other` (the player's own capsule, a vehicle it sits in).
func add_collision_exception(other: CollisionObject3D) -> void:
	if other != null and not _ignored.has(other):
		_ignored.append(other)


## True when a death may be a ragdoll now: there are bones, fewer than `max_active` lie limp and
## the camera is not past `ragdoll_range`. When it is false the character plays its death clip.
func can_start() -> bool:
	if _simulator == null:
		return false
	if max_active > 0 and _counted >= max_active and not _counts:
		return false
	if ragdoll_range > 0.0 and not Engine.is_editor_hint() and is_inside_tree():
		var camera := get_viewport().get_camera_3d()
		var hip := hips()
		if camera != null and camera.global_position.distance_to(hip) > ragdoll_range:
			return false
	return true


## The ragdoll takes over from the pose on screen: each bone leaves with the velocity the
## animation gave it (or, with `pose_velocity` off, all with `velocity`), times `carry_velocity`.
## Returns false, and does nothing, when `can_start()` is false.
func start(velocity: Vector3 = Vector3.ZERO) -> bool:
	if not can_start():
		return false
	var clamped := _clamped_world()
	if _simulator.is_simulating_physics():
		_simulator.physical_bones_stop_simulation()
	_simulator.influence = 1.0
	_simulator.active = true
	_simulator.physical_bones_start_simulation()
	for ignored in _ignored:
		if is_instance_valid(ignored):
			_simulator.physical_bones_add_collision_exception(ignored.get_rid())
	var from_pose := pose_velocity and _pose_ready()
	for key: StringName in _bones:
		var bone: PhysicalBone3D = _bones[key]
		# The animated pose, pushed inside the joints' limits.
		if clamped.has(key):
			bone.global_transform = clamped[key]
		bone.linear_velocity = velocity * carry_velocity
		bone.angular_velocity = Vector3.ZERO
		if from_pose:
			_give_pose_velocity(key, bone)
	_limp = true
	_blend = 1.0
	_since_start = 0.0
	_settled = false
	_count(true)
	started.emit()
	return true


## The body stops being limp: the animation takes the skeleton back over `get_up_time` (at once
## with `blend` false, or with no get-up time).
func stop(blend: bool = true) -> void:
	if not _limp:
		return
	_limp = false
	_count(false)
	_pose_now.clear()
	_pose_before.clear()
	if blend and get_up_time > 0.0:
		_blend = 1.0
	else:
		_end()


## Where the hips lie, in world space (the pelvis bone's body).
func hips() -> Vector3:
	var pelvis := body(&"pelvis")
	return pelvis.global_position if pelvis != null else Vector3.ZERO


## The way the ragdoll's chest faces, flat on the ground (a unit vector), or, lying face up or
## face down, the way its head points: the way a person getting up would face.
func facing() -> Vector3:
	var chest := body(&"spine_03")
	var pelvis := body(&"pelvis")
	if chest == null or pelvis == null or model == null or model.skeleton() == null:
		return Vector3.BACK
	var skeleton := model.skeleton()
	# The chest's forward now: the model's forward (+Z) turned the way the chest body turned from
	# its rest place.
	var rest := skeleton.global_basis * rest_body(&"spine_03").basis
	var forward := chest.global_basis * rest.inverse() * (skeleton.global_basis * Vector3.BACK)
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length() > 0.35:
		return flat.normalized()
	var along := chest.global_position - pelvis.global_position
	along.y = 0.0
	if along.length_squared() < 0.0001:
		return Vector3.BACK
	return along.normalized()


func _end() -> void:
	_blend = 0.0
	_count(false)
	if _simulator == null:
		return
	_simulator.physical_bones_stop_simulation()
	_simulator.active = false
	_simulator.influence = 1.0
	stopped.emit()


func _on_rig_changed(_rig: Node3D) -> void:
	_rebuild()


func _rebuild() -> void:
	if is_node_ready():
		_build()


# Takes the bones off the old skeleton (or this one) and makes them again on the model's skeleton.
func _build() -> void:
	var was_limp := _limp
	# A change made while the body lies limp keeps it lying where it is.
	var lying: Dictionary[StringName, Transform3D] = {}
	if was_limp:
		for bone_name: StringName in _bones:
			lying[bone_name] = _bones[bone_name].global_transform
	_clear()
	var skeleton := model.skeleton() if model != null else null
	if skeleton == null or not skeleton.is_inside_tree():
		return
	for entry: Dictionary in BODIES:
		if skeleton.find_bone(entry.bone) < 0 or skeleton.find_bone(entry.from) < 0:
			return
	_simulator = PhysicalBoneSimulator3D.new()
	_simulator.name = SIMULATOR
	_simulator.active = false
	skeleton.add_child(_simulator)
	# The extra joints are server joints between the bones' bodies: they go before the bodies do
	# (a model swap deletes the skeleton and the bones with it), and come back with them.
	_simulator.tree_exiting.connect(_free_braces)
	_simulator.tree_entered.connect(_brace_joints)
	var rest_bodies: Dictionary[StringName, Transform3D] = {}
	for entry: Dictionary in BODIES:
		var bone := _make_bone(skeleton, entry)
		_simulator.add_child(bone)
		_bones[entry.bone] = bone
		rest_bodies[entry.bone] = rest_body(entry.bone)
	# The engine (4.7.2) sets a joint up when its type is set, from where the two bodies are then
	# and the joint's offset; setting the offset later only moves the body back onto its bone. So:
	# every offset first, then every body posed at its joint's centre (a cone's `centre`, the
	# middle of a bend's ranges: a limit that is the same each way never wraps past half a turn,
	# where the engine would read it as the other limit), then the types. The limits are then the
	# measured ones, whatever the animation shows.
	for entry: Dictionary in BODIES:
		_bones[entry.bone].joint_offset = Transform3D(_joint_frame(entry), Vector3.ZERO)
	var posed := _posed
	for entry: Dictionary in BODIES:
		var place: Transform3D = rest_bodies[entry.bone]
		var parent := _parent_body(skeleton, entry.bone)
		if parent != &"":
			# The engine puts the joint on the bone's own origin.
			var pivot := Transform3D(Basis.IDENTITY, _bones[entry.bone].joint_offset.origin)
			var centre := _centre(entry)
			place = (
				posed[parent]
				* rest_bodies[parent].affine_inverse()
				* rest_bodies[entry.bone]
				* pivot
				* Transform3D(centre, Vector3.ZERO)
				* pivot.affine_inverse()
			)
		posed[entry.bone] = place
		_bones[entry.bone].global_transform = skeleton.global_transform * place
	for entry: Dictionary in BODIES:
		_set_joint(_bones[entry.bone], entry)
	_apply_materials()
	_except_parents()
	_brace_joints()
	if was_limp and not Engine.is_editor_hint():
		start()
		for bone_name: StringName in lying:
			if _bones.has(bone_name):
				_bones[bone_name].global_transform = lying[bone_name]


func _clear() -> void:
	_free_braces()
	_count(false)
	_posed.clear()
	_pose_now.clear()
	_pose_before.clear()
	if _simulator != null and is_instance_valid(_simulator):
		if _simulator.is_inside_tree() and _simulator.is_simulating_physics():
			_simulator.physical_bones_stop_simulation()
		_simulator.get_parent().remove_child(_simulator)
		_simulator.free()
	_simulator = null
	_bones.clear()
	_limp = false
	_blend = 0.0


## Where the body of `bone_name` is in the rest pose, in the skeleton's space: its X axis along
## the bone (the twist axis of a cone joint), its Z axis on the bend axis (a hinge's axis), its
## middle halfway along its capsule.
func rest_body(bone_name: StringName) -> Transform3D:
	var entry := _entry(bone_name)
	var skeleton := model.skeleton()
	var head := skeleton.get_bone_global_rest(skeleton.find_bone(entry.from)).origin
	var tail := _tail(skeleton, entry)
	var along := (tail - head).normalized()
	var side: Vector3 = entry.get("side", Vector3.UP if absf(along.y) < 0.7 else Vector3.RIGHT)
	side = (side - along * side.dot(along)).normalized()
	var basis := Basis(along, side.cross(along), side)
	return Transform3D(basis, (head + tail) / 2.0)


func _tail(skeleton: Skeleton3D, entry: Dictionary) -> Vector3:
	if entry.to is float:
		var rest := skeleton.get_bone_global_rest(skeleton.find_bone(entry.bone))
		return rest.origin + rest.basis.y.normalized() * float(entry.to)
	return skeleton.get_bone_global_rest(skeleton.find_bone(entry.to)).origin


func _entry(bone_name: StringName) -> Dictionary:
	for entry: Dictionary in BODIES:
		if entry.bone == bone_name:
			return entry
	return {}


func _make_bone(skeleton: Skeleton3D, entry: Dictionary) -> PhysicalBone3D:
	var bone := PhysicalBone3D.new()
	bone.name = String(entry.bone)
	bone.bone_name = entry.bone
	var rest_bone := skeleton.get_bone_global_rest(skeleton.find_bone(entry.bone))
	var body_rest := rest_body(entry.bone)
	bone.body_offset = rest_bone.affine_inverse() * body_rest
	var length := (
		(
			_tail(skeleton, entry)
			- skeleton.get_bone_global_rest(skeleton.find_bone(entry.from)).origin
		)
		. length()
	)
	var radius: float = entry.radius * thickness
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = maxf(length + radius, radius * 2.0 + 0.01)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = capsule
	# A capsule stands on its Y axis; lay it along the body's X axis, the bone.
	shape.basis = Basis(Vector3.BACK, -PI / 2.0)
	bone.add_child(shape)
	return bone


# The joint's frame in the body's: the body's own (X along the bone: a cone's twist axis), or for a
# hinge, Z on its bend axis and X along the bone.
func _joint_frame(entry: Dictionary) -> Basis:
	if entry.joint != &"hinge":
		return Basis.IDENTITY
	return hinge_frame(entry.axis)


## The frame of a knee or an elbow in its body's frame: Z on `axis` (the bend, what a hinge turns
## about) and X along the bone (the body's X, made square to the axis), where its angle is zero.
static func hinge_frame(axis: Vector3) -> Basis:
	var bend := axis.normalized()
	var along := (Vector3.RIGHT - bend * bend.dot(Vector3.RIGHT)).normalized()
	return Basis(along, bend.cross(along), bend)


func _set_joint(bone: PhysicalBone3D, entry: Dictionary) -> void:
	match entry.joint:
		&"cone":
			bone.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			bone.set(&"joint_constraints/swing_span", minf(entry.swing * joint_range, 175.0))
			bone.set(&"joint_constraints/twist_span", minf(entry.twist * joint_range, 175.0))
		&"hinge":
			# The joint is made at the middle of its range, so the limits are the same each way.
			bone.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
			var half := minf((entry.range.y - entry.range.x) / 2.0 * joint_range, 170.0)
			bone.set(&"joint_constraints/angular_limit_enabled", true)
			bone.set(&"joint_constraints/angular_limit_upper", half)
			bone.set(&"joint_constraints/angular_limit_lower", -half)
		_:
			bone.joint_type = PhysicalBone3D.JOINT_TYPE_NONE


# The turn from the rest pose (in the body's frame) at which a joint is made: a cone's `centre`,
# or the middle of a hinge's range (turned about the hinge axis).
func _centre(entry: Dictionary) -> Basis:
	if entry.joint == &"cone":
		return Basis.from_euler(_degrees(entry.centre))
	if entry.joint != &"hinge":
		return Basis.IDENTITY
	var frame := _joint_frame(entry)
	var middle: float = (entry.range.x + entry.range.y) / 2.0
	return frame * Basis(Vector3.BACK, deg_to_rad(middle)) * frame.inverse()


## A turn read as a twist about X and then a swing about Y and Z of what is left, in degrees (the
## way Jolt reads a 6DOF joint). `tools/ragdoll/measure_joints.gd` reads the clips with it.
static func swing_twist(turn: Basis) -> Vector3:
	var q := Quaternion(turn)
	if q.w < 0.0:
		q = -q
	var twist := Quaternion(q.x, 0.0, 0.0, q.w).normalized()
	var swing := q * twist.inverse()
	return (
		Vector3(
			2.0 * atan2(twist.x, twist.w),
			2.0 * atan2(swing.y, swing.w),
			2.0 * atan2(swing.z, swing.w)
		)
		* (180.0 / PI)
	)


# The nearest bone above `bone` in the skeleton that has a body, or empty for the root.
func _parent_body(skeleton: Skeleton3D, bone: StringName) -> StringName:
	var index := skeleton.get_bone_parent(skeleton.find_bone(bone))
	while index >= 0:
		var found := StringName(skeleton.get_bone_name(index))
		if _bones.has(found):
			return found
		index = skeleton.get_bone_parent(index)
	return &""


func _degrees(euler: Vector3) -> Vector3:
	return euler * (PI / 180.0)


func _apply_materials() -> void:
	if _bones.is_empty():
		return
	var total := 0.0
	for entry: Dictionary in BODIES:
		total += float(entry.share)
	for entry: Dictionary in BODIES:
		var bone: PhysicalBone3D = _bones[entry.bone]
		bone.mass = maxf(mass * float(entry.share) / total, 0.05)
		bone.linear_damp = linear_damp
		bone.angular_damp = angular_damp
		bone.friction = friction
		bone.bounce = bounce
		bone.collision_layer = collision_layer
		bone.collision_mask = collision_mask


# The extra joints (`hinge_passes`, `cone_passes`): Jolt's project-wide solver steps are too few
# for a light limb under a falling trunk, so each joint is made again between the same bones
# (`RagdollBraces`, docs/engines/godot/ragdoll.md#limits).
func _brace_joints() -> void:
	var skeleton := model.skeleton() if model != null else null
	if skeleton == null or not _braces.is_empty() or _posed.is_empty():
		return
	var parents: Dictionary[StringName, StringName] = {}
	for key: StringName in _bones:
		parents[key] = _parent_body(skeleton, key)
	_braces.build(_bones, _posed, parents, hinge_passes, cone_passes, joint_range)


func _free_braces() -> void:
	_braces.free_all()


## How many hinges hold the elbows and knees now, the bones' own and the extra ones.
func hinge_count() -> int:
	var own := 0
	for entry: Dictionary in BODIES:
		if entry.joint == &"hinge" and _bones.has(entry.bone):
			own += 1
	return own + _braces.hinges


## How many cones hold the shoulders, hips, spine, neck, wrists and ankles now, the bones' own and
## the extra ones.
func cone_count() -> int:
	var own := 0
	for entry: Dictionary in BODIES:
		if entry.joint == &"cone" and _bones.has(entry.bone):
			own += 1
	return own + _braces.cones


# Godot 4.7.2 gives a `PhysicalBone3D` no exception for the bone it hangs from (godot PR 70945 is
# open), and their capsules overlap at the joint: without this they push each other apart for ever.
func _except_parents() -> void:
	var skeleton := model.skeleton() if model != null else null
	if skeleton == null:
		return
	for key: StringName in _bones:
		var up := _parent_body(skeleton, key)
		if up == &"":
			continue
		var below := _bones[key].get_rid()
		var above := _bones[up].get_rid()
		PhysicsServer3D.body_add_collision_exception(below, above)
		PhysicsServer3D.body_add_collision_exception(above, below)


# --- the animated pose: its velocity and its place inside the limits ---


func _pose_ready() -> bool:
	return not _pose_before.is_empty() and _pose_now.size() == _pose_before.size()


# Where every body is in the pose the animation has now, in world space.
func _sample_pose() -> void:
	var skeleton := model.skeleton() if model != null else null
	if skeleton == null or not skeleton.is_inside_tree():
		return
	_pose_before = _pose_now
	_pose_now = {}
	for key: StringName in _bones:
		_pose_now[key] = _animated_body(skeleton, key)


func _animated_body(skeleton: Skeleton3D, key: StringName) -> Transform3D:
	return (
		skeleton.global_transform
		* skeleton.get_bone_global_pose(skeleton.find_bone(key))
		* _bones[key].body_offset
	)


# The velocity of the body over the last tick: a bone's own motion plus the character's. Past 40
# m/s the sample is a teleport, not a motion, and the character's velocity stays.
func _give_pose_velocity(key: StringName, bone: PhysicalBone3D) -> void:
	var step := 1.0 / maxf(float(Engine.physics_ticks_per_second), 1.0)
	var now: Transform3D = _pose_now[key]
	var before: Transform3D = _pose_before[key]
	var linear := (now.origin - before.origin) / step
	if linear.length() > MAX_POSE_SPEED:
		return
	bone.linear_velocity = linear * carry_velocity
	var turn := Quaternion(now.basis.orthonormalized() * before.basis.orthonormalized().inverse())
	if turn.w < 0.0:
		turn = -turn
	if turn.get_angle() > 0.00001:
		bone.angular_velocity = turn.get_axis() * (turn.get_angle() / step) * carry_velocity


# The animated pose with every joint turned inside its limits, as world transforms, chained from
# the pelvis: what the bodies are put at when the character goes limp.
func _clamped_world() -> Dictionary:
	var skeleton := model.skeleton() if model != null else null
	var placed := {}
	if skeleton == null or _posed.is_empty():
		return placed
	for entry: Dictionary in BODIES:
		var key: StringName = entry.bone
		var animated := _animated_body(skeleton, key)
		var parent := _parent_body(skeleton, key)
		if parent == &"":
			placed[key] = animated
			continue
		var parent_animated := _animated_body(skeleton, parent)
		var creation: Transform3D = _posed[parent].affine_inverse() * _posed[key]
		var frame := _joint_frame(entry)
		# The turn from the pose the joint was made in, in the joint's frame.
		var delta := creation.basis.inverse() * (parent_animated.affine_inverse() * animated).basis
		var turn := inside_limits(entry, frame.inverse() * delta * frame)
		var pivot := Transform3D(Basis.IDENTITY, _bones[key].joint_offset.origin)
		var about := Transform3D(frame * turn * frame.inverse(), Vector3.ZERO)
		var relative := creation * pivot * about * pivot.affine_inverse()
		placed[key] = (placed[parent] as Transform3D) * relative
	return placed


## `turn` (a turn from the pose a joint was made in, in its frame) held inside the joint's limits:
## a cone's swing and twist cut to their spans, a hinge's turn kept to its axis and its range.
func inside_limits(entry: Dictionary, turn: Basis) -> Basis:
	var q := Quaternion(turn).normalized()
	if q.w < 0.0:
		q = -q
	match entry.joint:
		&"cone":
			var twist := Quaternion(q.x, 0.0, 0.0, q.w)
			twist = twist.normalized() if twist.length() > 0.0001 else Quaternion.IDENTITY
			var swing := q * twist.inverse()
			var twist_angle := 2.0 * atan2(twist.x, twist.w)
			var most := deg_to_rad(entry.twist * joint_range)
			twist_angle = clampf(twist_angle, -most, most)
			var widest := deg_to_rad(entry.swing * joint_range)
			if swing.get_angle() > widest:
				swing = Quaternion(swing.get_axis(), widest)
			return Basis(swing * Quaternion(Vector3.RIGHT, twist_angle))
		&"hinge":
			var half := deg_to_rad((entry.range.y - entry.range.x) / 2.0 * joint_range)
			return Basis(Vector3.BACK, clampf(2.0 * atan2(q.z, q.w), -half, half))
	return turn


# --- while limp ---


func _while_limp(delta: float) -> void:
	_since_start += delta
	if _since_start <= relax_time and relax_gravity > 0.0:
		for key: StringName in RELAXED:
			var bone: PhysicalBone3D = _bones[key]
			bone.apply_central_impulse(
				Vector3.DOWN * bone.mass * relax_gravity * float(RELAXED[key]) * delta
			)
	if not _settled and _since_start >= settle_time and _all_asleep():
		_settled = true
		_count(false)
		settled.emit()


func _all_asleep() -> bool:
	for bone: PhysicalBone3D in _bones.values():
		if not PhysicsServer3D.body_get_state(bone.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING):
			return false
	return true


## True when every bone fell asleep `settle_time` seconds after the death (Jolt).
func is_settled() -> bool:
	return _settled


# Keeps `_counted` right: this ragdoll counts toward `max_active` from `start()` until it stops,
# settles or is taken away.
func _count(on: bool) -> void:
	if on and not _counts:
		_counts = true
		_counted += 1
	elif not on and _counts:
		_counts = false
		_counted -= 1


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if model == null:
		warnings.append("Set `model` to the PlayerModel that holds the character.")
	elif model.skeleton() != null and _bones.is_empty():
		warnings.append("The model's skeleton lacks the universal rig's bones the ragdoll needs.")
	return warnings

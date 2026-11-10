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

## The ragdoll took over the skeleton.
signal started
## The skeleton is the animation's again (the get-up blend finished).
signal stopped

## Each physical bone: `bone` is the skeleton bone it moves, `from` and `to` the bones (or, for
## `to`, a length along the bone, in metres) between which its capsule lies, and `radius` the
## capsule's radius in metres. A body's frame has X along the bone and Z across it, toward `side`
## (in the skeleton's space, which holds a T-pose facing +Z) or else up or to the right.
##
## `joint` is how it hangs on the body above it: `&""` (the root, no joint); `&"cone"`, a ball
## joint that swings up to `swing` degrees from `centre` (a turn from the rest pose, Euler degrees)
## and twists `twist` degrees either way around the bone; or `&"bend"`, a knee or an elbow, that
## bends about `axis` (in the body's frame) through `bend`, rolls about the bone through `twist`
## and leans sideways through `side_swing` (each a range in degrees, the lowest and the highest,
## read by `swing_twist()` in `bend_frame()`, the way the joint reads them).
##
## The limits hold every pose of the player's clips, on both mannequins, with 10 degrees to spare:
## a body that died in a pose outside its limits would be snapped back and could be thrown.
## `tools/ragdoll/measure_joints.gd` measures them; run it again after changing a clip or a frame.
const BODIES := [
	{bone = &"pelvis", from = &"pelvis", to = &"spine_01", radius = 0.12, joint = &""},
	{
		bone = &"spine_01",
		from = &"spine_01",
		to = &"spine_03",
		radius = 0.12,
		joint = &"cone",
		centre = Vector3.ZERO,
		swing = 20.0,
		twist = 15.0
	},
	{
		bone = &"spine_03",
		from = &"spine_03",
		to = &"neck_01",
		radius = 0.13,
		joint = &"cone",
		centre = Vector3(0.7, -0.1, 34.6),
		swing = 74.0,
		twist = 48.0
	},
	{
		bone = &"Head",
		from = &"neck_01",
		to = 0.26,
		radius = 0.1,
		joint = &"cone",
		centre = Vector3(-0.9, -1.4, -14.7),
		swing = 42.0,
		twist = 52.0
	},
	{
		bone = &"upperarm_l",
		from = &"upperarm_l",
		to = &"lowerarm_l",
		radius = 0.05,
		joint = &"cone",
		centre = Vector3(25.8, 33.6, -31.9),
		swing = 125.0,
		twist = 53.0
	},
	{
		bone = &"lowerarm_l",
		from = &"lowerarm_l",
		to = &"hand_l",
		radius = 0.045,
		side = Vector3.DOWN,
		joint = &"bend",
		axis = Vector3(0.0, 0.181, 0.983),
		bend = Vector2(-7.0, 145.0),
		twist = Vector2(-84.0, 33.0),
		side_swing = Vector2(-34.0, 20.0)
	},
	{
		bone = &"hand_l",
		from = &"hand_l",
		to = 0.17,
		radius = 0.04,
		joint = &"cone",
		centre = Vector3(-10.4, -4.4, -6.4),
		swing = 85.0,
		twist = 80.0
	},
	{
		bone = &"upperarm_r",
		from = &"upperarm_r",
		to = &"lowerarm_r",
		radius = 0.05,
		joint = &"cone",
		centre = Vector3(-27.8, 39.8, 21.5),
		swing = 133.0,
		twist = 65.0
	},
	{
		bone = &"lowerarm_r",
		from = &"lowerarm_r",
		to = &"hand_r",
		radius = 0.045,
		side = Vector3.UP,
		joint = &"bend",
		axis = Vector3(0.0, -0.109, 0.994),
		bend = Vector2(-7.0, 145.0),
		twist = Vector2(-59.0, 97.0),
		side_swing = Vector2(-14.0, 49.0)
	},
	{
		bone = &"hand_r",
		from = &"hand_r",
		to = 0.17,
		radius = 0.04,
		joint = &"cone",
		centre = Vector3(17.6, -0.8, 10.6),
		swing = 93.0,
		twist = 31.0
	},
	{
		bone = &"thigh_l",
		from = &"thigh_l",
		to = &"calf_l",
		radius = 0.075,
		joint = &"cone",
		centre = Vector3(-8.9, -20.4, -39.2),
		swing = 91.0,
		twist = 27.0
	},
	{
		bone = &"calf_l",
		from = &"calf_l",
		to = &"foot_l",
		radius = 0.06,
		side = Vector3.RIGHT,
		joint = &"bend",
		axis = Vector3(0.0, 0.12, 0.993),
		bend = Vector2(-9.0, 145.0),
		twist = Vector2(-50.0, 23.0),
		side_swing = Vector2(-17.0, 10.0)
	},
	{
		bone = &"foot_l",
		from = &"foot_l",
		to = &"ball_leaf_l",
		radius = 0.045,
		joint = &"cone",
		centre = Vector3(-0.8, -5.8, -9.7),
		swing = 63.0,
		twist = 28.0
	},
	{
		bone = &"thigh_r",
		from = &"thigh_r",
		to = &"calf_r",
		radius = 0.075,
		joint = &"cone",
		centre = Vector3(6.7, 10.0, -22.5),
		swing = 110.0,
		twist = 21.0
	},
	{
		bone = &"calf_r",
		from = &"calf_r",
		to = &"foot_r",
		radius = 0.06,
		side = Vector3.RIGHT,
		joint = &"bend",
		axis = Vector3(0.0, -0.114, 0.994),
		bend = Vector2(-9.0, 145.0),
		twist = Vector2(-24.0, 53.0),
		side_swing = Vector2(-13.0, 17.0)
	},
	{
		bone = &"foot_r",
		from = &"foot_r",
		to = &"ball_leaf_r",
		radius = 0.045,
		joint = &"cone",
		centre = Vector3(1.2, -8.0, 14.8),
		swing = 66.0,
		twist = 29.0
	},
]

## The name of the node that holds the bones, under the skeleton.
const SIMULATOR := &"RagdollBones"

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
## The share of the character's velocity the body keeps when it goes limp: 1 keeps a run's
## momentum, 0 drops on the spot.
@export_range(0.0, 2.0, 0.01) var carry_velocity := 1.0
## Seconds the pose takes to blend from lying to the animation when the character gets up.
@export_range(0.0, 2.0, 0.01, "suffix:s") var get_up_time := 0.4

@export_group("Collision")
## The physics layers the bones are on while limp. Their own layer by default, so nothing that
## looks for the level or the characters (the camera's walls, a door, a shot) finds them.
@export_flags_3d_physics var collision_layer := 16:
	set(value):
		collision_layer = value
		_apply_materials()
## The layers the bones fall onto and collide with: the level by default. Leave their own layer
## out, so the bones never fight each other.
@export_flags_3d_physics var collision_mask := 1:
	set(value):
		collision_mask = value
		_apply_materials()

var _simulator: PhysicalBoneSimulator3D
var _bones: Dictionary[StringName, PhysicalBone3D] = {}
var _blend := 0.0
var _limp := false
var _ignored: Array[CollisionObject3D] = []


func _ready() -> void:
	if model != null and not model.rig_changed.is_connected(_on_rig_changed):
		model.rig_changed.connect(_on_rig_changed)
	_build()


func _notification(what: int) -> void:
	# The bones live under the skeleton, not under this node: take them away with it.
	if what == NOTIFICATION_PREDELETE:
		_clear()


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


## The ragdoll takes over from the pose on screen, every bone moving at `velocity` times
## `carry_velocity`.
func start(velocity: Vector3 = Vector3.ZERO) -> void:
	if _simulator == null:
		return
	if _simulator.is_simulating_physics():
		_simulator.physical_bones_stop_simulation()
	_simulator.influence = 1.0
	_simulator.active = true
	_simulator.physical_bones_start_simulation()
	for ignored in _ignored:
		if is_instance_valid(ignored):
			_simulator.physical_bones_add_collision_exception(ignored.get_rid())
	for bone: PhysicalBone3D in _bones.values():
		bone.linear_velocity = velocity * carry_velocity
		bone.angular_velocity = Vector3.ZERO
	_limp = true
	_blend = 1.0
	started.emit()


## The body stops being limp: the animation takes the skeleton back over `get_up_time` (at once
## with `blend` false, or with no get-up time).
func stop(blend: bool = true) -> void:
	if not _limp:
		return
	_limp = false
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
	var posed: Dictionary[StringName, Transform3D] = {}
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
	if was_limp and not Engine.is_editor_hint():
		start()
		for bone_name: StringName in lying:
			if _bones.has(bone_name):
				_bones[bone_name].global_transform = lying[bone_name]


func _clear() -> void:
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
	bone.set_meta(&"volume", PI * radius * radius * (capsule.height - radius * 2.0 / 3.0))
	return bone


# The joint's frame in the body's: the body's own (X along the bone: a cone's twist axis), or for a
# bend, X on its bend axis and Y along the bone. The joint reads a turn as a twist about X and then
# a swing about Y and Z, and only the twist stays exact through a large angle, so the bend is the
# twist; the bone's roll (about Y) and the sideways lean (about Z) are small.
func _joint_frame(entry: Dictionary) -> Basis:
	if entry.joint != &"bend":
		return Basis.IDENTITY
	return bend_frame(entry.axis)


## The frame of a knee or an elbow in its body's frame: X on `axis` (the bend), Y along the bone
## (the body's X, made square to the axis), Z across both.
static func bend_frame(axis: Vector3) -> Basis:
	var bend := axis.normalized()
	var along := (Vector3.RIGHT - bend * bend.dot(Vector3.RIGHT)).normalized()
	return Basis(bend, along, bend.cross(along))


func _set_joint(bone: PhysicalBone3D, entry: Dictionary) -> void:
	match entry.joint:
		&"cone":
			bone.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			bone.set(&"joint_constraints/swing_span", minf(entry.swing * joint_range, 175.0))
			bone.set(&"joint_constraints/twist_span", minf(entry.twist * joint_range, 175.0))
		&"bend":
			bone.joint_type = PhysicalBone3D.JOINT_TYPE_6DOF
			_limit(bone, "x", entry.bend)
			_limit(bone, "y", entry.twist)
			_limit(bone, "z", entry.side_swing)
		_:
			bone.joint_type = PhysicalBone3D.JOINT_TYPE_NONE


# One axis of a 6DOF joint turns through `range_degrees` (a turn of the body below about the axis,
# the lowest and the highest), measured from the middle of the range, where the joint was set up.
func _limit(bone: PhysicalBone3D, axis: String, range_degrees: Vector2) -> void:
	var half := minf((range_degrees.y - range_degrees.x) / 2.0 * joint_range, 170.0)
	bone.set("joint_constraints/%s/angular_limit_enabled" % axis, true)
	bone.set("joint_constraints/%s/angular_limit_lower" % axis, -half)
	bone.set("joint_constraints/%s/angular_limit_upper" % axis, half)


# The turn from the rest pose (in the body's frame) at which a joint is set up: a cone's `centre`,
# or the middle of a bend's three ranges (Euler XYZ in the joint's frame, the way it reads them).
func _centre(entry: Dictionary) -> Basis:
	if entry.joint == &"cone":
		return Basis.from_euler(_degrees(entry.centre))
	if entry.joint != &"bend":
		return Basis.IDENTITY
	var middle := Vector3(
		(entry.bend.x + entry.bend.y) / 2.0,
		(entry.twist.x + entry.twist.y) / 2.0,
		(entry.side_swing.x + entry.side_swing.y) / 2.0
	)
	var frame := _joint_frame(entry)
	return frame * from_swing_twist(middle) * frame.inverse()


## A turn read the way a 6DOF joint (Jolt) reads it, in degrees: `x` the twist about X, then `y`
## and `z` the swing about Y and Z of what is left. The knees' and elbows' ranges are in these
## terms.
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


## The turn of `swing_twist()`'s angles (degrees).
static func from_swing_twist(angles: Vector3) -> Basis:
	var half := angles * (PI / 360.0)
	var twist := Quaternion(sin(half.x), 0.0, 0.0, cos(half.x))
	var swing := Quaternion(0.0, tan(half.y), tan(half.z), 1.0).normalized()
	return Basis(swing * twist)


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
	for bone: PhysicalBone3D in _bones.values():
		total += float(bone.get_meta(&"volume"))
	for bone: PhysicalBone3D in _bones.values():
		bone.mass = maxf(mass * float(bone.get_meta(&"volume")) / total, 0.05)
		bone.linear_damp = linear_damp
		bone.angular_damp = angular_damp
		bone.friction = friction
		bone.bounce = bounce
		bone.collision_layer = collision_layer
		bone.collision_mask = collision_mask


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if model == null:
		warnings.append("Set `model` to the PlayerModel that holds the character.")
	elif model.skeleton() != null and _bones.is_empty():
		warnings.append("The model's skeleton lacks the universal rig's bones the ragdoll needs.")
	return warnings

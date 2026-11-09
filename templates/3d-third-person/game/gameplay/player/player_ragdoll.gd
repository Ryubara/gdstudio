@tool
class_name PlayerRagdoll
extends Node
## The character's physical bones. It builds a `PhysicalBoneSimulator3D` with a `PhysicalBone3D`
## for the pelvis, the torso, the head, the arms and the legs (`RagdollLayout`) under the skeleton
## of the model in the `PlayerModel` slot, and a `RagdollBlend` beside it.
##
## Alive, the bones are not simulated and have no collision: the animation drives the skeleton as
## it always did. `start()` takes the pose the animation left and hands it to the simulator, and
## `stop()` hands it back, with the pose the ragdoll was in held so that `RagdollBlend` can fade
## it into the animation over `PlayerTuning.ragdoll_get_up_time`.
##
## The bones are generated, from the skeleton, and never saved in a scene: a model that is swapped
## in (the other mannequin, or any model on the same rig) gets its own bones, built when
## `PlayerModel.rig_changed` says it arrived, and the player scene holds only this node. In the
## editor they are built too, so the gizmos show the shapes and the joints, and taken off while
## the scene is saved.

## The bones were built again (the model changed, or the tuning asked for it).
signal rebuilt

## The player whose tuning sets the bones' mass, damping, joints and collision.
@export var player: Player
## The slot that holds the model; the bones are built on the skeleton it finds.
@export var model: PlayerModel

var _skeleton: Skeleton3D
var _simulator: PhysicalBoneSimulator3D
var _blend: RagdollBlend
var _bodies: Dictionary[StringName, PhysicalBone3D] = {}
var _flex: Dictionary[StringName, float] = {}
var _active := false
var _fade := 0.0


func _ready() -> void:
	if player == null or model == null:
		return
	model.rig_changed.connect(_on_rig_changed)
	if player.tuning != null:
		player.tuning.changed.connect(apply_tuning)
	rebuild()


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	# Nothing generated is saved into a scene: the bones come off while it is written.
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_clear()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		rebuild()


func _physics_process(delta: float) -> void:
	if _blend == null or not _blend.is_blending() or player == null or player.tuning == null:
		return
	_fade += delta
	var time := maxf(player.tuning.ragdoll_get_up_time, 0.001)
	_blend.weight = 1.0 - smoothstep(0.0, 1.0, clampf(_fade / time, 0.0, 1.0))
	if _fade >= time:
		_blend.release()


## True while the simulator drives the skeleton.
func is_simulating() -> bool:
	return _active


## True while the pose of the ragdoll is still fading into the animation.
func is_blending() -> bool:
	return _blend != null and _blend.is_blending()


## The physical bone of `bone` (`&"pelvis"`), or null.
func body(bone: StringName) -> PhysicalBone3D:
	return _bodies.get(bone)


## How many physical bones there are.
func body_count() -> int:
	return _bodies.size()


## The `PhysicalBoneSimulator3D`, or null while there is no model.
func simulator() -> PhysicalBoneSimulator3D:
	return _simulator


## Where the middle of the body is now (the pelvis), in world space. Before the bones exist, the
## player's place.
func pelvis_position() -> Vector3:
	var pelvis := body(RagdollLayout.PELVIS)
	if pelvis != null and pelvis.is_inside_tree():
		return pelvis.global_position
	return player.global_position if player != null else Vector3.ZERO


## Builds the bones again from the skeleton of the model, in the pose the skeleton is in at the
## rest: the joints' limits are measured from the pose the bones are made in.
func rebuild() -> void:
	_clear()
	_skeleton = model.skeleton() if model != null else null
	if _skeleton == null or not _skeleton.is_inside_tree():
		return
	_skeleton.reset_bone_poses()
	_simulator = PhysicalBoneSimulator3D.new()
	_simulator.name = &"PhysicalBones"
	_skeleton.add_child(_simulator)
	_blend = RagdollBlend.new()
	_blend.name = &"RagdollBlend"
	_skeleton.add_child(_blend)
	for entry in RagdollLayout.BONES:
		var bone := _make_bone(entry)
		if bone != null:
			_simulator.add_child(bone)
			_bodies[entry[&"bone"]] = bone
	if player != null:
		_simulator.physical_bones_add_collision_exception(player.get_rid())
	apply_tuning()
	if Engine.is_editor_hint():
		_show_in_editor()
	rebuilt.emit()
	if _active_before_rebuild():
		start(Vector3.ZERO)


## Puts the tuning on every bone: mass, damping, friction, bounce, how far the joints bend, and
## which layers the bones are on and hit. Called when the tuning changes.
func apply_tuning() -> void:
	if player == null or player.tuning == null:
		return
	var tuning := player.tuning
	var shares := RagdollLayout.total_mass()
	for entry in RagdollLayout.BONES:
		var bone: PhysicalBone3D = _bodies.get(entry[&"bone"])
		if bone == null:
			continue
		bone.mass = maxf(tuning.ragdoll_mass * entry[&"mass"] / shares, 0.01)
		bone.linear_damp = tuning.ragdoll_linear_damp
		bone.angular_damp = tuning.ragdoll_angular_damp
		bone.friction = tuning.ragdoll_friction
		bone.bounce = tuning.ragdoll_bounce
		_limit_joint(bone, entry, tuning.ragdoll_joint_freedom)
		_set_collision(bone, _active)


## Hands the skeleton to the simulator, from the pose it is in. `carried` is the velocity every
## bone starts with (the body's run), in m/s.
func start(carried: Vector3) -> void:
	if _simulator == null or Engine.is_editor_hint():
		return
	_blend.release()
	_pose_joints()
	_active = true
	for bone in _bodies.values():
		_set_collision(bone, true)
	_simulator.physical_bones_start_simulation()
	for bone in _bodies.values():
		bone.linear_velocity = carried


## The world transform of every bone, as the skeleton shows them now (a ragdoll lying on the
## floor, if it is). Empty before there is a model.
func snapshot() -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	if _skeleton == null:
		return poses
	for bone in _skeleton.get_bone_count():
		poses.append(_skeleton.global_transform * _skeleton.get_bone_global_pose(bone))
	return poses


## Takes the skeleton back from the simulator and fades `held` (a `snapshot()` from before) into
## the animation over the tuning's get-up time. The bones stop colliding.
func stop(held: Array[Transform3D]) -> void:
	if _simulator == null:
		return
	_active = false
	_simulator.physical_bones_stop_simulation()
	_flex.clear()
	for bone in _bodies.values():
		_set_collision(bone, false)
	if not held.is_empty():
		_blend.hold(held)
		_fade = 0.0


## The way the ragdoll faces, as a heading (radians about the up axis, 0 faces +Z), read from
## the pose `held` (a `snapshot()`): the chest's front when it is turned toward the side, and
## when the body lies on its back or its front, the way its head and feet lie.
func heading(held: Array[Transform3D]) -> float:
	if _skeleton == null or held.size() != _skeleton.get_bone_count():
		return NAN
	var chest := _skeleton.find_bone(RagdollLayout.CHEST)
	var pelvis := _skeleton.find_bone(RagdollLayout.PELVIS)
	var head := _skeleton.find_bone(RagdollLayout.HEAD)
	if chest < 0 or pelvis < 0 or head < 0:
		return NAN
	var rest := _skeleton.get_bone_global_rest(chest).basis
	var front := held[chest].basis * (rest.inverse() * Vector3.BACK)
	var along := held[head].origin - held[pelvis].origin
	var flat := Vector3(front.x, 0.0, front.z)
	if flat.length() < 0.35:
		# Lying on the back (the front looks up): it gets up facing the feet. On the front: the
		# head.
		flat = Vector3(along.x, 0.0, along.z)
		if front.y > 0.0:
			flat = -flat
	if flat.length_squared() < 0.0001:
		return NAN
	return atan2(flat.x, flat.z)


# Whether the ragdoll was simulating when the bones were thrown away (a model swapped during it).
func _active_before_rebuild() -> bool:
	return _active and not Engine.is_editor_hint()


func _clear() -> void:
	for node in [_simulator, _blend]:
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
	_simulator = null
	_blend = null
	_bodies.clear()


func _on_rig_changed(_rig: Node3D) -> void:
	# The old skeleton is going away, and its bones with it.
	if _rig == null:
		_clear()
		return
	rebuild.call_deferred()


# Builds the body of one entry of the layout on the skeleton, or null when the skeleton has not
# the bone.
func _make_bone(entry: Dictionary) -> PhysicalBone3D:
	var index := _skeleton.find_bone(entry[&"bone"])
	if index < 0:
		return null
	var rest := _skeleton.get_bone_global_rest(index)
	var bone := PhysicalBone3D.new()
	bone.name = entry[&"bone"]
	bone.bone_name = String(entry[&"bone"])
	var collider := CollisionShape3D.new()
	collider.name = &"Shape"
	collider.shape = _shape_for(entry)
	collider.transform = _shape_place(entry, rest)
	bone.add_child(collider)
	_set_joint(bone, entry)
	return bone


func _shape_for(entry: Dictionary) -> Shape3D:
	match entry[&"shape"]:
		&"box":
			var box := BoxShape3D.new()
			box.size = entry[&"size"]
			return box
		&"sphere":
			var sphere := SphereShape3D.new()
			sphere.radius = entry[&"radius"]
			return sphere
	var length := _reach(entry).length()
	var capsule := CapsuleShape3D.new()
	capsule.radius = minf(entry[&"radius"], length / 2.0 - 0.001)
	capsule.height = length
	return capsule


# Where the shape sits in the body's own space (the bone's rest frame): boxes and spheres by the
# offset in the table, a capsule between the bone and the bone it runs to.
func _shape_place(entry: Dictionary, rest: Transform3D) -> Transform3D:
	var to_local := rest.basis.inverse()
	if entry[&"shape"] != &"capsule":
		return Transform3D(Basis(to_local), to_local * entry[&"offset"])
	var reach := _reach(entry)
	var tilt := Basis(Quaternion(Vector3.UP, reach.normalized()))
	return Transform3D(Basis(to_local) * tilt, to_local * (reach / 2.0))


# The vector from the bone to the end of its limb, in the rest pose.
func _reach(entry: Dictionary) -> Vector3:
	var end := _skeleton.find_bone(entry.get(&"end", &""))
	if end >= 0:
		return _skeleton.get_bone_global_rest(end).origin - rest.origin
	return Vector3.UP * entry.get(&"reach", 0.2)


# The joint's type; its frame is set in the pose the body dies in (`_pose_joints`).
func _set_joint(bone: PhysicalBone3D, entry: Dictionary) -> void:
	match entry[&"joint"]:
		&"hinge":
			bone.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
		&"cone":
			bone.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
		_:
			bone.joint_type = PhysicalBone3D.JOINT_TYPE_NONE


# Joints are made in the pose the skeleton is in, because a joint measures its limits from the
# pose it was made in: a body that dies running has its elbows bent already, and limits taken
# from the T-pose of the model file would be broken the moment it started. A cone swings and
# twists by its limits from where the limb is. A hinge turns about an axis fixed in the bone
# above it (a knee turns about the thigh's side axis, however the shin is twisted), within its
# limits counted from the model's straight limb, shifted by how bent the limb is now.
func _pose_joints() -> void:
	for entry in RagdollLayout.BONES:
		var bone: PhysicalBone3D = _bodies.get(entry[&"bone"])
		if bone == null or entry[&"joint"] == &"none":
			continue
		var index := _skeleton.find_bone(entry[&"bone"])
		var pose := _skeleton.get_bone_global_pose(index)
		var rest := _skeleton.get_bone_global_rest(index)
		var axis: Vector3 = entry[&"axis"]
		var frame: Basis
		_flex[entry[&"bone"]] = 0.0
		if entry[&"joint"] == &"hinge":
			var above := _body_above(index)
			var carried := (
				_skeleton.get_bone_global_pose(above).basis
				* _skeleton.get_bone_global_rest(above).basis.inverse()
			)
			axis = (carried * axis).normalized()
			frame = _frame_z(axis)
			_flex[entry[&"bone"]] = _bend(entry, index, carried, axis)
		else:
			axis = (pose.basis * rest.basis.inverse() * axis).normalized()
			frame = _frame_x(axis)
		bone.joint_offset = Transform3D(pose.basis.inverse() * frame, Vector3.ZERO)
		# Setting the offset does not make the joint again, and a joint measures from the
		# bodies' places when it is made: turn the type off and on.
		var kind: PhysicalBone3D.JointType = bone.joint_type
		bone.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		bone.joint_type = kind
	apply_tuning()


# How far the limb of the bone `index` is bent now about `axis`, in degrees: the angle from the
# straight limb (carried along by the bone above) to where its end is.
func _bend(entry: Dictionary, index: int, carried: Basis, axis: Vector3) -> float:
	var end := _skeleton.find_bone(entry.get(&"end", &""))
	if end < 0:
		return 0.0
	var straight := (
		carried
		* (
			_skeleton.get_bone_global_rest(end).origin
			- _skeleton.get_bone_global_rest(index).origin
		)
	)
	var now := (
		_skeleton.get_bone_global_pose(end).origin - _skeleton.get_bone_global_pose(index).origin
	)
	straight -= axis * straight.dot(axis)
	now -= axis * now.dot(axis)
	if straight.length_squared() < 0.0001 or now.length_squared() < 0.0001:
		return 0.0
	return rad_to_deg(straight.signed_angle_to(now, axis))


# The nearest bone above `index` that has a physical bone (the one the joint holds on to).
func _body_above(index: int) -> int:
	var above := _skeleton.get_bone_parent(index)
	while above >= 0 and not _bodies.has(_skeleton.get_bone_name(above)):
		above = _skeleton.get_bone_parent(above)
	return above


# A frame whose X is `axis` (a cone twists about its frame's X).
func _frame_x(axis: Vector3) -> Basis:
	var side := axis.cross(_across(axis)).normalized()
	return Basis(axis, side, axis.cross(side).normalized())


# A frame whose Z is `axis` (a hinge turns about its frame's Z).
func _frame_z(axis: Vector3) -> Basis:
	var side := axis.cross(_across(axis)).normalized()
	return Basis(side, axis.cross(side).normalized(), axis)


func _across(axis: Vector3) -> Vector3:
	return Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.UP


func _limit_joint(bone: PhysicalBone3D, entry: Dictionary, freedom: float) -> void:
	match entry[&"joint"]:
		&"cone":
			bone.set(&"joint_constraints/swing_span", entry[&"swing"] * freedom)
			bone.set(&"joint_constraints/twist_span", entry[&"twist"] * freedom)
		&"hinge":
			var bend: float = _flex.get(entry[&"bone"], 0.0)
			var lower := minf(entry[&"lower"] * freedom, bend)
			var upper := maxf(entry[&"upper"] * freedom, bend)
			bone.set(&"joint_constraints/angular_limit_enabled", true)
			bone.set(&"joint_constraints/angular_limit_lower", lower - bend)
			bone.set(&"joint_constraints/angular_limit_upper", upper - bend)


func _set_collision(bone: PhysicalBone3D, on: bool) -> void:
	if player == null or player.tuning == null:
		return
	bone.collision_layer = player.tuning.ragdoll_collision_layer if on else 0
	bone.collision_mask = player.tuning.ragdoll_collision_mask if on else 0


# In the editor the bones get an owner, so the viewport draws their shapes and joints. The owner
# is the scene being edited; they come off again before it is saved.
func _show_in_editor() -> void:
	var root := get_tree().edited_scene_root if is_inside_tree() else null
	if root == null:
		return
	for bone in _bodies.values():
		bone.owner = root
		for child in bone.get_children():
			child.owner = root

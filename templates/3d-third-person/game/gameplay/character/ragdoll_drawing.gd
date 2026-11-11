class_name RagdollDrawing
extends SkeletonModifier3D
## Draws a ragdoll's skin where its bodies are drawn: between the last two physics ticks, like
## every other moving thing on screen. The `PhysicalBoneSimulator3D` puts each bone where its
## body was at the last tick, and the skin follows the bones, so with physics interpolation on
## (the camera, the pusher and the bodies themselves are drawn between ticks) a body moving at
## 144 frames a second stood still for two or three frames and then jumped (gdstudio #1126, kit
## engines/godot/ragdoll.md#drawing). This modifier comes right after the simulator on the
## skeleton and puts every simulated bone where its body is drawn
## (`get_global_transform_interpolated()`), the simulator's `influence` kept.
##
## `CharacterRagdoll` puts it beside its bones (`place()`) and its `draw_between_ticks` turns it
## on and off. It is off while no bone is simulated and while the body sleeps, so a body lying
## still costs one check a tick.

## The name of the node, on the skeleton right after the ragdoll's simulator.
const NODE_NAME := &"RagdollDrawing"

## The ragdoll whose bodies this draws.
var ragdoll: CharacterRagdoll
## The bodies drawn (the ragdoll's, read again when its simulator changes).
var bodies: Array[PhysicalBone3D] = []

var _simulator: PhysicalBoneSimulator3D
# The body whose sleep stands for the whole ragdoll (Jolt wakes and sleeps a jointed body as one
# island): the pelvis.
var _sleeper: PhysicalBone3D
# Each simulated bone's pose before this modifier ran, read before any is written (setting a
# bone's global pose moves its children's).
var _before: Array[Transform3D] = []


## Puts `drawing` (made when null or freed with an old skeleton) on the skeleton of `of`'s bones,
## right after its simulator, and returns it. Nothing while `of` has no bones.
static func place(drawing: RagdollDrawing, of: CharacterRagdoll) -> RagdollDrawing:
	var simulator := of.simulator() if of.has_bones() else null
	var skeleton := simulator.get_parent() as Skeleton3D if simulator != null else null
	if skeleton == null:
		return drawing
	if drawing == null or not is_instance_valid(drawing):
		drawing = RagdollDrawing.new()
		drawing.name = NODE_NAME
		drawing.active = false
	if drawing.get_parent() != skeleton:
		if drawing.get_parent() != null:
			drawing.get_parent().remove_child(drawing)
		skeleton.add_child(drawing)
	skeleton.move_child(drawing, simulator.get_index() + 1)
	drawing.ragdoll = of
	drawing._follow()
	return drawing


# Once a tick: on while the ragdoll's bones on this skeleton are simulated and awake. A flinch
# simulates a few limbs and not the pelvis, so a sleeper that is not simulated never turns it off.
func _physics_process(_delta: float) -> void:
	_follow()


func _follow() -> void:
	var simulator: PhysicalBoneSimulator3D = null
	if is_instance_valid(ragdoll) and ragdoll.has_bones():
		simulator = ragdoll.simulator()
	if simulator != _simulator:
		_watch(simulator)
	var wanted := (
		simulator != null
		and ragdoll.draw_between_ticks
		and simulator.get_parent() == get_parent()
		and simulator.active
		and simulator.is_simulating_physics()
		and not _asleep()
	)
	if active != wanted:
		active = wanted


func _watch(simulator: PhysicalBoneSimulator3D) -> void:
	_simulator = simulator
	bodies.clear()
	_sleeper = null
	if simulator != null:
		for entry: Dictionary in CharacterRagdoll.BODIES:
			bodies.append(ragdoll.body(entry.bone))
		_sleeper = ragdoll.body(&"pelvis")
	_before.resize(bodies.size())


func _asleep() -> bool:
	if not is_instance_valid(_sleeper) or not _sleeper.is_simulating_physics():
		return false
	return PhysicsServer3D.body_get_state(_sleeper.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING)


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton != null and is_instance_valid(_simulator):
		draw(skeleton, _simulator.influence)


## Puts every simulated bone of `skeleton` where its body is drawn, as much as `share` (the
## simulator's influence) of the bone is the body's: the pose the simulator left (the tick's body
## at `share`) moved by `share` of the way from the tick's body to the drawn one.
func draw(skeleton: Skeleton3D, share: float) -> void:
	if share <= 0.0:
		return
	var tick_inverse := skeleton.global_transform.affine_inverse()
	var drawn_inverse := skeleton.get_global_transform_interpolated().affine_inverse()
	var whole := share >= 1.0
	if not whole:
		for index in bodies.size():
			var body := bodies[index]
			if is_instance_valid(body) and body.is_simulating_physics():
				_before[index] = skeleton.get_bone_global_pose(body.get_bone_id())
	for index in bodies.size():
		var body := bodies[index]
		if not is_instance_valid(body) or not body.is_simulating_physics():
			continue
		var offset := body.body_offset.affine_inverse()
		var drawn := drawn_inverse * body.get_global_transform_interpolated() * offset
		if whole:
			skeleton.set_bone_global_pose(body.get_bone_id(), drawn)
			continue
		var tick := tick_inverse * body.global_transform * offset
		var correction := Transform3D.IDENTITY.interpolate_with(
			drawn * tick.affine_inverse(), share
		)
		skeleton.set_bone_global_pose(body.get_bone_id(), correction * _before[index])

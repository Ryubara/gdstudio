class_name RagdollStage
extends Node3D
## One death staged the same way every run, for the ragdoll's tests: a mannequin on a floor plays
## a clip on the physics clock while it moves along +Z, and goes limp on a chosen tick with the
## velocity it had. Nothing reads real time (the `Player`'s animation tree does), so the same
## death gives the same numbers, which is what a joint that gives way only in some deaths needs.
## The scenarios are the ragdoll lab's (docs/engines/godot/ragdoll.md#limits).

const MODELS := {
	&"female": "res://assets/characters/mannequin/mannequin_female.glb",
	&"male": "res://assets/characters/mannequin/mannequin_male.glb",
}

var ragdoll: CharacterRagdoll
var slot: CharacterModel
var speed := 0.0
var _anim: AnimationPlayer
var _limp := false


## Builds the floor and the mannequin `model` (`&"female"` or `&"male"`) playing `clip` while it
## moves `speed` m/s along +Z. Call after the stage is in the tree.
func setup(model: StringName, clip: StringName, move_speed: float) -> void:
	speed = move_speed
	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(16.0, 1.0, 120.0)
	shape.shape = box
	floor_body.add_child(shape)
	add_child(floor_body)
	var root := Node3D.new()
	root.name = "Actor"
	root.position = Vector3(0.0, 0.0, -6.0 if speed > 0.0 else 0.0)
	add_child(root)
	slot = CharacterModel.new()
	root.add_child(slot)
	var rig := (load(MODELS[model]) as PackedScene).instantiate() as Node3D
	slot.add_child(rig)
	_anim = AnimationPlayer.new()
	_anim.add_animation_library(
		&"ual1", load("res://assets/animation/universal/ual1.glb") as AnimationLibrary
	)
	root.add_child(_anim)
	_anim.root_node = _anim.get_path_to(rig)
	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	_anim.play(clip)
	ragdoll = CharacterRagdoll.new()
	ragdoll.max_active = 0
	ragdoll.model = slot
	root.add_child(ragdoll)


## The body goes limp now, keeping the velocity of the walk (each bone its own, from the clip).
func kill() -> void:
	_anim.pause()
	_limp = ragdoll.start(Vector3(0.0, 0.0, speed))


func _physics_process(delta: float) -> void:
	if not _limp and slot != null:
		(slot.get_parent() as Node3D).position.z += speed * delta


## How far each elbow and knee is past its range now, in degrees: the most of the bend past
## `range` and the sideways lean (a hinge turns about its axis only). Keys are the bones.
func hinge_overrun() -> Dictionary:
	var found := {}
	for entry: Dictionary in CharacterRagdoll.BODIES:
		if entry.joint != &"hinge":
			continue
		var angles := hinge_angles(entry)
		var past := maxf(entry.range.x - angles.x, angles.x - entry.range.y)
		found[entry.bone] = Vector2(maxf(past, 0.0), absf(angles.y))
	return found


## The angles of a hinge joint from the straight limb, in degrees: x the bend (about the hinge),
## y the sideways lean and z the roll about the bone.
func hinge_angles(entry: Dictionary) -> Vector3:
	var skeleton := slot.skeleton()
	var parent: StringName = ragdoll._parent_body(skeleton, entry.bone)
	var rest := ragdoll.rest_body(parent).basis.inverse() * ragdoll.rest_body(entry.bone).basis
	var now := ragdoll.body(parent).global_basis.inverse() * ragdoll.body(entry.bone).global_basis
	var frame := CharacterRagdoll.hinge_frame(entry.axis)
	var q := Quaternion((frame.inverse() * rest.inverse() * now * frame).orthonormalized())
	if q.w < 0.0:
		q = -q
	return Vector3(
		rad_to_deg(2.0 * atan2(q.z, q.w)),
		rad_to_deg(2.0 * asin(clampf(q.y, -1.0, 1.0))),
		rad_to_deg(2.0 * asin(clampf(q.x, -1.0, 1.0)))
	)


## The angles of a cone joint from its centre, in degrees: x the swing (how far the bone points
## away from the centre) and y the twist about the bone, read the way Jolt reads them (the twist
## first, the swing of what is left).
func cone_angles(entry: Dictionary) -> Vector2:
	var skeleton := slot.skeleton()
	var parent: StringName = ragdoll._parent_body(skeleton, entry.bone)
	var rest := ragdoll.rest_body(parent).basis.inverse() * ragdoll.rest_body(entry.bone).basis
	var now := ragdoll.body(parent).global_basis.inverse() * ragdoll.body(entry.bone).global_basis
	var centre := Basis.from_euler(entry.centre * (PI / 180.0))
	var q := Quaternion((centre.inverse() * rest.inverse() * now).orthonormalized())
	if q.w < 0.0:
		q = -q
	var twist := Quaternion(q.x, 0.0, 0.0, q.w)
	twist = twist.normalized() if twist.length() > 0.0001 else Quaternion.IDENTITY
	var swing := q * twist.inverse()
	return Vector2(rad_to_deg(swing.get_angle()), rad_to_deg(2.0 * atan2(twist.x, twist.w)))

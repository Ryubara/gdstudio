@tool
class_name HitReaction
extends Node
## How the character's body answers a hit, on its own peer: a hit that kills throws the ragdoll
## along the shot from the bone that was hit (a headshot snaps the head back), a hit on a body
## already lying pushes the bone it hit, and a hit that does not kill makes the body flinch: the
## hit part and what hangs from it go physical for a moment (a partial ragdoll), pushed by the
## shot, and blend back into the clip while the legs keep walking.
##
## It listens to the character's `hit_received(record)`, so whatever gives the character a
## `HitRecord` (a shot here, or a record from the network) gets the same reaction. None of it is
## sent: each peer makes its own from the record. Every number is read when a hit lands.

## A flinch began on these bones.
signal flinched(bones: Array[StringName])
## The flinch ended: the clip has the whole skeleton again.
signal flinch_ended

## The bodies a flinch never takes: the legs keep their clip.
const LEGS: Array[StringName] = [&"thigh_l", &"calf_l", &"foot_l", &"thigh_r", &"calf_r", &"foot_r"]
## The body a flinch starts from when the pelvis or a leg is hit (the pelvis would take the whole
## body with it).
const TRUNK := &"spine_01"

@export_group("Nodes")
## The character whose hits this answers.
@export var character: Character:
	set(value):
		if character != null and character.hit_received.is_connected(_on_hit):
			character.hit_received.disconnect(_on_hit)
			character.revived.disconnect(_on_revived)
		character = value
		_connect()
## The character's ragdoll, which the death, the push and the flinch move.
@export var ragdoll: CharacterRagdoll

@export_group("Death")
## How hard a hit that kills throws the bone it hit, as a share of the hit's strength (a shot's
## impulse): real bullets barely move a body, games make it plain. 0: the body only falls.
@export_range(0.0, 10.0, 0.05, "or_greater") var death_push := 1.5

@export_group("Lying body")
## How hard a hit on a body already lying pushes the bone it hit, as a share of the hit's
## strength. 0: shots do not move a dead body.
@export_range(0.0, 10.0, 0.05, "or_greater") var lying_push := 0.5

@export_group("Flinch")
## On: a hit that does not kill makes the hit part flinch. Off: the body takes it with no motion.
@export var flinch_enabled := true
## How hard the flinch's push is, as a share of the hit's strength.
@export_range(0.0, 10.0, 0.05, "or_greater") var flinch_push := 0.6
## How much of the physical pose shows at the flinch's height (0 none, 1 all of it); it then
## blends back to the clip.
@export_range(0.0, 1.0, 0.01) var flinch_strength := 0.85
## How long a flinch lasts, seconds, from the hit until the clip has the skeleton again.
@export_range(0.05, 2.0, 0.01, "suffix:s") var flinch_time := 0.45
## The share of `flinch_time` the physical pose is held before it blends back.
@export_range(0.0, 0.95, 0.01) var flinch_hold := 0.25

var _flinch_left := 0.0
var _flinch_bones: Array[StringName] = []
var _lengths: RagdollLengths


func _ready() -> void:
	_connect()
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_tick_flinch(delta)


## True while a flinch holds some of the bones.
func is_flinching() -> bool:
	return _flinch_left > 0.0


## The bones the running flinch holds (empty when none).
func flinch_bones() -> Array[StringName]:
	return _flinch_bones


## The ragdoll body a hit on `bone` moves: the bone's own body, or the nearest one above it.
func body_for(bone: StringName) -> StringName:
	var skeleton := ragdoll.model.skeleton() if ragdoll != null and ragdoll.model != null else null
	if skeleton == null:
		return &""
	var index := skeleton.find_bone(bone)
	while index >= 0:
		var name_here := StringName(skeleton.get_bone_name(index))
		if ragdoll.body(name_here) != null:
			return name_here
		index = skeleton.get_bone_parent(index)
	return &"pelvis" if ragdoll.body(&"pelvis") != null else &""


## The bodies a flinch from a hit on `bone` takes: the hit body and every body that hangs from it,
## never a leg; a hit on the pelvis or a leg starts from the trunk.
func flinch_set(bone: StringName) -> Array[StringName]:
	var start := body_for(bone)
	if start == &"pelvis" or LEGS.has(start):
		start = TRUNK
	var picked: Array[StringName] = []
	if ragdoll == null or ragdoll.body(start) == null:
		return picked
	for entry: Dictionary in CharacterRagdoll.BODIES:
		var key: StringName = entry.bone
		if LEGS.has(key) or ragdoll.body(key) == null:
			continue
		var up := key
		while up != &"" and up != start:
			up = ragdoll.parent_body(up)
		if up == start:
			picked.append(key)
	return picked


func _connect() -> void:
	if character == null or Engine.is_editor_hint() or not is_inside_tree():
		return
	if not character.hit_received.is_connected(_on_hit):
		character.hit_received.connect(_on_hit)
		character.revived.connect(_on_revived)


func _on_hit(record: HitRecord) -> void:
	if ragdoll == null or not record.has_point():
		return
	if ragdoll.is_limp():
		_stop_flinch(false)
		_push(record, death_push if record.killed else lying_push)
	elif not character.is_dead():
		_flinch(record)


# Pushes the body the record hit at its point along its direction.
func _push(record: HitRecord, share: float) -> void:
	var key := body_for(record.bone)
	var bone := ragdoll.body(key)
	if bone == null or share <= 0.0 or record.strength <= 0.0:
		return
	bone.apply_impulse(record.direction * record.strength * share, _arm(bone, record))


# Where on `bone` the push lands, from its centre: the hit point, or the centre for a point that
# lies far from the bone (a record from a peer whose pose differed).
func _arm(bone: PhysicalBone3D, record: HitRecord) -> Vector3:
	var arm := record.point - bone.global_position
	return arm if arm.length() < 0.5 else Vector3.ZERO


func _flinch(record: HitRecord) -> void:
	if not flinch_enabled or flinch_strength <= 0.0:
		return
	var simulator := ragdoll.simulator()
	if simulator == null or (ragdoll.is_active() and not is_flinching()):
		# The ragdoll is getting up: a flinch would fight its blend.
		return
	var bones := flinch_set(record.bone)
	if bones.is_empty():
		return
	if is_flinching():
		# A new hit starts the flinch again, on its own part.
		simulator.physical_bones_stop_simulation()
	# Off first: every body is static while the simulator is off, so placing it moves it at once.
	simulator.active = false
	_place_bodies()
	simulator.influence = flinch_strength
	simulator.active = true
	simulator.physical_bones_start_simulation(bones)
	# With the character's velocity: at rest, a running body's limbs were left behind it.
	var moving := character.velocity if character != null else Vector3.ZERO
	for key in bones:
		ragdoll.body(key).linear_velocity = moving
	_hold_lengths(simulator, bones)
	var hit_body := body_for(record.bone)
	var pushed := ragdoll.body(hit_body if bones.has(hit_body) else bones[0])
	if flinch_push > 0.0 and record.strength > 0.0:
		pushed.apply_impulse(record.direction * record.strength * flinch_push, _arm(pushed, record))
	_flinch_bones = bones
	_flinch_left = flinch_time
	set_physics_process(true)
	flinched.emit(bones)


# Puts every body at rest where the animated pose has it while the simulator is off. Every body,
# not only the flinch's: the flinch's top body hangs by a joint from one that is not simulated,
# which stays where the last flinch or death left it, and once the simulator is on it is
# kinematic, which Jolt carries to a new place over the next tick at whatever speed that takes
# (`MoveKinematic`): a parent 0.9 m away pulled the limb at 50 to 70 m/s, a rod on screen for a
# few frames (gdstudio #1338).
func _place_bodies() -> void:
	for entry: Dictionary in CharacterRagdoll.BODIES:
		var body := ragdoll.body(entry.bone)
		if body == null:
			continue
		var placed := ragdoll.animated_body(entry.bone)
		body.global_transform = placed
		# The server too: a body that is not simulated does not hand its node's move on.
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, placed)
		body.reset_physics_interpolation()
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO


# The flinch's bones keep their lengths while the clip moves the bones between the bodies.
func _hold_lengths(simulator: PhysicalBoneSimulator3D, bones: Array[StringName]) -> void:
	_lengths = RagdollLengths.place(_lengths, simulator)
	if _lengths == null:
		return
	var skeleton := simulator.get_parent() as Skeleton3D
	var ids := PackedInt32Array()
	for key in bones:
		ids.append(skeleton.find_bone(key))
	_lengths.bones = ids
	_lengths.active = true


func _tick_flinch(delta: float) -> void:
	if _flinch_left <= 0.0:
		set_physics_process(false)
		return
	if ragdoll == null or ragdoll.is_limp() or ragdoll.simulator() == null:
		# The character died meanwhile: the ragdoll has the whole skeleton now.
		_stop_flinch(false)
		return
	_flinch_left = maxf(_flinch_left - delta, 0.0)
	var done := 1.0 - _flinch_left / maxf(flinch_time, 0.001)
	var left := 1.0 - smoothstep(flinch_hold, 1.0, done)
	ragdoll.simulator().influence = flinch_strength * left
	if _flinch_left <= 0.0:
		_stop_flinch(true)


# Ends the flinch; `release` hands the skeleton back to the clip (off when the ragdoll took it).
func _stop_flinch(release: bool) -> void:
	if _flinch_bones.is_empty() and _flinch_left <= 0.0:
		return
	var simulator := ragdoll.simulator() if ragdoll != null else null
	if release and simulator != null and not ragdoll.is_limp():
		simulator.physical_bones_stop_simulation()
		simulator.active = false
		simulator.influence = 1.0
	if is_instance_valid(_lengths):
		_lengths.active = false
	_flinch_left = 0.0
	_flinch_bones = []
	set_physics_process(false)
	flinch_ended.emit()


# A body that gets up takes its wounds off: the marks shots left on its bones hang on bones that
# follow the clip a tick late.
func _on_revived() -> void:
	var simulator := ragdoll.simulator() if ragdoll != null else null
	if simulator != null and is_inside_tree():
		var impacts := Impacts.find(self)
		if impacts != null:
			impacts.clear_marks_on(simulator)
		_hold_lengths_getting_up(simulator)


# The get-up blend keeps the bones' lengths too, all but the pelvis (it moves the body): blending
# from where the bodies lie, a hand stood 6 cm off its forearm (gdstudio #1338).
func _hold_lengths_getting_up(simulator: PhysicalBoneSimulator3D) -> void:
	if not ragdoll.is_active() or ragdoll.is_limp():
		return
	var all: Array[StringName] = []
	for entry: Dictionary in CharacterRagdoll.BODIES:
		if entry.bone != &"pelvis":
			all.append(entry.bone)
	_hold_lengths(simulator, all)
	if not ragdoll.stopped.is_connected(_release_lengths):
		ragdoll.stopped.connect(_release_lengths)
		ragdoll.started.connect(_release_lengths)


func _release_lengths() -> void:
	if is_instance_valid(_lengths) and not is_flinching():
		_lengths.active = false


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if character == null:
		warnings.append("Set `character` to the character whose hits this answers.")
	if ragdoll == null:
		warnings.append("Set `ragdoll` to the character's ragdoll.")
	return warnings

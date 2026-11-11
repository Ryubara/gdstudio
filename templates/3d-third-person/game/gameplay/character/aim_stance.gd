class_name AimStance
extends RefCounted
## The legs under a standing aim (kit #1206), kept apart so the tree's script stays one size. The
## template's idle shifts its weight from foot to foot (the pelvis 40 mm to each side over its
## 10 s loop), and the aim pose rides the pelvis, so the muzzle swayed 34 mm to each side while
## the player held the aim. A person who aims stops shifting: the ground state's idle point is the
## idle and the same clip held still on its steadiest pose (the frame whose pelvis is nearest the
## middle of its sway), blended by how far the arm is up, so the stance comes in with the aim and
## goes with it. Walking, the blend space has already left the idle point, so the gaits are as
## they were. Cosmetic: a pose worked out on each machine, never sent.

## The blend inside the idle point, 0 the idle playing, 1 the held pose.
const BLEND := &"Steady"
## Its amount in the tree: the idle point (`idle`) of the ground state, in the `Locomotion` machine
## at the tree's root (`CharacterAnimation._build_ground()`).
const AMOUNT := "parameters/Locomotion/%s/idle/%s/blend_amount" % [CharacterAnimation.GROUND, BLEND]
## How often the idle's pelvis is read to find the held pose, per second.
const SAMPLES_PER_SECOND := 30.0

## The time of the idle clip the stance holds, in seconds (`steady_time()`).
var held_at := 0.0


## The node for the ground blend space's idle point: `clip` playing, and `clip` held on its
## steadiest pose, blended by `drive()`.
func idle_point(animation: CharacterAnimation, clip: StringName) -> AnimationNodeBlendTree:
	held_at = steady_time(animation, clip)
	var point := AnimationNodeBlendTree.new()
	var playing := AnimationNodeAnimation.new()
	playing.animation = clip
	# A clip's own timeline cut to nothing at the held frame: whatever time the blend space and
	# the state machine hand it (a sync, a seek to the start), it shows that one pose.
	var held := AnimationNodeAnimation.new()
	held.animation = clip
	held.use_custom_timeline = true
	held.stretch_time_scale = false
	held.loop_mode = Animation.LOOP_NONE
	held.start_offset = held_at
	held.timeline_length = 0.0
	point.add_node(&"Playing", playing, Vector2(0, 0))
	point.add_node(&"Held", held, Vector2(0, 200))
	point.add_node(BLEND, AnimationNodeBlend2.new(), Vector2(200, 100))
	point.connect_node(BLEND, 0, &"Playing")
	point.connect_node(BLEND, 1, &"Held")
	point.connect_node(&"output", 0, BLEND)
	return point


## Weighs the held pose by `aim`, how far the arm is up (0 to 1), or not at all while `on` is off.
func drive(tree: AnimationTree, aim: float, on: bool) -> void:
	if tree != null and tree.tree_root != null:
		tree.set(AMOUNT, clampf(aim, 0.0, 1.0) if on else 0.0)


## How much of the idle point the held pose has now (0 to 1).
func amount(tree: AnimationTree) -> float:
	return float(tree.get(AMOUNT)) if tree != null and tree.tree_root != null else 0.0


## The time of `clip` whose pelvis (the parent of the upper body's first bone) is nearest its
## mean place over the clip: the weight between the feet, the pose the clip passes through in the
## middle of a shift. 0 when the clip or the bone is missing or the pelvis has no position track.
static func steady_time(animation: CharacterAnimation, clip: StringName) -> float:
	var player := animation.animation_player
	var model := animation.model
	var skeleton := model.skeleton() if is_instance_valid(model) else null
	if skeleton == null or player == null or not player.has_animation(clip):
		return 0.0
	var pelvis := skeleton.get_bone_parent(skeleton.find_bone(animation.upper_body_bone))
	if pelvis < 0:
		return 0.0
	var tracks := String(model.rig().get_path_to(skeleton))
	var clip_data := player.get_animation(clip)
	var path := NodePath("%s:%s" % [tracks, skeleton.get_bone_name(pelvis)])
	var track := clip_data.find_track(path, Animation.TYPE_POSITION_3D)
	if track < 0 or clip_data.track_get_key_count(track) == 0:
		return 0.0
	var count := maxi(int(clip_data.length * SAMPLES_PER_SECOND), 1)
	var places := PackedVector3Array()
	var middle := Vector3.ZERO
	for index in count:
		var place := clip_data.position_track_interpolate(track, clip_data.length * index / count)
		places.append(place)
		middle += place / count
	var best := 0
	for index in count:
		if places[index].distance_to(middle) < places[best].distance_to(middle):
			best = index
	return clip_data.length * best / count

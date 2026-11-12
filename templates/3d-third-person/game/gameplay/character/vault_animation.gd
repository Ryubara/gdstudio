class_name VaultAnimation
extends RefCounted
## What `CharacterAnimation` does for a vault timed by its clip (`VaultClip`), kept apart so the
## tree's script stays one size: the vault clip and the step out of its landing joined into one
## animation (so the tree plays them as one action with no blend between), held to the clip time
## the body's own crossing is at; the model held where the clip's root belongs while the capsule
## goes over the top; and the hands kept off the weapon while they are busy.
## Cosmetic only: it reads the `Character` and is never stepped or sent.

## The library the joined clips are added to on the character's `AnimationPlayer`.
const LIBRARY := &"vault_joined"
## The tree's node that seeks the action clip, and its request.
const SEEK := &"ActionSeek"
const SEEK_REQUEST := &"parameters/ActionSeek/seek_request"
const PACE := &"parameters/ActionScale/scale"

## How busy the hands are with the vault (0 free, 1 on the obstacle): the weapon's two-hand hold
## lets go by this much.
var hands := 0.0
## True while the vault needs both hands open, so the weapon in the hands is hidden.
var away := false

var _playing: StringName = &""
var _was_running := false
var _rig_path := ""


## Plays `clip` over the whole body for the crossing `plan` on `animation`. A vault timed by its
## clip starts at the frame and plays at the rate the plan gives, with the landing step
## (`vault_land_clip`) after it; any other crossing's clip is played to last the crossing's time,
## inside `traversal_speed_range`.
func start(animation: CharacterAnimation, plan: VaultPlan, clip: StringName) -> void:
	var player := animation.animation_player
	if animation.tree == null or not player.has_animation(clip):
		animation.play_clip(clip, plan.duration)
		return
	if plan.has_clip_timing():
		var skeleton := animation.model.skeleton() if is_instance_valid(animation.model) else null
		_playing = _joined(player, skeleton, clip, animation.vault_land_clip)
		animation.play_clip(_playing)
		animation.tree.set(PACE, plan.clip_rate)
		animation.tree.set(SEEK_REQUEST, plan.clip_start)
		return
	animation.play_clip(clip, plan.duration)
	if plan.duration <= 0.0:
		return
	var paces := animation.traversal_speed_range
	var pace := clampf(player.get_animation(clip).length / plan.duration, paces.x, paces.y)
	animation.tree.set(PACE, pace)


## Follows `character`'s vault for a frame: holds the clip and the model to the crossing, keeps
## the hands' share, and when a vault ends with no move asked for, stops the landing step (a body
## that stands still does not run out of it). Returns the ground speed the tree's gait blends
## by: the body's own, or through a vault its pace across (the capsule has no velocity then, and
## the gait under the clip would drop to the idle the clip then blends in from).
func follow(
	character: Character, animation: CharacterAnimation, blend: float, delta: float
) -> float:
	var motion := character.vault_motion
	var timing := motion.clip(character.vault_settings)
	var running := timing != null and motion.is_active()
	var ours := animation.is_acting() and animation.last_action() == _playing
	if _was_running and not running and ours and character.last_command.move.is_zero_approx():
		animation.stop_clip()
		ours = false
	_was_running = running
	var model := character.model
	if not running:
		release(model)
	else:
		# The body that is drawn is the last tick's, or between the last two with physics
		# interpolation: the clip is held to that time and the model to the clip's root at that
		# time, so a planted hand stays where it landed.
		var shown := motion.elapsed
		if character.is_physics_interpolated_and_enabled():
			var behind := 1.0 - Engine.get_physics_interpolation_fraction()
			shown -= behind / Engine.physics_ticks_per_second
		var share := clampf(shown / maxf(motion.plan.duration, 0.001), 0.0, 1.0)
		if ours:
			animation.tree.set(SEEK_REQUEST, motion.plan.clip_time(share))
		if model != null:
			_hold(model, motion.plan.root_at(timing, share))
	away = running and timing.puts_weapon_away
	var busy := 1.0 if running or (ours and _playing != &"") else 0.0
	hands = move_toward(hands, busy, delta / maxf(blend, 0.001))
	if not running:
		return character.ground_speed()
	var path := motion.plan.end_point() - motion.plan.points[0]
	return Vector2(path.x, path.z).length() / maxf(motion.plan.duration, 0.001)


## Gives `model` back to the body it belongs to, on the capsule (the vault ended, or the body was
## put somewhere else).
static func release(model: Node3D) -> void:
	if model == null or not model.top_level:
		return
	model.top_level = false
	model.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	model.position = Vector3.ZERO
	model.reset_physics_interpolation()


# Puts `model` at `root` in the world for this frame. While the vault holds it the model is its
# own in the world and outside the physics interpolation: its place is worked out here for the
# very time that is drawn, where the capsule's fast way up over the top would otherwise show as
# the model sinking or rising for a frame.
func _hold(model: Node3D, root: Vector3) -> void:
	if not model.top_level:
		var facing := model.global_rotation
		model.top_level = true
		model.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		model.global_rotation = facing
	model.global_position = root


# The name of `clip` followed by `landing` as one animation in the player's own `LIBRARY`, made
# the first time it is asked for (and again for another model: its rest pose fills the tracks one
# clip has and the other lacks).
func _joined(
	player: AnimationPlayer, skeleton: Skeleton3D, clip: StringName, landing: StringName
) -> StringName:
	if landing == &"" or not player.has_animation(landing):
		return clip
	var path := skeleton.owner.scene_file_path if skeleton != null and skeleton.owner else ""
	if not player.has_animation_library(LIBRARY):
		player.add_animation_library(LIBRARY, AnimationLibrary.new())
	var library := player.get_animation_library(LIBRARY)
	if path != _rig_path:
		for old in library.get_animation_list():
			library.remove_animation(old)
		_rig_path = path
	var short := StringName(
		String(clip).replace("/", "_") + "__" + String(landing).replace("/", "_")
	)
	if not library.has_animation(short):
		library.add_animation(
			short, join(player.get_animation(clip), player.get_animation(landing), skeleton)
		)
	return StringName("%s/%s" % [LIBRARY, short])


## `first` followed by `second` as one animation. A bone only one of them moves keeps its rest
## pose (`skeleton`'s) through the other.
static func join(first: Animation, second: Animation, skeleton: Skeleton3D) -> Animation:
	var out := first.duplicate(true) as Animation
	var seam := first.length
	out.length = seam + second.length
	out.loop_mode = Animation.LOOP_NONE
	var joined := {}
	for track in second.get_track_count():
		var kind := second.track_get_type(track)
		var path := second.track_get_path(track)
		var into := out.find_track(path, kind)
		if into < 0:
			into = out.add_track(kind)
			out.track_set_path(into, path)
			out.track_set_interpolation_type(into, second.track_get_interpolation_type(track))
			var rest: Variant = _rest(skeleton, path, kind)
			if rest != null:
				out.track_insert_key(into, 0.0, rest)
				out.track_insert_key(into, seam - 0.001, rest)
		joined[into] = true
		for key in second.track_get_key_count(track):
			var at := second.track_get_key_time(track, key)
			out.track_insert_key(into, seam + at, second.track_get_key_value(track, key))
	for track in first.get_track_count():
		if joined.has(track):
			continue
		var rest: Variant = _rest(skeleton, out.track_get_path(track), out.track_get_type(track))
		if rest != null:
			out.track_insert_key(track, seam + 0.001, rest)
	return out


# The rest value of the bone a track moves (its rotation, position or scale), or null.
static func _rest(skeleton: Skeleton3D, path: NodePath, kind: Animation.TrackType) -> Variant:
	if skeleton == null or path.get_subname_count() == 0:
		return null
	var bone := skeleton.find_bone(path.get_subname(0))
	if bone < 0:
		return null
	var rest := skeleton.get_bone_rest(bone)
	match kind:
		Animation.TYPE_ROTATION_3D:
			return rest.basis.get_rotation_quaternion()
		Animation.TYPE_POSITION_3D:
			return rest.origin
		Animation.TYPE_SCALE_3D:
			return rest.basis.get_scale()
	return null

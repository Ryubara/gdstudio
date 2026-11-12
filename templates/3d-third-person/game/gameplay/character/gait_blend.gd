class_name GaitBlend
extends RefCounted
## The ground and crouch blend spaces of `CharacterAnimation`, and the speed matching that keeps a
## planted foot on its place on the floor (gdstudio #1158).
##
## Each space is a `BlendSpace1D` on ground speed whose first point is the idle and whose other
## points are gaits. A gait's point is the clip behind a seek and a time scale (`Clip`, `Seek`,
## `Pace`), at the speed its clip covers on this body: the record's speed (`GaitClips`) times the
## body's leg length over the reference's. Every frame the gaits play at one phase rate, the
## ground speed over the stride the blend weighs: `pace_i = length_i * speed / sum(w_j stride_j)`
## with `stride_j = speed_j * length_j`. At a point that is the ground speed over the clip's speed,
## below the walk the walk keeps its own pace while the idle fades out (its planted feet weigh
## nothing in the stride), and between two gaits the feet of both move at the ground's speed, so
## a foot planted in both stays where it landed. The gaits share one phase: they start together
## at the left foot's landing, and each covers a cycle in the same time.
##
## A clip with no record (a library clip put back as a stand-in) sits at the tuning's speed for
## its gait and plays at its own pace there, as the template's gaits did before.

## The nodes of a gait point's blend tree.
const CLIP := &"Clip"
const SEEK := &"Seek"
const PACE := &"Pace"
## The names of the ground space's gait points, slowest first, and of the crouch walk's.
const GROUND_GAITS: Array[StringName] = [&"walk", &"run", &"sprint"]
const CROUCH_GAITS: Array[StringName] = [&"walk"]
## The share of a contact its foot takes to roll down onto the floor, and the trim's lag (s) and
## its limits.
const ROLL_ON := 0.25
const TRIM_TIME := 0.15
const TRIM_RANGE := Vector2(0.8, 1.25)

var settings: GaitSettings
## The body's leg length over the reference body's (`GaitClips.leg_scale()`), read every frame.
var leg := 1.0

var _spaces := {}  # machine state -> {space, gaits, clips, speeds, lengths, path}
# The trim of the ground gaits' rate while two of them blend, from the planted foot itself.
var _trim := 1.0
var _trim_foot := ""
var _trim_place := Vector3.ZERO
var _to_body := 1.0


## Builds the ground state's space: the idle point `idle` at 0, then the walk, run and sprint.
func build_ground(
	animation: CharacterAnimation, idle: AnimationRootNode
) -> AnimationNodeBlendSpace1D:
	var clips: Array[StringName] = [animation.walk_clip, animation.run_clip, animation.sprint_clip]
	return _build(animation, CharacterAnimation.GROUND, idle, GROUND_GAITS, clips)


## Builds the crouch state's space: the crouch idle at 0, the crouch walk at its speed.
func build_crouch(animation: CharacterAnimation) -> AnimationNodeBlendSpace1D:
	var idle := AnimationNodeAnimation.new()
	idle.animation = animation.crouch_idle_clip
	var clips: Array[StringName] = [animation.crouch_walk_clip]
	return _build(animation, CharacterAnimation.CROUCH, idle, CROUCH_GAITS, clips)


## The clip a gait point of `space` plays (`walk`, `run`, `sprint`), or `&""`.
static func clip_of(space: AnimationNodeBlendSpace1D, point: StringName) -> StringName:
	var index := space.find_blend_point_by_name(point)
	if index < 0:
		return &""
	var node := space.get_blend_point_node(index)
	if node is AnimationNodeBlendTree:
		node = (node as AnimationNodeBlendTree).get_node(CLIP)
	return (node as AnimationNodeAnimation).animation if node is AnimationNodeAnimation else &""


## Puts the gait points at their speeds: the clips' on this body with the speed matching, else the
## tuning's (`walk_speed`, `run_speed`, `sprint_speed`, `crouch_speed`).
func place_points(tuning: CharacterTuning) -> void:
	if tuning == null:
		return
	var tuned := {
		CharacterAnimation.GROUND: [tuning.walk_speed, tuning.run_speed, tuning.sprint_speed],
		CharacterAnimation.CROUCH: [tuning.crouch_speed],
	}
	for state: StringName in _spaces:
		var entry: Dictionary = _spaces[state]
		var space: AnimationNodeBlendSpace1D = entry.space
		var speeds := PackedFloat32Array()
		for index in (entry.clips as Array).size():
			var fallback: float = tuned[state][index]
			var own := GaitClips.speed(entry.clips[index], fallback) * leg
			speeds.append(own if _matching() else fallback)
		entry.speeds = speeds
		for index in speeds.size():
			space.set_blend_point_position(index + 1, speeds[index])
		space.max_space = maxf(speeds[-1], tuned[state][-1])


## Sets the speed of each space and the pace of each of its gaits for this frame.
func drive(animation: CharacterAnimation, speed: float, delta: float) -> void:
	var tree := animation.tree
	var skeleton := animation.model.skeleton() if is_instance_valid(animation.model) else null
	var scale := GaitClips.leg_scale(skeleton, animation.character)
	if not is_equal_approx(scale, leg):
		leg = scale
		place_points(animation.character.tuning)
	for state: StringName in _spaces:
		var entry: Dictionary = _spaces[state]
		var at := position_at(entry.speeds, speed)
		tree.set(entry.position, at)
		var trimmed := 1.0
		if state == CharacterAnimation.GROUND:
			_follow_foot(animation, skeleton, entry, speed, at, delta)
			trimmed = _trim
		var paces := paces_at(entry, speed, at)
		for index in paces.size():
			tree.set(entry.paces[index], paces[index] * trimmed)


## The ground gaits' rate trim now (1 none): while two gaits blend, the blended pose's planted
## foot sweeps a little slower or faster than either clip's (a turn blended is not a place
## blended), and the rate is trimmed by how fast that foot really moved over the last frame.
func rate_trim() -> float:
	return _trim


# Measures the foot that is down in both gaits that blend (past the roll onto it) and trims the
# rate toward the speed that holds it; back to no trim when one gait plays alone.
func _follow_foot(
	animation: CharacterAnimation,
	skeleton: Skeleton3D,
	entry: Dictionary,
	speed: float,
	at: float,
	delta: float,
) -> void:
	var weights := gait_weights(entry.speeds, at)
	var blended: Array[StringName] = []
	for index in weights.size():
		if weights[index] > 0.05:
			blended.append(entry.clips[index])
	if blended.size() < 2 or skeleton == null or delta <= 0.0 or not _matching() or speed < 0.5:
		_trim = move_toward(_trim, 1.0, delta)
		_trim_foot = ""
		return
	var share := phase(animation.tree, CharacterAnimation.GROUND)
	var foot := ""
	for side: String in ["l", "r"]:
		if blended.all(func(clip: StringName) -> bool: return _down(clip, side, share)):
			foot = side
	if foot == "":
		_trim_foot = ""
		return
	var bone := skeleton.find_bone("ball_" + foot)
	if bone < 0:
		return
	var place := skeleton.get_bone_global_pose(bone).origin
	if foot == _trim_foot:
		_to_body = (
			(animation.character.global_basis.inverse() * skeleton.global_basis).get_scale().z
		)
		var backward := (_trim_place.z - place.z) * _to_body / delta
		if backward > 0.3 * speed:
			var follow := clampf(delta / TRIM_TIME, 0.0, 1.0)
			_trim = clampf(
				lerpf(_trim, _trim * speed / backward, follow), TRIM_RANGE.x, TRIM_RANGE.y
			)
	_trim_foot = foot
	_trim_place = place


# True when `foot` of `clip` is down at `share` of its cycle, past the roll onto it.
static func _down(clip: StringName, foot: String, share: float) -> bool:
	for window: Array in GaitClips.contacts(clip, foot):
		var from: float = window[0] + ROLL_ON * (window[1] - window[0])
		if share >= from and share <= window[1]:
			return true
	return false


## Where in a space whose gaits sit at `speeds` the blend is at ground speed `speed`: a gait's
## own point while it plays alone, slowed or sped up (`GaitSettings.stretch` and
## `slowest_pace`), and between two points only across the speeds that blend them. `speed` itself
## without the speed matching.
func position_at(speeds: PackedFloat32Array, speed: float) -> float:
	if not _matching() or speeds.is_empty():
		return speed
	var first := speeds[0]
	if speed <= first:
		var alone := first * settings.slowest_pace
		return first if speed >= alone else speed / maxf(settings.slowest_pace, 0.01)
	for index in range(speeds.size() - 1):
		if speed <= speeds[index + 1]:
			return _between(speeds[index], speeds[index + 1], speed)
	return speed


# `position_at()` between two gaits at `slower` and `faster` m/s: each alone as far as the
# stretch lets it, the blend across the speeds between.
func _between(slower: float, faster: float, speed: float) -> float:
	var up_to := slower * settings.stretch.y
	var from := faster * settings.stretch.x
	if up_to >= from:
		return speed
	var share := clampf((speed - up_to) / (from - up_to), 0.0, 1.0)
	return slower + share * (faster - slower)


## The pace of each gait of a space's `entry` at ground speed `speed`, with the blend at `at`
## (`position_at()`), 1 being its clip's own.
func paces_at(entry: Dictionary, speed: float, at: float) -> PackedFloat32Array:
	var count: int = (entry.clips as Array).size()
	var paces := PackedFloat32Array()
	paces.resize(count)
	paces.fill(1.0)
	if not _matching():
		return paces
	var speeds: PackedFloat32Array = entry.speeds
	var lengths: PackedFloat32Array = entry.lengths
	var weights := gait_weights(speeds, at)
	var stride := 0.0
	var log_stride := 0.0
	var gaits := 0.0
	var nearest := 0
	for index in count:
		var own_stride := speeds[index] * lengths[index]
		stride += weights[index] * own_stride
		log_stride += weights[index] * log(maxf(own_stride, 0.0001))
		gaits += weights[index]
		if weights[index] > weights[nearest]:
			nearest = index
	if gaits > 0.999:
		stride = exp(log_stride)
	# Cycles a second: the ground speed over the stride the blend weighs, or the nearest gait's own
	# when only the idle has weight.
	var rate := speed / stride if stride > 0.0001 else 1.0 / lengths[nearest]
	var own := rate * lengths[nearest]
	var held := clampf(own, settings.pace_range.x, settings.pace_range.y)
	rate *= held / own if own > 0.0 else 1.0
	for index in count:
		paces[index] = rate * lengths[index]
	return paces


## Each gait's weight in a space whose idle is at 0 and whose gaits are at `speeds` (rising), at
## `speed`: the space's own linear blend between the two points either side.
static func gait_weights(speeds: PackedFloat32Array, speed: float) -> PackedFloat32Array:
	var weights := PackedFloat32Array()
	weights.resize(speeds.size())
	weights.fill(0.0)
	var below := 0.0
	for index in speeds.size():
		if speed <= speeds[index]:
			var share := clampf((speed - below) / maxf(speeds[index] - below, 0.0001), 0.0, 1.0)
			weights[index] = share
			if index > 0:
				weights[index - 1] = 1.0 - share
			return weights
		below = speeds[index]
	weights[-1] = 1.0
	return weights


## Where the gaits of `state` are in their shared cycle, 0 to 1 (the first gait's place over its
## length; the gaits all keep it).
func phase(tree: AnimationTree, state: StringName) -> float:
	var entry: Dictionary = _spaces.get(state, {})
	if entry.is_empty() or tree == null:
		return 0.0
	var at: float = tree.get(entry.positions[0])
	var length: float = entry.lengths[0]
	return fposmod(at, length) / length if length > 0.0 else 0.0


## The gait clip of `state` that weighs most at `speed`, or `&""` with none.
func main_gait(state: StringName, speed: float) -> StringName:
	var entry: Dictionary = _spaces.get(state, {})
	if entry.is_empty():
		return &""
	var weights := gait_weights(entry.speeds, position_at(entry.speeds, speed))
	var best := 0
	for index in weights.size():
		if weights[index] > weights[best]:
			best = index
	return entry.clips[best]


## The point name (`walk`, `run`, `sprint`) of the gait of `state` that weighs most at `speed`.
func main_point(state: StringName, speed: float) -> StringName:
	var entry: Dictionary = _spaces.get(state, {})
	if entry.is_empty():
		return &""
	var weights := gait_weights(entry.speeds, position_at(entry.speeds, speed))
	var best := 0
	for index in weights.size():
		if weights[index] > weights[best]:
			best = index
	return entry.gaits[best]


## The speed of the gait point `point` of `state` on this body (m/s), or 0.
func point_speed(state: StringName, point: StringName) -> float:
	var entry: Dictionary = _spaces.get(state, {})
	var index := (entry.get("gaits", []) as Array).find(point)
	return entry.speeds[index] if index >= 0 else 0.0


## Puts every gait of `state` at `share` of its cycle at once (a transition hands over to the gait
## at the phase it ends on).
func seek_phase(tree: AnimationTree, state: StringName, share: float) -> void:
	var entry: Dictionary = _spaces.get(state, {})
	if entry.is_empty() or tree == null:
		return
	for index in (entry.clips as Array).size():
		tree.set(entry.seeks[index], fposmod(share, 1.0) * entry.lengths[index])


func _matching() -> bool:
	return settings == null or settings.speed_match


func _build(
	animation: CharacterAnimation,
	state: StringName,
	idle: AnimationRootNode,
	gaits: Array[StringName],
	clips: Array[StringName],
) -> AnimationNodeBlendSpace1D:
	var space := AnimationNodeBlendSpace1D.new()
	space.min_space = 0.0
	# Room for the points before `place_points()` puts them at their speeds.
	space.max_space = 100.0
	space.sync = true
	space.add_blend_point(idle, 0.0, -1, &"idle")
	var base := "parameters/Locomotion/%s/" % state
	var entry := {
		"space": space,
		"gaits": gaits,
		"clips": clips,
		"speeds": PackedFloat32Array(),
		"lengths": PackedFloat32Array(),
		"position": StringName(base + "blend_position"),
		"paces": [],
		"seeks": [],
		"positions": [],
	}
	# A packed array is a value: filled here and put in the entry whole.
	var lengths := PackedFloat32Array()
	for index in gaits.size():
		var clip := clips[index]
		space.add_blend_point(_point(clip), float(index + 1), -1, gaits[index])
		var point := base + String(gaits[index]) + "/"
		(entry.paces as Array).append(StringName(point + "%s/scale" % PACE))
		(entry.seeks as Array).append(StringName(point + "%s/seek_request" % SEEK))
		(entry.positions as Array).append(StringName(point + "%s/current_position" % CLIP))
		lengths.append(_length(animation, clip))
	entry.lengths = lengths
	_spaces[state] = entry
	place_points(animation.character.tuning if animation.character != null else null)
	return space


static func _point(clip: StringName) -> AnimationNodeBlendTree:
	var point := AnimationNodeBlendTree.new()
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	point.add_node(CLIP, node, Vector2(0, 0))
	point.add_node(SEEK, AnimationNodeTimeSeek.new(), Vector2(200, 0))
	point.add_node(PACE, AnimationNodeTimeScale.new(), Vector2(400, 0))
	point.connect_node(SEEK, 0, CLIP)
	point.connect_node(PACE, 0, SEEK)
	point.connect_node(&"output", 0, PACE)
	return point


# The clip's length in seconds: the record's, else the clip's own, else a second.
static func _length(animation: CharacterAnimation, clip: StringName) -> float:
	var player := animation.animation_player
	if player != null and player.has_animation(clip):
		return maxf(player.get_animation(clip).length, 0.01)
	var own := GaitClips.seconds(clip)
	return own if own > 0.0 else 1.0

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
## at the left foot's landing, and each covers a cycle in the same time. Where two stretched gaits
## meet with no speeds between, the drawn position crosses from one to the other over
## `GaitSettings.gait_change_time` (gdstudio #1578: a speed crossing there changed the pose in a
## tick).
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
## Seconds the crouch space is still set after the body last crouched or was drawn crouched: a
## cross-fade out of the crouch (`CharacterAnimation.blend_time`, with the momentum blend off)
## still draws it. Outside that nothing draws it, so it is not set (gdstudio #1569).
const CROUCH_HOLD := 0.5

var settings: GaitSettings
## On, every space is set every frame, drawn or not (a test holds the shortcut against it).
var set_undrawn := false
## The body's leg length over the reference body's (`GaitClips.leg_scale()`), read every frame.
var leg := 1.0

var _spaces := {}  # machine state -> {space, gaits, clips, speeds, lengths, path}
# The trim of the ground gaits' rate while two of them blend, from the planted foot itself.
var _trim := 1.0
var _trim_foot := ""
var _trim_place := Vector3.ZERO
var _to_body := 1.0
var _crouch_hold := 0.0
# The skeleton whose ball bones `_balls` holds (by instance id), found once.
var _balls_of := 0
var _balls := PackedInt32Array([-1, -1])


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
	var crouch_drawn := _crouch_drawn(animation, delta)
	var shown := animation.body_state()
	for state: StringName in _spaces:
		var entry: Dictionary = _spaces[state]
		var target := position_at(entry.speeds, speed)
		var at := _follow(entry, target, delta, shown == state)
		if state == CharacterAnimation.CROUCH and not crouch_drawn:
			continue
		tree.set(entry.position, at)
		# The paces (the cadence) and the trim come from the speed's own position: a gait still
		# fading out keeps the cadence of the one coming in, never raced to its fastest pace to
		# cover the speed alone (a crouch walk's arms at twice its pace standing up into a jog).
		var trimmed := 1.0
		if state == CharacterAnimation.GROUND:
			_follow_foot(animation, skeleton, entry, speed, target, delta)
			trimmed = _trim
		var paces := paces_at(entry, speed, target)
		for index in paces.size():
			tree.set(entry.paces[index], paces[index] * trimmed)


# The position `entry`'s space is drawn at this frame. Where two gaits' stretched ranges meet with
# no speeds between (`_seam()`: the jog alone to 5.2 m/s, the sprint alone from 5.2), it moves
# toward `target` (`position_at()`) by at most one gait in `gait_change_time`, counted in points
# (`_steps_at()`), so a speed that crosses the seam in a tick still blends the pose over that time.
# Elsewhere, and while its state is not the machine's (`current`: a transition clip or a stance
# draws the body, and hands over to the speed's own position), it is `target`: a blend with
# speeds of its own already spreads the change, and slowed there the walk's arms fading out of a
# crouch walk into a jog moved a hand 0.18 m in a tick, not 0.12.
func _follow(entry: Dictionary, target: float, delta: float, current: bool) -> float:
	var drawn: float = entry.drawn
	if drawn == target:
		return target  # At rest on the speed's own position: most frames, nothing to work out.
	var time := settings.gait_change_time if settings != null else 0.0
	var speeds: PackedFloat32Array = entry.speeds
	var from := _steps_at(speeds, drawn)
	var to := _steps_at(speeds, target)
	if (
		not current
		or drawn < 0.0
		or time <= 0.0
		or delta <= 0.0
		or not _crosses_seam(speeds, from, to)
	):
		entry.drawn = target
		return target
	entry.drawn = _position_of(speeds, move_toward(from, to, delta / time))
	return entry.drawn


# True when the way from `from` to `to` (in points, `_steps_at()`) passes through a seam's blend.
func _crosses_seam(speeds: PackedFloat32Array, from: float, to: float) -> bool:
	var low := minf(from, to)
	var high := maxf(from, to)
	for index in range(speeds.size() - 1):
		var start := index + 1.0  # The slower gait's point, in points.
		if (
			high > start + 0.0001
			and low < start + 0.9999
			and _seam(speeds[index], speeds[index + 1])
		):
			return true
	return false


# True when the gaits at `slower` and `faster` m/s blend over no speeds of their own: the slower
# alone as far as the stretch lets it reaches the faster alone (to within a mm a second).
func _seam(slower: float, faster: float) -> bool:
	if not _matching() or settings == null:
		return false
	return absf(faster * settings.stretch.x - slower * settings.stretch.y) <= 0.001


# How many points a space whose gaits sit at `speeds` (the idle at 0) is past at position `at`:
# 1 at the first gait, 1.5 halfway to the second, and on past the last at its spacing from 0.
static func _steps_at(speeds: PackedFloat32Array, at: float) -> float:
	var below := 0.0
	for index in speeds.size():
		if at <= speeds[index]:
			return index + (at - below) / maxf(speeds[index] - below, 0.0001)
		below = speeds[index]
	return speeds.size() + (at - below) / maxf(below, 0.0001)


# The position `steps` points into a space whose gaits sit at `speeds` (`_steps_at()` undone).
static func _position_of(speeds: PackedFloat32Array, steps: float) -> float:
	var below := 0.0
	for index in speeds.size():
		if steps <= index + 1:
			return below + (steps - index) * (speeds[index] - below)
		below = speeds[index]
	return below + (steps - speeds.size()) * below


# True while the crouch space may be drawn: the body crouches (a crouch state is travelled to on
# the tick it does, and `CharacterAnimation` sets the tree before the tree runs), the machine is in
# it, or it was either within `CROUCH_HOLD`.
func _crouch_drawn(animation: CharacterAnimation, delta: float) -> bool:
	var body := animation.character
	if (
		set_undrawn
		or (body != null and body.crouching)
		or animation.body_state() == CharacterAnimation.CROUCH
	):
		_crouch_hold = CROUCH_HOLD
		return true
	_crouch_hold -= delta
	return _crouch_hold > 0.0


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
	# A one-dimensional space blends two gaits at most: the first two that weigh.
	var weights := gait_weights(entry.speeds, at)
	var first := -1
	var second := -1
	for index in weights.size():
		if weights[index] > 0.05:
			if first < 0:
				first = index
			elif second < 0:
				second = index
	if second < 0 or skeleton == null or delta <= 0.0 or not _matching() or speed < 0.5:
		_trim = move_toward(_trim, 1.0, delta)
		_trim_foot = ""
		return
	var share := phase(animation.tree, CharacterAnimation.GROUND)
	var one: StringName = entry.clips[first]
	var other: StringName = entry.clips[second]
	var foot := ""
	var side := 0
	for each: String in ["l", "r"]:
		if _down(one, each, share) and _down(other, each, share):
			foot = each
			side = 0 if each == "l" else 1
	if foot == "":
		_trim_foot = ""
		return
	if skeleton.get_instance_id() != _balls_of:
		_balls_of = skeleton.get_instance_id()
		_balls = PackedInt32Array([skeleton.find_bone("ball_l"), skeleton.find_bone("ball_r")])
	var bone := _balls[side]
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
		"drawn": -1.0,
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

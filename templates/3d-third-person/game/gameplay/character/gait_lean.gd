class_name GaitLean
extends RefCounted
## The lean of `CharacterAnimation` (gdstudio #1158): the body leans into its acceleration and its
## turns, from four lean poses added over the locomotion. A lean pose is a clip whose first frame
## is the pose leaning one way; what is added is its difference from the base pose (the idle's
## first frame), times how far the body leans that way: forward by its acceleration along its
## facing, back by its braking, left or right by its acceleration across (a turn at speed).
## The nodes sit between the body machine and the weapon layer, and are built only when every lean
## clip of `GaitSettings.lean_clips` is in the libraries: until the lean poses exist (gdstudio
## #1159) the tree has no lean and costs nothing for it. Cosmetic, never sent.
##
## The cost (gdstudio #1403): at most one way of each axis leans at a time (left or right, forward
## or back), so each axis takes its base off once, by an `AnimationNodeAdd2` at minus the axis's
## lean, before its two poses are added: the tree blends the same clips in the same order as one
## `AnimationNodeSub2` a way did, with two base nodes in place of four. The poses and the bases are
## blended from `LeanClips`, which keeps of each axis only the tracks its poses move off the base,
## and a parameter is set only when it changes. The lean is the same for every character at every
## distance, on screen or not.

## The ways the body leans, the node of each, and its axis and sign (x across, y along).
const WAYS: Dictionary[StringName, Vector3] = {
	&"left": Vector3(-1.0, 0.0, 0.0),
	&"right": Vector3(1.0, 0.0, 0.0),
	&"forward": Vector3(0.0, 1.0, 0.0),
	&"back": Vector3(0.0, -1.0, 0.0),
}
## The axis each way leans along: its node takes the base off for both of its ways.
const AXES: Dictionary[StringName, StringName] = {
	&"left": &"across", &"right": &"across", &"forward": &"along", &"back": &"along"
}
const BASE := "Base"
const ADD := "/add_amount"

var settings: GaitSettings
## The lean now, -1 to 1 each: x to the right, y forward.
var amount := Vector2.ZERO
var _built := false
var _velocity := Vector3.ZERO
var _primed := false
## The tree's parameters: each way's pose, then each axis's base (made once), and the value each
## was last given.
var _params: Array[StringName] = []
var _shown := PackedFloat64Array()


## True when the tree has the lean nodes.
func is_built() -> bool:
	return _built


## Puts the lean between `from` (the body machine) and input 0 of `to` in `root`, when it is on
## and every lean clip is in `player`'s libraries. `base` is the clip whose first frame the
## poses lean from.
func add_to(
	root: AnimationNodeBlendTree,
	from: StringName,
	to: StringName,
	player: AnimationPlayer,
	base: StringName
) -> void:
	_built = false
	if settings == null or not settings.lean or player == null or not player.has_animation(base):
		return
	for way: StringName in WAYS:
		if not player.has_animation(settings.lean_clips.get(way, &"")):
			return
	var clips := LeanClips.trimmed(player, base, settings.lean_clips, AXES)
	root.disconnect_node(to, 0)
	_params.clear()
	var axis_params: Array[StringName] = []
	var last := from
	var x := 600
	for way: StringName in WAYS:
		var axis := _node_name(AXES[way])
		if not root.has_node(axis):
			# A node's output feeds one input only: each axis has its own base.
			root.add_node(axis + BASE, _held(clips[AXES[way]]), Vector2(x, -600))
			root.add_node(axis, AnimationNodeAdd2.new(), Vector2(x + 100, 0))
			root.connect_node(axis, 0, last)
			root.connect_node(axis, 1, axis + BASE)
			axis_params.append(StringName("parameters/" + axis + ADD))
			last = axis
			x += 200
		var name := _node_name(way)
		root.add_node(name + "Pose", _held(clips[way]), Vector2(x, -400))
		root.add_node(name, AnimationNodeAdd2.new(), Vector2(x + 100, 0))
		root.connect_node(name, 0, last)
		root.connect_node(name, 1, name + "Pose")
		_params.append(StringName("parameters/" + name + ADD))
		last = name
		x += 200
	root.connect_node(to, 0, last)
	_params.append_array(axis_params)
	# A new tree starts every amount at 0; NAN differs from any value, so the first frame sets all.
	_shown.resize(_params.size())
	_shown.fill(NAN)
	_built = true


## Follows the body: its acceleration along and across its facing, through the lag of
## `lean_time`, into each way's amount.
func drive(tree: AnimationTree, body: Character, delta: float) -> void:
	if not _built or delta <= 0.0:
		return
	var velocity := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var accel := (velocity - _velocity) / delta if _primed else Vector3.ZERO
	_velocity = velocity
	_primed = true
	var forward := Vector3.BACK.rotated(Vector3.UP, body.facing)
	var right := forward.cross(Vector3.UP)
	# A turn is an acceleration across the way the body moves: the velocity turns with it.
	var goal := Vector2(accel.dot(right), accel.dot(forward)) / settings.lean_full_at
	goal = goal.clamp(-Vector2.ONE, Vector2.ONE)
	var share := clampf(delta / maxf(settings.lean_time, 0.001), 0.0, 1.0)
	amount = amount.lerp(goal, share)
	apply(tree, amount)


## Sets the tree's lean to `lean` (x to the right, y forward, -1 to 1 each): each way's pose by its
## share and each axis's base off by as much.
func apply(tree: AnimationTree, lean: Vector2) -> void:
	if not _built:
		return
	var index := 0
	for way: StringName in WAYS:
		var axis := WAYS[way]
		_put(tree, index, maxf(lean.x * axis.x + lean.y * axis.y, 0.0))
		index += 1
	_put(tree, index, -absf(lean.x))
	_put(tree, index + 1, -absf(lean.y))


func _put(tree: AnimationTree, index: int, value: float) -> void:
	if _shown[index] != value:
		_shown[index] = value
		tree.set(_params[index], value)


static func _node_name(way: StringName) -> String:
	return "Lean" + String(way).capitalize()


# The clip held on its first frame.
static func _held(clip: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	node.use_custom_timeline = true
	node.stretch_time_scale = false
	node.loop_mode = Animation.LOOP_NONE
	node.start_offset = 0.0
	node.timeline_length = 0.0
	return node

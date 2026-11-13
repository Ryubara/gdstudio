class_name GaitLean
extends RefCounted
## The lean of `CharacterAnimation` (gdstudio #1158): the body leans into its acceleration and its
## turns, from four lean poses added over the locomotion. A lean pose is a clip whose first frame
## is the pose leaning one way; what is added is its difference from the base pose (the idle's
## first frame), times how far the body leans that way: forward by its acceleration along its
## facing, back by its braking, left or right by its acceleration across (a turn at speed).
## The four nodes sit between the body machine and the weapon layer, and are built only when
## every lean clip of `GaitSettings.lean_clips` is in the libraries: until the lean poses exist
## (gdstudio #1159) the tree has no lean and costs nothing for it. Cosmetic, never sent.

## The ways the body leans, the node of each, and its axis and sign (x across, y along).
const WAYS: Dictionary[StringName, Vector3] = {
	&"left": Vector3(-1.0, 0.0, 0.0),
	&"right": Vector3(1.0, 0.0, 0.0),
	&"forward": Vector3(0.0, 1.0, 0.0),
	&"back": Vector3(0.0, -1.0, 0.0),
}
const BASE := "Base"

var settings: GaitSettings
## The lean now, -1 to 1 each: x to the right, y forward.
var amount := Vector2.ZERO
var _built := false
var _velocity := Vector3.ZERO
var _primed := false
## Whether the tree's differences have been set to take their base off whole: a new tree starts
## every `sub_amount` at 0, which adds the whole lean pose over the locomotion.
var _differences_set := false


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
	_differences_set = false
	if settings == null or not settings.lean or player == null or not player.has_animation(base):
		return
	for way: StringName in WAYS:
		if not player.has_animation(settings.lean_clips.get(way, &"")):
			return
	root.disconnect_node(to, 0)
	var last := from
	var x := 600
	for way: StringName in WAYS:
		var name := _node_name(way)
		var pose := AnimationNodeSub2.new()
		var add := AnimationNodeAdd2.new()
		root.add_node(name + "Pose", _held(settings.lean_clips[way]), Vector2(x, -400))
		root.add_node(name + "Diff", pose, Vector2(x, -200))
		root.add_node(name, add, Vector2(x + 100, 0))
		root.connect_node(name + "Diff", 0, name + "Pose")
		# A node's output feeds one input only: each difference has its own base.
		root.add_node(name + BASE, _held(base), Vector2(x, -600))
		root.connect_node(name + "Diff", 1, name + BASE)
		root.connect_node(name, 0, last)
		root.connect_node(name, 1, name + "Diff")
		last = name
		x += 200
	root.connect_node(to, 0, last)
	_built = true


## Follows the body: its acceleration along and across its facing, through the lag of
## `lean_time`, into each way's amount.
func drive(tree: AnimationTree, body: Character, delta: float) -> void:
	if not _built or delta <= 0.0:
		return
	if not _differences_set:
		for way: StringName in WAYS:
			tree.set("parameters/%sDiff/sub_amount" % _node_name(way), 1.0)
		_differences_set = true
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
	for way: StringName in WAYS:
		var axis := WAYS[way]
		var along := amount.x * axis.x + amount.y * axis.y
		tree.set("parameters/%s/add_amount" % _node_name(way), maxf(along, 0.0))


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

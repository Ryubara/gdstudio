# On the clock: a ruler is fixed work timed on the wall clock, the divisor of a cost gate.
class_name AnimationRuler
extends Node3D
## A fixed piece of the engine's animation work, timed beside a cost gate's measured frames, so the
## gate holds a timing as a ratio of work the machine did in the same seconds (kit
## docs/engines/godot/performance-budgets.md#reading-a-timing-on-a-shared-machine): an
## `AnimationTree` of its own blends three clips of a skeleton made here, advanced by hand, and the
## skeleton's poses are read after each advance, the native work a walking body's tree and
## skeleton spend a frame on. Everything is built in code, so no change to the template's clips,
## rig or tree moves it. Add it to the tree before timing; free it with the arena.

## Advances a timing.
const ROUNDS := 120
## Bones of the ruler's skeleton: four limbs of `LIMB` bones off a root.
const LIMBS := 4
const LIMB := 15
## Keys a clip's track, over a clip's second.
const KEYS := 30

var _tree: AnimationTree
var _skeleton: Skeleton3D
var _last_bone := 0
## The last pose read, kept so the reads are not idle work.
var _sink := Vector3.ZERO


func _ready() -> void:
	_skeleton = Skeleton3D.new()
	_skeleton.name = "Skeleton3D"
	_skeleton.add_bone("root")
	for limb in LIMBS:
		var parent := 0
		for index in LIMB:
			var bone := _skeleton.add_bone("b%d_%d" % [limb, index])
			_skeleton.set_bone_parent(bone, parent)
			_skeleton.set_bone_rest(bone, Transform3D(Basis(), Vector3(0.0, 0.1, 0.0)))
			parent = bone
	_last_bone = _skeleton.get_bone_count() - 1
	add_child(_skeleton)
	var library := AnimationLibrary.new()
	for clip in 3:
		library.add_animation(StringName("clip%d" % clip), _clip(clip))
	_tree = AnimationTree.new()
	_tree.add_animation_library(&"", library)
	var space := AnimationNodeBlendSpace1D.new()
	for clip in 3:
		var node := AnimationNodeAnimation.new()
		node.animation = StringName("clip%d" % clip)
		space.add_blend_point(node, clip - 1.0)
	_tree.tree_root = space
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	add_child(_tree)
	_tree.root_node = _tree.get_path_to(self)
	_tree.active = true


## Milliseconds the ruler takes now.
func measure_ms() -> float:
	var start := Time.get_ticks_usec()
	var spot := Vector3.ZERO
	for index in ROUNDS:
		_tree.set(&"parameters/blend_position", sin(index * 0.1))
		_tree.advance(1.0 / 60.0)
		spot += _skeleton.get_bone_global_pose(_last_bone).origin
	var spent := (Time.get_ticks_usec() - start) / 1000.0
	_sink = spot
	return spent


func _clip(seed_index: int) -> Animation:
	var clip := Animation.new()
	clip.length = 1.0
	clip.loop_mode = Animation.LOOP_LINEAR
	var root_track := clip.add_track(Animation.TYPE_POSITION_3D)
	clip.track_set_path(root_track, NodePath("Skeleton3D:root"))
	for key in KEYS:
		var at := float(key) / KEYS
		clip.position_track_insert_key(root_track, at, Vector3(0.0, sin(at * TAU) * 0.05, 0.0))
	for bone in range(1, _skeleton.get_bone_count()):
		var track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track, NodePath("Skeleton3D:" + _skeleton.get_bone_name(bone)))
		for key in KEYS:
			var at := float(key) / KEYS
			var angle := sin(at * TAU + bone * 0.3 + seed_index) * 0.4
			clip.rotation_track_insert_key(track, at, Quaternion(Vector3.RIGHT, angle))
	return clip

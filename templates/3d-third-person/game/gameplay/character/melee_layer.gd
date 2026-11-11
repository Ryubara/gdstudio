class_name MeleeLayer
extends RefCounted
## The melee blow's part of `CharacterAnimation`'s tree (gdstudio #1254): a one-shot on the upper
## body, over everything of the weapon layer, that plays the held weapon's category clips one
## after another, blow by blow, and says how much of the body it holds now (the weapon layer takes
## the left hand off the weapon and the finger off the trigger by it, so the clip swings the free
## arm). The `CharacterAnimation` owns one (`melee`) and plays it on `Weapon.melee_started`.

## The tree's nodes: the one-shot, its clip and the clip's speed.
const NODE := "Melee"
const CLIP := "MeleeClip"
const SCALE := "MeleeScale"
## Seconds a melee clip takes to come over the upper body, and to leave it.
const FADE_IN := 0.05
const FADE_OUT := 0.12

const _P_ACTIVE := StringName("parameters/%s/active" % NODE)
const _P_REQUEST := StringName("parameters/%s/request" % NODE)
const _P_SCALE := StringName("parameters/%s/scale" % SCALE)
const _P_FADING_IN := StringName("parameters/%s/fade_in_remaining" % NODE)
const _P_FADING_OUT := StringName("parameters/%s/fade_out_remaining" % NODE)
const _P_INSIDE := StringName("parameters/%s/internal_active" % NODE)

## The clip played last (`&""` before the first blow).
var clip: StringName = &""

var _clip_node: AnimationNodeAnimation


## Adds the one-shot to `root`: `below` (the weapon layer's last node) under it, the clip node
## `first` (the first blow's clip, or the idle with no weight) over it, filtered to `upper`.
func add_to(
	root: AnimationNodeBlendTree,
	below: StringName,
	upper: Array[NodePath],
	first: AnimationNodeAnimation
) -> void:
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = FADE_IN
	shot.fadeout_time = FADE_OUT
	shot.filter_enabled = true
	for path in upper:
		shot.set_filter_path(path, true)
	_clip_node = first
	root.add_node(CLIP, first, Vector2(1000, 1200))
	root.add_node(SCALE, AnimationNodeTimeScale.new(), Vector2(1200, 1200))
	root.add_node(NODE, shot, Vector2(1300, 0))
	root.connect_node(SCALE, 0, CLIP)
	root.connect_node(NODE, 0, below)
	root.connect_node(NODE, 1, SCALE)


## The clip a tree is built with for `hold`: its first blow's, or `&""` (the idle, no weight).
static func first_clip(hold: WeaponDef) -> StringName:
	var clips: Array[StringName] = hold.blow_clips() if hold != null else [] as Array[StringName]
	return clips[0] if not clips.is_empty() else &""


## Plays blow `blow` of the held weapon's clips (its category's, `WeaponDef.blow_clips()`) on
## `animation`'s tree at their speed; nothing when it has none or the player lacks the clip.
func play(blow: int, animation: CharacterAnimation) -> void:
	var hold := animation.held_definition()
	var tree := animation.tree
	if hold == null or _clip_node == null or tree == null or animation.animation_player == null:
		return
	var clips := hold.blow_clips()
	if clips.is_empty():
		return
	var next := clips[posmod(blow, clips.size())]
	if not animation.animation_player.has_animation(next):
		return
	clip = next
	_clip_node.animation = next
	tree.set(_P_SCALE, hold.blow_clip_speed())
	tree.set(_P_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## True while a melee clip plays over the upper body of `tree`.
func is_active(tree: AnimationTree) -> bool:
	return tree != null and tree.tree_root != null and tree.get(_P_ACTIVE)


## How much of the upper body the clip holds now (0 none, 1 all of it: it fades in and out).
func share(tree: AnimationTree) -> float:
	if not is_active(tree):
		return 0.0
	var weight := 1.0 - float(tree.get(_P_FADING_IN)) / FADE_IN
	if not tree.get(_P_INSIDE):
		weight = float(tree.get(_P_FADING_OUT)) / FADE_OUT
	return clampf(weight, 0.0, 1.0)

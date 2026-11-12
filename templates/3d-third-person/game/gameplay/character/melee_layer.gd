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
# A blow was asked for and the tree has not said it ended: only then is the tree read (a read of
# a tree parameter is a lookup every frame, for every character).
var _playing := false
var _seen := false
# The weapon whose blows this plays (connected once).
var _heard: Weapon
# The body's aim is up for a blow alone: from the blow's start until that aim has come down again.
var _blow_aim := false


## Adds the one-shot to `root`: `below` (the weapon layer's last node) under it, the clip node
## `first` (the first blow's clip, or the idle with no weight) over it, filtered to `upper`; and
## plays a blow of `animation`'s character's weapon (`Weapon.melee_started`) from then on.
func add_to(
	animation: CharacterAnimation,
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
	var weapon := animation.character.weapon if animation.character != null else null
	# Once a weapon: the tree is built again on every change of the held definition.
	if weapon != null and weapon != _heard and not Engine.is_editor_hint():
		weapon.melee_started.connect(play.bind(animation))
		_heard = weapon


## The clip a tree is built with for `hold`: its first blow's, or `&""` (the idle, no weight).
static func first_clip(hold: WeaponDef) -> StringName:
	if hold == null or hold.blow_clips().is_empty():
		return &""
	return hold.blow_clips()[0]


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
	_playing = true
	_seen = false


## The aim the weapon layer shows for `body`: its `aim_amount`, or 0 while that aim is up only for
## a blow. A blow turns the body the way it goes as an aim does (`Character.aiming`), but it raises
## no aim pose: with one, the aim offset turned the spine to point the carried pistol at the aim
## for the frames before the clip held the body and after it let go, and the body folded back
## (66 degrees at the chest; gdstudio #1254, pull request #1315).
func aim_of(body: Character) -> float:
	var real := body.aim_held or body.fire_held
	if real or body.aim_amount <= 0.0:
		_blow_aim = false
	if body.weapon != null and body.weapon.meleeing and not real:
		_blow_aim = true
	return 0.0 if _blow_aim else body.aim_amount


## The weapon layer's two weights (`CharacterAnimation.pistol_weights`) from the tree's `armed`
## and `aim` parameters: the aim is taken away as the blow holds the upper body, so the left hand
## leaves the weapon and the finger the trigger while the clip swings the free arm.
func weigh(tree: AnimationTree, armed: StringName, aim: StringName) -> Vector2:
	return Vector2(tree.get(armed), float(tree.get(aim)) * (1.0 - share(tree)))


## True while a melee clip plays over the upper body of `tree`.
func is_active(tree: AnimationTree) -> bool:
	if not _playing or tree == null or tree.tree_root == null:
		return false
	var active: bool = tree.get(_P_ACTIVE)
	# Ended only once it was seen playing: the request is taken on the tree's next process.
	_seen = _seen or active
	_playing = active or not _seen
	return active


## How much of the upper body the clip holds now (0 none, 1 all of it: it fades in and out).
func share(tree: AnimationTree) -> float:
	if not is_active(tree):
		return 0.0
	var weight := 1.0 - float(tree.get(_P_FADING_IN)) / FADE_IN
	if not tree.get(_P_INSIDE):
		weight = float(tree.get(_P_FADING_OUT)) / FADE_OUT
	return clampf(weight, 0.0, 1.0)

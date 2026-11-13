class_name HitLayer
extends RefCounted
## Where a hit's clip plays on the body. The hit clip (`CharacterClips.HIT`) is made standing and
## empty-handed, so it holds the whole body only in a standing body state with nothing in the
## hands. Crouched, lying or sliding it plays on the upper body alone (the bones from
## `CharacterAnimation.upper_body_bone` down) and the hips and legs keep the state's pose, so a
## crouched body under fire stays down (gdstudio #1292). With a weapon held (the weapon layer's
## grip on), it leaves the arms out (the clavicles down), so they keep holding and aiming the
## weapon while the trunk and head take the hit; before, the clip's empty-handed arms dropped the
## pistol to the hip for the whole stun (gdstudio #1345). It is the action one-shot's filter, set
## for a hit and off for every other action but an upper-body one (`UseLayer`: the upper body less
## the right arm, `Part.USE`). `CharacterAnimation` owns one (`hits`).

## The share of the action that plays a hit, as `part_for()` names it.
enum Part { WHOLE, UPPER, WHOLE_BUT_ARMS, UPPER_BUT_ARMS, USE }

## The body states whose hit plays on the upper body only.
const UPPER_BODY_STATES: Array[StringName] = [
	CharacterAnimation.CROUCH,
	CharacterAnimation.PRONE,
	CharacterAnimation.SLIDE_START,
	CharacterAnimation.SLIDE,
	CharacterAnimation.SLIDE_EXIT,
]

var _whole: Array[NodePath] = []
var _upper: Array[NodePath] = []
var _arms: Array[NodePath] = []
var _kept: Array[NodePath] = []
var _part := Part.WHOLE


## True when a hit in the body state `state` plays on the upper body only.
static func upper_body_only(state: StringName) -> bool:
	return UPPER_BODY_STATES.has(state)


## The part of the body a hit plays on in body state `state`, with a weapon held (`armed`) or not.
static func part_for(state: StringName, armed: bool) -> Part:
	if upper_body_only(state):
		return Part.UPPER_BUT_ARMS if armed else Part.UPPER
	return Part.WHOLE_BUT_ARMS if armed else Part.WHOLE


## Takes the bones' tracks the parts are made of (`whole`: every bone; `upper`: the upper body;
## `arms`: both arms from the clavicles; `kept`: the arm an upper-body action leaves on the layers
## under it, `UseLayer.KEPT_ARM` down) and leaves `action`'s filter off until a hit.
func prepare(
	action: AnimationNodeOneShot,
	whole: Array[NodePath],
	upper: Array[NodePath],
	arms: Array[NodePath],
	kept: Array[NodePath] = []
) -> void:
	_whole = whole
	_upper = upper
	_arms = arms
	_kept = kept
	_part = Part.WHOLE
	action.filter_enabled = false


## The part of the action `tree`'s one-shot plays now (`Part.WHOLE` while its filter is off).
func part() -> Part:
	return _part


## Sets the filter of `tree`'s action one-shot for a hit that plays (`hit`) in body state `state`,
## with a weapon held (`armed`) or not, or for an upper-body action (`upper_body`, `UseLayer`), and
## turns it off for every other action: called when a hit lands and every frame after, so a body
## that crouches, stands up or puts its weapon away during the stun gets the share of the clip its
## new state takes. The paths are written only on a change.
func follow(
	tree: AnimationTree, hit: bool, state: StringName, armed: bool, upper_body: bool = false
) -> void:
	var root := tree.tree_root as AnimationNodeBlendTree if tree != null else null
	if root == null or not root.has_node(&"Action"):
		return
	var action := root.get_node(&"Action") as AnimationNodeOneShot
	if action == null:
		return
	var wanted := Part.WHOLE
	if hit:
		wanted = part_for(state, armed)
	elif upper_body:
		wanted = Part.USE
	if wanted == _part and action.filter_enabled == (wanted != Part.WHOLE):
		return
	_part = wanted
	action.filter_enabled = wanted != Part.WHOLE
	if wanted == Part.WHOLE:
		return
	var upper := wanted in [Part.UPPER, Part.UPPER_BUT_ARMS, Part.USE]
	var but_arms := wanted == Part.WHOLE_BUT_ARMS or wanted == Part.UPPER_BUT_ARMS
	for path in _whole:
		var on := (not upper or _upper.has(path)) and not (but_arms and _arms.has(path))
		on = on and not (wanted == Part.USE and _kept.has(path))
		action.set_filter_path(path, on)

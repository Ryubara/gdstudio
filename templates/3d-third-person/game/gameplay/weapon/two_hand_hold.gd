@tool
class_name TwoHandHold
extends Node3D
## How a character holds a long gun with both hands when the animation library has no clip for it
## (the Universal Animation Library has pistol clips only): the gun sits with its butt in the right
## shoulder's pocket, low and across the body at rest and at the shoulder along the view when the
## character aims or shoots, the chest turns the left shoulder forward so the left arm reaches, each
## arm reaches its hand's place on the gun, and the fingers close on it: the right hand on the
## pistol grip with the index finger along the receiver (on the trigger while the gun is up), the
## left hand cupped under the hand guard. Both hands stay on the gun in every state; only a reload
## takes the left hand away, to the magazine and the belt and back by the charging handle
## (`ChargePull`, kit #1266), and an action that reaches with it (using a door: `FreeHand`, kit
## #1336), for which the gun goes down in the right hand alone. A melee blow's clip carries the
## rifle in both hands while it plays (`HoldBlow`). The legs and the head stay on the locomotion
## clips. `two_hand_hold.tscn` is the part with no gun; the rifle's
## `gameplay/weapon/rifle_held.tscn` inherits it and puts the rifle and the hands' places under
## `Pivot`.
##
## The parts a person tunes are scene nodes: `Pivot` (the shoulder's pocket, which this node moves
## and turns), the gun under it, the hands' places on the gun (`RightHandTarget`,
## `LeftHandTarget` and `MagazineHand`, where each hand's bone sits: written with the finger poses
## by `tools/hold/solve_rifle_hold.py`, so the skin meets the gun) and the elbows' pole markers
## (`RightPole`, `LeftPole`, in the model's space). The modifiers that bend the arms and close the
## fingers are made at run time on the model's skeleton (they belong to whatever model the
## `CharacterModel` slot holds): the stance (`TwoHandStance`: places the pocket, turns the chest,
## hands each arm its place of this update), a `HoldArm` per arm and a `HandPoseModifier` per hand.
##
## A switch is one sequence with the loadout's own times. Going away, the gun goes down to its
## `stow` place with both hands on it and is hidden there, in the tick the next weapon appears in
## the right hand, and the arms go from the gun's places to the next weapon's pose while that one
## comes up. Coming out, the arms go to the stow place while the last weapon goes down, the gun
## appears in the hands there and comes up. So no frame shows the gun without the hands on it.
##
## It is a child of the character's `Model` slot, shown by the `WeaponLoadout` while its weapon is
## in the hands (the definition's `view`). The pose is cosmetic: it is worked out on each machine
## from what the character already has (`aim_amount`, `view_pitch`, the weapon's shots and reload,
## the loadout's switch) and never sent. With no `character` (a figure posed by hand: a test, a
## capture) the `posed_` values are the caller's.

const STANCE_SCRIPT := preload("res://gameplay/weapon/two_hand_stance.gd")
const _MODIFIER_PREFIX := "TwoHandHold_"
## The share of a magazine's way out of the gun that is straight down the magazine well.
const _WELL_SHARE := 0.4
## The left hand's way from the hand guard to the magazine, as shares of it: its four fingers
## open by the first (the knuckles over its first half, then the rest, as the hand starts down),
## it is off the hand guard by the second, beside the magazine by the third and on it by the
## fourth; the fingers close on the magazine after that.
const _WAY_OPEN := 0.1
## How far the left hand drops while its knuckles open, before it moves off the hand guard.
const _LET_GO_DROP := 0.006
## What a finger's first bone (the knuckle's) has in its name: those open first.
const _KNUCKLE := "_01_"
const _WAY_DOWN := 0.3
## The shares of that way over which the thumb goes from its place on the hand guard to its place
## behind the magazine.
const _WAY_THUMB := Vector2(0.2, 0.5)
const _WAY_BESIDE := 0.7
const _WAY_ON := 0.88
## The share of a freed hand's way off the gun that takes it down under the hand guard (the
## reload's own first steps); over the rest it goes out to `free_clearance`.
const _FREE_DOWN := 0.6
## How many times at most the left shoulder is brought to the hand guard and the butt to the skin
## in one frame.
const _PASSES := 3
## How far the push to the skin may move in a frame before the shoulder's reach is worked out
## again for it, in metres.
const _PUSH_STEP := 0.003

@export_group("Nodes")
## The character holding it. Empty: the `Model` slot's parent.
@export var character: Character

@export_group("Stance")
## Where the butt sits when aiming, from the chest bone (`chest_bone`) in the chest's frame (+Z
## its front, +X its left, turned with the chest about the up axis and `pocket_lean` of its lean):
## the right shoulder's pocket, a little inside the skin, since the gun then goes forward along its
## barrel until the butt is on the skin (`butt_pad`). The chest's place comes from the clip, so a
## crouch or a lean carries the gun with it.
@export var aim_pocket := Vector3(-0.16, 0.11, 0.08)
## Where it sits at rest (the low ready).
@export var low_pocket := Vector3(-0.16, 0.1, 0.08)
## How far the muzzle points down at rest.
@export_range(0.0, 80.0, 0.5, "suffix:deg") var low_pitch := 35.0
## How far the muzzle points across the body at rest (toward the left). More lies the stock along
## the chest; less leaves the left hand farther from the hand guard.
@export_range(-60.0, 60.0, 0.5, "suffix:deg") var low_yaw := 10.0
## How far the chest stands turned from the model's front, about its up axis, split over the
## spine bones; negative brings the left shoulder forward so the left hand reaches the fore-end.
## The clip's own turn of the chest is taken off, so the shoulders keep this in a walk or a run.
@export_range(-60.0, 60.0, 0.5, "suffix:deg") var chest_turn := -30.0
## The most the chest leans (from its rest, the way the clip has it) while the gun is up: a chest
## that leans more (a crouch's hunch) is raised toward this as the gun comes to the shoulder.
@export_range(0.0, 90.0, 0.5, "suffix:deg") var aim_lean_limit := 25.0
## The most the trunk leans forward on average (the line from the pelvis to the neck, in the
## model's space) at the low ready while the character runs on its feet (`HoldCarry.STATES`,
## from the walk's speed to the run's): a run or a sprint that leans more is raised toward this,
## so the rifle is carried upright (kit #1348; the run leaned 13 degrees and the sprint 14). Not
## standing or walking, in a crouch, a slide, a vault or lying down.
@export_range(0.0, 90.0, 0.5, "suffix:deg") var carry_lean_limit := 9.0
## How long the upright carry takes to come in or go (a crouch, a slide), in seconds.
@export_range(0.0, 2.0, 0.01, "suffix:s") var carry_time := 0.25
## `butt_margin` while carried upright (`carry_amount()`): at 1 cm the straightened spine put the
## male's butt corner 10 mm in the chest, between two `skin_spacing` points; none at 2 cm.
@export_range(0.0, 0.05, 0.001, "suffix:m") var carry_butt_margin := 0.02
## The most of its length the left arm stretches to. When the hand guard is farther than that
## from the left shoulder (a clip leans or drops the shoulder), the gun comes back along its
## barrel until the hand reaches, by `pull_limit` at most.
@export_range(0.5, 1.0, 0.005) var arm_stretch := 0.97
@export_range(0.0, 0.3, 0.005, "suffix:m") var pull_limit := 0.0
## The butt's width and height, centred on `Pivot` (the butt's place), and how far along the
## barrel the stock keeps them: the gun goes forward from the pocket until no point of the torso's
## skin is inside that box, so the pockets may be given a little inside the chest.
@export var butt_pad := Vector2(0.062, 0.145)
@export_range(0.0, 0.4, 0.005, "suffix:m") var butt_depth := 0.16
## How far off the skin the butt stays (the skin points ride one bone each, so they are a few
## millimetres off the drawn skin near a joint).
@export_range(0.0, 0.03, 0.001, "suffix:m") var butt_margin := 0.01
## How much of the barrel's fall the butt's way to the skin leaves out while the muzzle is down
## (1: it comes level out of the pocket; 0: along the barrel). Along the barrel, a steep aim down
## slid the butt down the chest and 10 cm off the shoulder before it was clear (kit #1346).
@export_range(0.0, 1.0, 0.01) var push_level := 1.0
## The torso's skin is thinned to one point in each cell this size.
@export_range(0.005, 0.1, 0.005, "suffix:m") var skin_spacing := 0.03
## The most the left collarbone turns to bring the shoulder toward the hand guard when the arm
## alone would be over `arm_stretch` of its length; what is still short then brings the gun back.
@export_range(0.0, 75.0, 0.5, "suffix:deg") var reach_turn := 55.0
## The most the gun follows the view up or down.
@export_range(0.0, 89.0, 0.5, "suffix:deg") var pitch_limit := 60.0
## Seconds from the low ready to the shoulder (and back).
@export_range(0.01, 2.0, 0.01, "suffix:s") var raise_time := 0.15
## Seconds the gun stays at the shoulder after a shot fired from the low ready.
@export_range(0.0, 3.0, 0.05, "suffix:s") var shot_hold_time := 0.6

@export_group("Switch")
## Where the butt is when the gun is all the way down in a switch (the place it is hidden and
## shown at), from the chest bone like `low_pocket`: both hands still reach it there.
@export var stow_pocket := Vector3(-0.16, 0.08, 0.08)
## How far the muzzle points down there, and across the body.
@export_range(0.0, 89.0, 0.5, "suffix:deg") var stow_pitch := 40.0
@export_range(-60.0, 60.0, 0.5, "suffix:deg") var stow_yaw := 10.0

@export_group("Free hand")
## How far the muzzle points down, and across the body, while the left hand is away for an action
## that reaches with it (using a door or a lever: `FreeHand`): the gun in the right hand alone,
## its butt still in the shoulder's pocket, lower than the low ready and out of the left arm's way.
@export_range(0.0, 89.0, 0.5, "suffix:deg") var free_pitch := 50.0
@export_range(-60.0, 60.0, 0.5, "suffix:deg") var free_yaw := 0.0
## Where the opened left hand goes from under the hand guard before the action's arm takes it,
## and where it comes back to, from its place on the gun in the gun's space: down and well out to
## the left, so its way to and from a reach in front goes beside the gun and never through it.
@export var free_clearance := Vector3(0.0, -0.1, 0.14)
## Seconds the left hand takes off the hand guard to the action's arm (its fingers open and it
## drops clear over the first half), and back from it, ending as the action ends.
@export_range(0.01, 1.0, 0.01, "suffix:s") var free_release_time := 0.16
@export_range(0.01, 1.0, 0.01, "suffix:s") var free_return_time := 0.26

@export_group("Recoil")
## How far a shot pushes the gun back along the barrel.
@export_range(0.0, 0.2, 0.001, "suffix:m") var kick_distance := 0.02
## How far a shot tips the muzzle up.
@export_range(0.0, 20.0, 0.1, "suffix:deg") var kick_degrees := 2.0
## Seconds for the gun to come back from a kick.
@export_range(0.01, 1.0, 0.01, "suffix:s") var kick_recover_time := 0.08

@export_group("Hands")
## The right hand's fingers on the grip, the index finger straight along the receiver.
@export var grip_pose: HandPose
## The index finger on the trigger, blended over `grip_pose` as the gun comes up to the shoulder.
@export var trigger_pose: HandPose
## The poses the index finger passes through between `grip_pose` and `trigger_pose`, round the
## trigger guard (kit #1036). None: the straight way.
@export var trigger_way: HandPoseWay
## The left hand's fingers cupped under the hand guard.
@export var support_pose: HandPose
## The left hand's four fingers opened, as it lets go of the gun and comes back to it (the thumb
## keeps the pose under it).
@export var open_pose: HandPose
## The left hand's fingers round the magazine.
@export var magazine_pose: HandPose
## The left hand's fingers hooked on the charging handle (`charge`). None: no pull.
@export var charge_pose: HandPose

## Past this distance from the camera the fingers keep the clip's fist (the hands are a few
## pixels there; the rifle's far level shows from 10 m). 0: always posed. The hold reads no
## camera (a server has none): the animation throttle, which measures every character's distance,
## sets `fingers_far`.
@export_range(0.0, 100.0, 0.5, "suffix:m") var fingers_far_distance := 10.0

@export_group("Reload")
## Where the left hand takes the magazine to during a reload: the belt at the left hip, from the
## chest bone in the model's space like the pockets (a place the left arm reaches in every clip).
@export var reload_belt := Vector3(0.17, -0.3, 0.1)
## How far the magazine comes straight down out of the gun before it goes to the belt, along the
## gun's own up axis.
@export_range(0.0, 0.3, 0.005, "suffix:m") var magazine_well := 0.1
## How far the left hand comes off the hand guard before it goes to the magazine (and where it
## comes back to before it goes onto it), in the gun's space: down, and out to the left, the
## thumb's side, since the thumb stays as it lies up the hand guard's left side.
@export var reload_clearance := Vector3(0.0, -0.07, 0.035)
## Where the left hand is beside the magazine before it closes on it, from its place on it, in
## the gun's space: out to the left, so the open fingers pass in front of the magazine.
@export var magazine_approach := Vector3(0.0, 0.0, 0.07)
## The shares of the reload between which the left hand goes from the hand guard to the magazine.
@export var reload_leave := Vector2(0.0, 0.18)
## The shares between which it takes the magazine out and down to the belt.
@export var reload_out := Vector2(0.2, 0.42)
## The shares between which it brings the new magazine up and in.
@export var reload_in := Vector2(0.48, 0.62)
## The shares between which it goes back to the hand guard.
@export var reload_return := Vector2(0.66, 0.86)
## The magazine node under the gun that leaves with the left hand. Empty: none moves.
@export var magazine: NodePath
## The far level's magazine, moved and hidden with it. Empty: none.
@export var magazine_far: NodePath
## The charging handle's pull after the magazine is seated (kit #1266): the left hand goes from
## the magazine to the `ChargeHand` marker, pulls the `bolt` node back and lets it go, then comes
## back under the hand guard by `reload_return`. None (or no `ChargeHand`): straight back.
@export var charge: ChargePull
## The bolt node under the gun the pull moves, and the far level's. Empty: none moves.
@export var bolt: NodePath
@export var bolt_far: NodePath

@export_group("Bodies")
## Holds solved on other bodies than the one the scene's own hands' places and poses were solved
## on (`HoldFit`, written by `tools/hold/write_hold.gd ... rifle <body>`): a model whose file is a
## fit's `body` gets that fit's places (`seat` is the inverse of `RightHandTarget`) and poses; any
## other model the scene's own.
@export var fits: Array[HoldFit] = []

@export_group("Bones")
## The bone whose place the pockets are given from, and the reload's belt.
@export var chest_bone: StringName = &"spine_03"
## How far the pockets lean with the chest bone (its turn from its rest, less its turn about the up
## axis, which they always take): a chest that leans forward in a crouch takes the butt's place on
## its skin with it.
@export_range(0.0, 1.0, 0.01) var pocket_lean := 0.5
## The bones whose skin is the torso the butt comes to (`butt_pad`).
@export var torso_bones: Array[StringName] = [
	&"spine_01", &"spine_02", &"spine_03", &"clavicle_l", &"clavicle_r"
]
## The left collarbone, which brings the left shoulder toward the hand guard when the arm alone is
## short (`reach_turn`).
@export var left_clavicle: StringName = &"clavicle_l"
## The bones the chest turn spreads over.
@export var spine_bones: Array[StringName] = [&"spine_01", &"spine_02", &"spine_03"]
## The right arm: upper arm, forearm, hand.
@export var right_arm: Array[StringName] = [&"upperarm_r", &"lowerarm_r", &"hand_r"]
## The left arm.
@export var left_arm: Array[StringName] = [&"upperarm_l", &"lowerarm_l", &"hand_l"]

## For a figure posed by hand (no `character`): how far the gun is up at the shoulder, the view's
## pitch in degrees, how far a reload is (below 0: none) and how far a switch has it down.
var posed_aim := 0.0
var posed_pitch := 0.0
var posed_reload := -1.0
var posed_lowered := 0.0
## For a figure posed by hand: how far the left hand is let go (`FreeHand.amount()`).
var posed_free := 0.0
## For a figure posed by hand: how far the trunk is carried upright (`carry_amount()`).
var posed_carry := 0.0
## How much of the upper body a melee blow's clip holds, for a figure posed by hand (`HoldBlow`).
var posed_blow := 0.0
## True while the camera is past `fingers_far_distance` (set by `CharacterAnimationThrottle`).
var fingers_far := false

var _skeleton: Skeleton3D
var _modifiers: Array[SkeletonModifier3D] = []
var _stance: SkeletonModifier3D
var _arms: Array[HoldArm] = []
var _fingers: Array[HandPoseModifier] = []
var _raised := 0.0
var _shot_left := 0.0
var _kick := 0.0
var _reach := 1.0
var _down := 0.0
var _leaving := false
# The left hand let go for an action that reaches with it, and how far it is gone this frame.
var _free := FreeHand.new()
var _blow := HoldBlow.new()
# How far the trunk is carried upright, before the hold's own shares (`carry_amount()`).
var _carry := HoldCarry.new()
var _hand_index := -1
var _freed := 0.0
var _chest := Vector3.ZERO
var _left_rest := Transform3D.IDENTITY
var _magazine_rest := Transform3D.IDENTITY
# The torso's skin the butt meets, thinned and grouped by bone (`TorsoSkin`).
var _skin := TorsoSkin.new()
# The push of the last frame it was measured.
var _push := 0.0
var _weapon: Weapon
var _loadout: WeaponLoadout
# The scene's parts and the bones, found once (`_find_parts()`, `_find_bones()`) rather than
# looked up every frame (kit #1178).
var _pivot: Node3D
var _gun: Node3D
var _targets: Array[Node3D] = [null, null]
var _poles: Array[Node3D] = [null, null]
var _on_magazine: Node3D
var _on_handle: Node3D
var _bolt := ChargeBolt.new()
var _mag: Node3D
var _mag_far: Node3D
var _chest_index := -1
var _chest_rest_turn := Basis.IDENTITY
var _clavicle_index := -1
var _spine_indices := PackedInt32Array()
var _left_indices := PackedInt32Array()
# What was last written to the modifiers and to `Pivot`'s visibility (-1: never), so a frame
# writes only what changed (kit #1347).
var _weights := HoldWeights.new()
var _pivot_shown := -1
# The left forearm's and hand's length this update; the low ready's turn and what it was worked
# out from.
var _arm := 0.0
# Whether the skeleton has every bone `left_arm` names (three, or more).
var _left_found := false
var _low_key := Vector2(NAN, NAN)
var _low_turn := Quaternion.IDENTITY
var _aim_key := Vector2(NAN, NAN)
var _aim_turn := Quaternion.IDENTITY
# The parents and the spine's top pose the poses are worked out from (kit #1347).
var _bones := HoldBones.new()
# Whether the left hand and the magazine are at rest already (nothing to write outside a reload).
var _hand_at_rest := false
# The weapon definition this hold is the view of, looked for again when the slots change.
var _mine: WeaponDef
var _mine_slots := -1
# The scene's own hold as a fit, kept before a body's fit is first put on.
var _own: HoldFit


func _ready() -> void:
	_find_parts()
	if _targets[1] != null:
		_left_rest = _targets[1].transform
	if _mag != null:
		_magazine_rest = _mag.transform
	if Engine.is_editor_hint():
		set_process(false)
		return
	if character == null and get_parent() != null:
		character = get_parent().get_parent() as Character
	var slot := get_parent() as CharacterModel
	if slot != null:
		slot.rig_changed.connect(_on_rig_changed.unbind(1))
	if character != null:
		_weapon = character.weapon
		_loadout = character.loadout
		character.interacted.connect(free_hand_for_interact.unbind(1))
		if _weapon != null:
			_weapon.fired.connect(_on_fired.unbind(1))
		if _loadout != null:
			_loadout.slots_changed.connect(_forget_definition)
			_loadout.weapon_changed.connect(_on_weapon_changed)
			_loadout.switch_finished.connect(_on_switch_finished.unbind(1))
	_on_rig_changed.call_deferred()


func _exit_tree() -> void:
	_drop_modifiers()


func _process(delta: float) -> void:
	_step(delta)
	refresh()


## How far the gun is up at the shoulder: 0 at the low ready, 1 aimed.
func raised_amount() -> float:
	return _raised


## How far the trunk is carried upright now (`carry_lean_limit`): 1 running at the low ready, 0
## standing, aimed, crouched, sliding, vaulting or lying down, eased over `carry_time`, by the
## hold's weight; none while a melee blow's clip has the upper body (`HoldBlow`).
func carry_amount() -> float:
	return _carry.amount * (1.0 - _raised) * weight() * (1.0 - _blow.amount)


## How much of the upper body a melee blow's clip holds now: by as much the rifle rides the clip's
## right hand and the hold's own turns ease off (`HoldBlow`, gdstudio #1288).
func blow_amount() -> float:
	return _blow.amount


## How far the left hand is let go for an action that reaches with it (`FreeHand.amount()`).
func free_amount() -> float:
	return _freed


## Lets the left hand go for an action of `seconds` that reaches with it (the gun goes down in
## the right hand); a reload keeps the hand. The character's `interacted` does it by itself.
## With `by` above 0 the hand is off within that many seconds (a vault's hand plant).
func free_hand(seconds: float, by := -1.0) -> void:
	if visible and _reload_progress() < 0.0:
		_free.release_time = minf(free_release_time, by) if by > 0.0 else free_release_time
		_free.return_time = free_return_time
		_free.start(seconds)


## The character used something: the interact clip reaches with the left hand.
func free_hand_for_interact() -> void:
	free_hand(character.tuning.interact_time)


## The action the hand was let go for ended early (a use cut short): the hand comes back onto the
## weapon its own way, from wherever it is.
func take_hand_back() -> void:
	_free.finish()


## How far the arms are on the gun's places: 1 while the gun is in the hands, and the way there
## or away while a switch brings it out or has just put it away.
func reach_amount() -> float:
	return _reach


## The skeleton modifiers this hold made: the stance, each arm's reach, each hand's fingers.
func modifiers() -> Array[SkeletonModifier3D]:
	return _modifiers.duplicate()


## How far each hand's bone stopped from its place on the gun on the last update, in metres (an
## arm too short for the stance): x the right hand, y the left.
func shortfall() -> Vector2:
	if _arms.size() < 2:
		return Vector2.ZERO
	return Vector2(_arms[0].shortfall, _arms[1].shortfall)


## Puts the weights on the modifiers now (the frame's own `_process` does it too).
func refresh() -> void:
	# The calls a frame are few (kit #1347): a figure posed by hand has its values at hand.
	var posed := character == null or _loadout == null
	_reach = 1.0 if posed else _reach_now()
	_down = posed_lowered if posed else _down_now()
	var alive := character == null or not character.is_dead()
	var shown := alive and is_visible_in_tree()
	if is_instance_valid(_pivot) and _pivot_shown != int(alive):
		_pivot.visible = alive
		_pivot_shown = int(alive)
	var far := fingers_far and fingers_far_distance > 0.0
	var fingers := 1.0 if shown and not far else 0.0
	# Both arms go to the clip while the gun is put away for an action (a high vault: gdstudio
	# #1409), the left one alone while an action reaches with it.
	_weights.weigh(_modifiers, alive, _reach, fingers, _freed, _blow.amount, not shown)
	if _fingers.size() < 2:
		return
	# The finger is on the trigger while the gun is up, and off it through a reload.
	var reload := posed_reload if character == null else _reload_progress()
	var trigger := _raised if reload < 0.0 else 0.0
	var to_magazine := _to_magazine(reload) if reload >= 0.0 else 0.0
	if _freed > 0.0:
		to_magazine = maxf(to_magazine, _let_go())
	# The thumb goes from the hand guard's side to its place behind the magazine while the hand
	# comes down off the hand guard (the open pose leaves it be): a thumb still standing up
	# on the way across went 17 mm through the magazine well. The four fingers stay open until
	# the hand is on the magazine, then close as one: closing tips first, as they open off the
	# hand guard, swung the little finger 8 mm through the magazine's front.
	var thumb := smoothstep(_WAY_THUMB.x, _WAY_THUMB.y, to_magazine)
	var together := to_magazine > _WAY_DOWN
	var opened := (
		smoothstep(0.0, _WAY_OPEN, to_magazine) * (1.0 - smoothstep(_WAY_ON, 1.0, to_magazine))
	)
	var left := Vector4(thumb, opened, float(together), 0.0)
	if _charging():
		left = charge.finger_weights(reload, left)
	_weights.hands(_fingers[0], _fingers[1], trigger, left.x, left.y, left.z > 0.5, left.w)


## Puts the pocket and the gun where they are this frame, and gives each arm its hand's place.
## The stance modifier calls it while the skeleton updates, when the chest bone has the clip's
## pose of this frame. Every pose comes from the local ones up the parents and every node's place
## from the transforms up to this node: nothing asks the engine to work out a global one.
## `spine_top`: the pose of the last of `spine_bones` in the skeleton's space, when `has_top` (the
## stance has it from its turn, kit #1347): the chest and the left shoulder are then worked out
## from it, not from every pose up to the root.
func place(skeleton: Skeleton3D, spine_top := Transform3D(), has_top := false) -> void:
	if not is_instance_valid(_pivot) or not is_instance_valid(_gun):
		_find_parts()
		if _pivot == null:
			return
	_bones.top = _spine_indices[-1] if has_top and not _spine_indices.is_empty() else -1
	_bones.top_pose = spine_top
	_arm = 0.0
	if _left_found:
		_arm = skeleton.get_bone_pose_position(_left_indices[1]).length()
		_arm += skeleton.get_bone_pose_position(_left_indices[2]).length()
	var chest := Vector3.ZERO
	var to_here := global_transform.affine_inverse() * skeleton.global_transform
	var chest_turned := Basis.IDENTITY
	if _chest_index >= 0:
		var chest_pose := spine_top
		if _bones.top != _chest_index:
			chest_pose = _bones.from_top(skeleton, _chest_index)
		chest = to_here * chest_pose.origin
		var frame := to_here.basis.orthonormalized()
		chest_turned = (
			frame * chest_pose.basis.orthonormalized() * _chest_rest_turn * frame.inverse()
		)
	_chest = chest
	var pitch := posed_pitch
	if character != null:
		pitch = rad_to_deg(character.view_pitch)
	pitch = clampf(pitch, -pitch_limit, pitch_limit)
	if _low_key != Vector2(low_pitch, low_yaw):
		_low_key = Vector2(low_pitch, low_yaw)
		_low_turn = _turned(low_pitch, low_yaw)
	var low := _low_turn
	var aim_key := Vector2(pitch, _kick)
	if _aim_key != aim_key:
		# `_turned(-pitch - kick_degrees * _kick, 0.0)`: no turn across is the identity.
		_aim_key = aim_key
		_aim_turn = (
			Basis(Vector3.RIGHT, deg_to_rad(-pitch - kick_degrees * _kick))
			. get_rotation_quaternion()
		)
	var aim := _aim_turn
	# A slerp all the way to either end is that end (its sign aside, the same turn).
	var turn := low if _raised == 0.0 else (aim if _raised == 1.0 else low.slerp(aim, _raised))
	var pocket := low_pocket.lerp(aim_pocket, _raised)
	if _freed > 0.0:
		turn = turn.slerp(_turned(free_pitch, free_yaw), smoothstep(0.0, 1.0, _freed))
	if _down > 0.0:
		var eased := smoothstep(0.0, 1.0, _down)
		turn = turn.slerp(_turned(stow_pitch, stow_yaw), eased)
		pocket = pocket.lerp(stow_pocket, eased)
	var basis_now := Basis(turn)
	# The frame the pockets are given in: the chest's turn about the up axis, and `pocket_lean` of
	# the rest of its turn from its rest (a lean forward, back or aside).
	var turned := chest_turned.get_rotation_quaternion()
	var twist := Quaternion(0.0, turned.y, 0.0, turned.w)
	if twist.length_squared() < 1e-8:
		twist = Quaternion.IDENTITY
	twist = twist.normalized()
	var lean := turned * twist.inverse()
	pocket = chest + Basis(Quaternion.IDENTITY.slerp(lean, pocket_lean) * twist) * pocket
	var gun_in_pivot := Transform3D.IDENTITY
	if _gun != null:
		gun_in_pivot = _gun.transform if _gun.get_parent() == _pivot else _between(_gun, _pivot)
	var pivot_xf := Transform3D(basis_now, pocket)
	# The left shoulder comes toward the hand guard with the gun where the last frame's push has
	# it, then the butt comes to the skin as the shoulder left it (the turn brings the chest's left
	# side forward under the stock). A push that moved more than `_PUSH_STEP` since the last
	# frame (a new pose, a switch) is gone through again, from the clip's collarbone.
	var clip_clavicle := Transform3D.IDENTITY
	var way := _push_way(basis_now)
	if _clavicle_index >= 0:
		clip_clavicle = skeleton.get_bone_pose(_clavicle_index)
	var to_skeleton := to_here.affine_inverse()
	var reaches := _targets[1] != null and _clavicle_index >= 0 and reach_turn > 0.0 and _left_found
	var support := gun_in_pivot * _left_rest.origin
	var turn_share := _reach * ((1.0 - FreeHand.gone(_freed)) if _freed > 0.0 else 1.0)
	# A melee blow's clip has the shoulders as far as it holds the upper body (`HoldBlow`).
	turn_share *= 1.0 - _blow.amount
	for pass_index in _PASSES:
		pivot_xf.origin = pocket + way * _push - basis_now.z * kick_distance * _kick
		if reaches:
			_bones.reach(
				skeleton,
				_clavicle_index,
				_left_indices[0],
				to_skeleton * (pivot_xf * support),
				_arm * arm_stretch,
				deg_to_rad(reach_turn),
				turn_share
			)
		# Past `fingers_far_distance` the butt keeps the push of the last near frame: the skin
		# is not gone through for a body too far to show a centimetre.
		if fingers_far and fingers_far_distance > 0.0:
			break
		var before := _push
		_push = _skin.push(
			skeleton,
			Transform3D(basis_now, pocket),
			to_here,
			butt_pad,
			butt_depth,
			lerpf(butt_margin, carry_butt_margin, carry_amount()),
			way
		)
		pivot_xf.origin = pocket + way * _push - basis_now.z * kick_distance * _kick
		if absf(_push - before) <= _PUSH_STEP or _clavicle_index < 0:
			break
		if pass_index == _PASSES - 1:
			break
		skeleton.set_bone_pose(_clavicle_index, clip_clavicle)
	# With no pull allowed (`pull_limit` 0, as shipped) there is none to work out.
	if _targets[1] != null and _left_found and pull_limit > 0.0:
		var shoulder := to_here * _bones.from_top(skeleton, _left_indices[0]).origin
		var length := _arm * to_here.basis.get_scale().x * arm_stretch
		var back := HoldBones.pull(pivot_xf * support - shoulder, -pivot_xf.basis.z, length)
		pivot_xf.origin -= basis_now.z * clampf(back, 0.0, pull_limit)
	if _blow.amount > 0.0 and _targets[0] != null:
		pivot_xf = HoldBlow.carried(
			pivot_xf,
			_blow.amount,
			skeleton,
			_hand_index,
			to_here,
			_targets[0].transform,
			gun_in_pivot
		)
	_pivot.transform = pivot_xf
	var gun_here := pivot_xf * gun_in_pivot
	# At rest nothing moves the left hand's place or the magazine once they are put back.
	var reload := posed_reload if character == null else _reload_progress()
	if not _hand_at_rest or _freed > 0.0 or _on_magazine == null or reload >= 0.0:
		_place_reload(gun_here)
	for index in mini(_arms.size(), 2):
		var target := _targets[index]
		if target == null:
			continue
		var target_here := gun_here * target.transform
		if target.get_parent() != _gun:
			target_here = _in_here(target)
		_arms[index].offset = to_skeleton * target_here
		var pole := _poles[index]
		if pole != null:
			var pole_here := pole.transform if pole.get_parent() == self else _in_here(pole)
			_arms[index].elbow = to_skeleton * pole_here.origin


## The skeleton's indexes of `spine_bones`, for the stance modifier.
func spine_indices() -> PackedInt32Array:
	return _spine_indices


# The way the butt goes from the pocket to the skin: along the barrel, its fall taken out by
# `push_level` while the muzzle is down (kit #1346). Aimed up the barrel's way stays: the push is
# small there, and out level it jumped between frames on a walk and shook the head on the sights.
func _push_way(turn: Basis) -> Vector3:
	var barrel := turn.z.normalized()
	var level := Vector3(barrel.x, 0.0, barrel.z)
	if push_level <= 0.0 or barrel.y >= 0.0 or level.length_squared() < 1e-6:
		return barrel
	return barrel.slerp(level.normalized(), push_level)


## How far the butt went from the pocket to the skin in the last frame it was measured, in metres
## (along `push_level`'s way).
func butt_push() -> float:
	return _push


## The weight of the hold on the arms and the chest: with the arms.
func weight() -> float:
	return _reach


## The weight of the chest's turn toward the hand guard: with the arms, and none while the left
## hand is away for an action, whose clip then has the shoulders (the turn would bring its
## reaching arm across the gun), nor while a melee blow's clip has the upper body.
func chest_weight() -> float:
	return _reach * (1.0 - smoothstep(0.0, 1.0, _freed)) * (1.0 - _blow.amount)


# How far the arms are on the gun's places now. In the hands: all the way. While the weapon
# before it goes down to make room for it, and while the one after it comes up: as far as the
# loadout's switch has the weapon down, so the arms are on the gun in the tick it appears and
# leave it only once it is hidden.
func _reach_now() -> float:
	if character == null or _loadout == null:
		return 1.0
	var mine := _definition()
	if _loadout.held_definition() == mine:
		return 1.0
	if not _loadout.is_switching():
		return 0.0
	var target := _loadout.target_slot()
	var coming := target >= 0 and target < _loadout.slots.size() and _loadout.slots[target] == mine
	return _loadout.lowered_amount() if coming or _leaving else 0.0


# How far the gun is down at its stow place: by the switch while it is in the hands, all the way
# while it is not.
func _down_now() -> float:
	if character == null or _loadout == null:
		return posed_lowered
	if _loadout.held_definition() == _definition():
		return _loadout.lowered_amount()
	return 1.0


# The weapon definition this hold is the view of, or null: looked for again after the slots
# changed (or their count, for slots set by hand) and while it is not found.
func _definition() -> WeaponDef:
	if _loadout == null or _loadout.model == null:
		return null
	if _mine != null and _mine_slots == _loadout.slots.size():
		return _mine
	_mine = null
	_mine_slots = _loadout.slots.size()
	for definition in _loadout.slots:
		if definition != null and _loadout.model.get_node_or_null(definition.view) == self:
			_mine = definition
			break
	return _mine


func _forget_definition() -> void:
	_mine = null


# Whether the fingers rest: `fingers_far`, unless `fingers_far_distance` is 0.
func _fingers_far() -> bool:
	return fingers_far and fingers_far_distance > 0.0


func _on_weapon_changed(definition: WeaponDef) -> void:
	# Hidden for the next weapon: the arms leave the gun's places as that one comes up.
	_leaving = _reach >= 1.0 and definition != _definition() and _loadout.is_switching()


func _on_switch_finished() -> void:
	_leaving = false


func _step(delta: float) -> void:
	if character != null:
		_free.step(delta)
		# Put away by a switch, not for the action (a high vault hides the gun it frees).
		if _reload_progress() >= 0.0 or not visible and _reach <= 0.0:
			_free.stop()
		_freed = _free.amount()
		_blow.step(character)
		var wants := _blow.aim(character)
		_shot_left = maxf(_shot_left - delta, 0.0)
		if _shot_left > 0.0:
			wants = 1.0
		if _freed > 0.0:
			wants = 0.0
		_raised = move_toward(_raised, wants, delta / maxf(raise_time, 0.001))
		_carry.step(character, _freed, visible, carry_time, delta)
	else:
		_raised = posed_aim
		_freed = posed_free
		_carry.amount = posed_carry
		_blow.amount = posed_blow
	_kick = move_toward(_kick, 0.0, delta / maxf(kick_recover_time, 0.001))


# A turn of the gun from straight ahead: the muzzle `pitch` degrees down and `yaw` across.
func _turned(pitch: float, yaw: float) -> Quaternion:
	var turned := Basis(Vector3.RIGHT, deg_to_rad(pitch)) * Basis(Vector3.UP, deg_to_rad(yaw))
	return turned.get_rotation_quaternion()


# A node's transform in this node's space, from the transforms up its parents (no global
# transform is asked for while the skeleton updates).
func _in_here(node: Node3D) -> Transform3D:
	return _between(node, self)


# A node's transform in the space of `top`, one of its parents, from the transforms between.
func _between(node: Node3D, top: Node) -> Transform3D:
	var xf := node.transform
	var above := node.get_parent() as Node3D
	while above != null and above != top:
		xf = above.transform * xf
		above = above.get_parent() as Node3D
	return xf


# How far the reload is (0 to 1), or below 0 with none.
func _reload_progress() -> float:
	if character == null:
		return posed_reload
	if _weapon != null and _weapon.is_reloading() and visible:
		return _weapon.reload_progress()
	return -1.0


# How far the left hand is from the hand guard (0) to the magazine (1) at `progress` of a reload.
func _to_magazine(progress: float) -> float:
	if progress < 0.0:
		return 0.0
	if _charging() and progress >= charge.leave.x:
		return charge.to_magazine(progress, Vector3(_WAY_ON, _WAY_BESIDE, _WAY_DOWN), reload_return)
	var there := smoothstep(reload_leave.x, reload_leave.y, progress)
	return there * (1.0 - smoothstep(reload_return.x, reload_return.y, progress))


# The left hand leaves the gun for the magazine and comes back with a full one, by the weapon's
# reload progress: down off the hand guard with its fingers open, across to beside the magazine,
# onto it and closed on it, straight down out of the well and to the belt (where the magazine is
# changed, out of sight), back up under the well, straight in, and back the way it came.
func _place_reload(gun_here: Transform3D) -> void:
	var left := _targets[1]
	if left == null:
		return
	var progress := _reload_progress() if _on_magazine != null else -1.0
	var mag := _mag
	var mag_far := _mag_far
	# A hand let go for an action comes off the hand guard the way a reload's does, and no further.
	var let_go := _let_go() if _freed > 0.0 else 0.0
	if progress < 0.0 and let_go <= 0.0:
		# At rest nothing but this moves the hand's place and the magazine: put them back once.
		if not _hand_at_rest:
			left.transform = _left_rest
			_set_magazine(mag, mag_far, _magazine_rest, true)
			_bolt.put(charge, 0.0)
			_hand_at_rest = true
		return
	_hand_at_rest = false
	var to_magazine := maxf(_to_magazine(progress), let_go)
	var away := smoothstep(reload_out.x, reload_out.y, progress)
	away *= 1.0 - smoothstep(reload_in.x, reload_in.y, progress)
	# Down off the hand guard, across to beside the magazine, then onto it.
	var below := _left_rest.translated(reload_clearance)
	var on_magazine := _on_magazine.transform if _on_magazine != null else below
	var beside := on_magazine.translated(magazine_approach)
	# A little straight down while the knuckles let go (the hooked fingers come off the far side
	# clear), then down and out to the thumb's side together: a move sideways under closed fingers
	# pushes the far side's into the hand guard, and a drop with none drags the thumb through it.
	var hand := _left_rest.translated(
		Vector3.DOWN * _LET_GO_DROP * smoothstep(0.0, _WAY_OPEN * 0.5, to_magazine)
	)
	hand = hand.interpolate_with(below, smoothstep(_WAY_OPEN * 0.5, _WAY_DOWN, to_magazine))
	hand = hand.interpolate_with(beside, smoothstep(_WAY_DOWN, _WAY_BESIDE, to_magazine))
	hand = hand.interpolate_with(on_magazine, smoothstep(_WAY_BESIDE, _WAY_ON, to_magazine))
	if progress < 0.0:
		var aside := smoothstep(_FREE_DOWN, 1.0, FreeHand.off(_freed))
		hand = hand.interpolate_with(_left_rest.translated(free_clearance), aside)
	elif _charging():
		if charge.holds_way(progress, reload_return.x):
			hand = charge.hand_place(
				progress, on_magazine, beside, _on_handle.transform, below, reload_return.x
			)
		_bolt.put(charge, charge.bolt_pull(progress))
	# Out of the well along the gun's own up axis, then to the belt, which is a place on the
	# body (the hand's place is on the gun).
	var out := Vector3.DOWN * magazine_well * minf(away / _WELL_SHARE, 1.0)
	var to_belt := smoothstep(0.0, 1.0, (away - _WELL_SHARE) / (1.0 - _WELL_SHARE))
	var belt := gun_here.affine_inverse() * (_chest + reload_belt)
	out += (belt - (hand.origin + out)) * to_belt
	hand.origin += out
	left.transform = hand
	var mag_xf := _magazine_rest
	if mag != null:
		mag_xf.origin += (mag.get_parent() as Node3D).transform.basis.inverse() * out
	_set_magazine(mag, mag_far, mag_xf, away < 0.9)


# How far down the reload's way off the hand guard a freed hand is (`_WAY_DOWN` at most).
func _let_go() -> float:
	return minf(FreeHand.off(_freed) / _FREE_DOWN, 1.0) * _WAY_DOWN


# Whether the reload pulls the charging handle: a `charge`, its marker and its finger pose.
func _charging() -> bool:
	return charge != null and _on_handle != null and charge_pose != null


func _set_magazine(near: Node3D, far: Node3D, xf: Transform3D, shown: bool) -> void:
	for mag: Node3D in [near, far]:
		if mag != null:
			mag.transform = xf
			mag.visible = shown


func _on_fired() -> void:
	if not visible:
		return
	_shot_left = shot_hold_time
	_kick = 1.0


func _on_rig_changed() -> void:
	_drop_modifiers()
	var slot := get_parent() as CharacterModel
	_skeleton = slot.skeleton() if slot != null else null
	if _skeleton == null:
		return
	_fit_body(slot)
	_find_bones()
	_skin.measure(_skeleton, _chest_index, torso_bones, skin_spacing)
	_push = 0.0
	_stance = STANCE_SCRIPT.new() as SkeletonModifier3D
	_stance.set(&"hold", self)
	_add_modifier(_stance, "Stance")
	_add_arm(right_arm, "RightArm")
	_add_arm(left_arm, "LeftArm")
	_add_fingers(grip_pose, trigger_pose, null, "RightFingers")
	if trigger_way != null:
		_fingers[-1].second_way = trigger_way.poses
	_add_fingers(support_pose, magazine_pose, open_pose, "LeftFingers")
	_fingers[-1].third = charge_pose
	refresh()


## The fit in use: the one solved on the body the model slot holds, or the scene's own.
func fit() -> HoldFit:
	var found := HoldFit.chosen(fits, get_parent() as CharacterModel)
	return found if found != null else _own


# Puts the fit of the model's body on the hands' places and on the poses, keeping the scene's own
# first.
func _fit_body(slot: CharacterModel) -> void:
	if _own == null:
		_own = HoldFit.of_two_hand(self, _targets[0], _left_rest, _on_magazine, _on_handle)
	var chosen := HoldFit.chosen(fits, slot)
	if chosen == null:
		chosen = _own
	chosen.put_on_two_hand(self, _targets[0], _targets[1], _on_magazine, _on_handle)
	_left_rest = chosen.support_hand
	_hand_at_rest = false


func _add_arm(bones: Array[StringName], tag: String) -> void:
	var arm := HoldArm.new()
	arm.arm = bones
	arm.bone = &""
	_arms.append(arm)
	_add_modifier(arm, tag)


func _add_fingers(pose: HandPose, second: HandPose, open: HandPose, tag: String) -> void:
	var fingers := HandPoseModifier.new()
	fingers.pose = pose
	fingers.second = second
	fingers.open = open
	if open != null:
		for bone_name in open.rotations:
			if String(bone_name).contains(_KNUCKLE):
				fingers.open_first.append(bone_name)
		fingers.open_first = fingers.open_first
	_fingers.append(fingers)
	_add_modifier(fingers, tag)


func _add_modifier(modifier: SkeletonModifier3D, tag: String) -> void:
	modifier.name = _MODIFIER_PREFIX + tag
	_skeleton.add_child(modifier)
	_modifiers.append(modifier)
	var kind := HoldWeights.FINGERS if modifier is HandPoseModifier else HoldWeights.OTHER
	if modifier is HoldArm:
		kind = HoldWeights.LEFT_ARM if tag == "LeftArm" else HoldWeights.ARM
	elif tag == "LeftFingers":
		kind = HoldWeights.LEFT_FINGERS
	_weights.add(modifier, kind)


func _drop_modifiers() -> void:
	for modifier in _modifiers:
		if is_instance_valid(modifier):
			modifier.queue_free()
			if modifier.get_parent() != null:
				modifier.get_parent().remove_child(modifier)
	_modifiers.clear()
	_weights.clear()
	_arms.clear()
	_fingers.clear()
	_stance = null


func _find_parts() -> void:
	_pivot = get_node_or_null(^"Pivot") as Node3D
	_targets[0] = find_child("RightHandTarget", true, false) as Node3D
	_targets[1] = find_child("LeftHandTarget", true, false) as Node3D
	_poles[0] = get_node_or_null(^"RightPole") as Node3D
	_poles[1] = get_node_or_null(^"LeftPole") as Node3D
	_on_magazine = find_child("MagazineHand", true, false) as Node3D
	_on_handle = find_child("ChargeHand", true, false) as Node3D
	_bolt.find(self, [bolt, bolt_far])
	_gun = _targets[1].get_parent() as Node3D if _targets[1] != null else null
	_mag = get_node_or_null(magazine) as Node3D
	_mag_far = get_node_or_null(magazine_far) as Node3D
	_hand_at_rest = false


func _find_bones() -> void:
	_bones.read(_skeleton)
	_chest_index = _skeleton.find_bone(chest_bone)
	_chest_rest_turn = Basis.IDENTITY
	if _chest_index >= 0:
		var rest := _skeleton.get_bone_global_rest(_chest_index).basis.orthonormalized()
		_chest_rest_turn = rest.inverse()
	_clavicle_index = _skeleton.find_bone(left_clavicle)
	_spine_indices.clear()
	for bone_name in spine_bones:
		_spine_indices.append(_skeleton.find_bone(bone_name))
	_hand_index = _skeleton.find_bone(right_arm[2]) if right_arm.size() > 2 else -1
	_left_indices.clear()
	for bone_name in left_arm:
		_left_indices.append(_skeleton.find_bone(bone_name))
	_left_found = _left_indices.size() >= 3 and not _left_indices.has(-1)


## The parents of the skeleton's bones, read once when the model was put in (for the stance).
func bone_parents() -> PackedInt32Array:
	return _bones.parents

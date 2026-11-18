class_name HoldArmCarry
extends Node
## The carried weapon's steady arm (gdstudio #1577), a child of the `WeaponHold` it serves: makes
## an `ArmCarrySteady` on the model's skeleton each time the hold builds its modifiers, right
## before the grip, and weighs it every frame from the hold's own weights, so the arm keeps one
## readable carry while the weapon is carried in one hand (`CharacterAnimation.Carry.HAND_ONLY`)
## and is the aim's, the reload's or an action's again as they come in. The numbers are
## `settings` (`pistol_arm_carry.tres`), tuned live. Cosmetic, never sent.

## How the arms ride the stride.
@export var settings: ArmCarry

var _hold: WeaponHold
var _steady: ArmCarrySteady


func _ready() -> void:
	_hold = get_parent() as WeaponHold
	if _hold == null:
		return
	_hold.built.connect(_attach)
	_attach.call_deferred()


## The modifier made on the skeleton now, or null.
func steady() -> ArmCarrySteady:
	return _steady if _steady != null and is_instance_valid(_steady) else null


## How much of the carry holds the arms now, 0 to 1: the hold's weight on the weapon, less the
## aim, a reload or the rack, and the left hand let go for an action; none without an animation.
func weight() -> float:
	if _hold == null or settings == null:
		return 0.0
	# A character posed by hand (a test, a capture) has no stride to steady.
	var animation := _hold.animation
	if animation == null or animation.carry != CharacterAnimation.Carry.HAND_ONLY:
		return 0.0
	if animation.tree == null or not animation.tree.active:
		return 0.0
	var busy := maxf(_hold.reload_weight, _hold.rack_weight)
	var free := FreeHand.gone(_hold.free_weight)
	return _hold.held_weight * (1.0 - _hold.aim_weight) * (1.0 - busy) * (1.0 - free)


func _process(_delta: float) -> void:
	var made := steady()
	if made != null:
		made.weigh(weight())


func _attach() -> void:
	var model := _hold.model if _hold != null else null
	var skeleton := model.skeleton() if model != null else null
	if skeleton != null and steady() != null and _steady.get_parent() == skeleton:
		# The hold built again on the same skeleton: keep the carry, before its new grip.
		var grip := _hold.grip_modifier()
		if grip != null:
			skeleton.move_child(_steady, grip.get_index())
		return
	_steady = ArmCarrySteady.attach(skeleton, settings, steady(), _hold.grip_modifier())

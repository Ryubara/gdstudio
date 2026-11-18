class_name HoldArmCarry
extends Node
## The carried weapon's steady arm (gdstudio #1577), a child of the `WeaponHold` it serves: makes
## an `ArmCarrySteady` on the model's skeleton each time the hold builds its modifiers, kept right
## before the grip, and weighs it every frame from the hold's own weights, so the arm keeps one
## readable carry while the weapon is carried in one hand (`CharacterAnimation.Carry.HAND_ONLY`)
## and is the aim's, the reload's or an action's again as they come in. The numbers are
## `settings` (`pistol_arm_carry.tres`), tuned live. Cosmetic, never sent.

## How the arms ride the stride.
@export var settings: ArmCarry

var _hold: WeaponHold
var _steady: ArmCarrySteady
# How far the body moves for the carry, 0 to 1, eased up and down (`ArmCarry.moving_rise_time`,
# `moving_fall_time`).
var _moving := 0.0


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
	var carried := _hold.held_weight * (1.0 - _hold.aim_weight) * (1.0 - busy) * (1.0 - free)
	return carried * _moving


func _process(delta: float) -> void:
	_follow_speed(delta)
	var made := steady()
	if made != null:
		made.keep_before(_hold.grip_modifier())
		made.weigh(weight())


func _follow_speed(delta: float) -> void:
	var animation := _hold.animation if _hold != null else null
	if animation == null or animation.character == null or settings == null:
		return
	var speed := animation.character.ground_speed()
	var share := clampf(speed / settings.moving_speed, 0.0, 1.0)
	var seconds := settings.moving_rise_time if share > _moving else settings.moving_fall_time
	_moving = move_toward(_moving, share, delta / maxf(seconds, 0.001))


func _attach() -> void:
	var model := _hold.model if _hold != null else null
	var skeleton := model.skeleton() if model != null else null
	if skeleton != null and steady() != null and _steady.get_parent() == skeleton:
		# The hold built again on the same skeleton: keep the carry, before its new grip.
		_steady.keep_before(_hold.grip_modifier())
		return
	_steady = ArmCarrySteady.attach(skeleton, settings, steady(), _hold.grip_modifier())

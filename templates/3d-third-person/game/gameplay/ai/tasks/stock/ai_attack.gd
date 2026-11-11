@tool
class_name AiAttack
extends AiStockTask
## Fights its subject with the weapon in the hands.
##
## - **Ranged** (a gun): the aim model of `AiAim` (reaction floor, a turn limited by `aim_speed`,
##   tracking noise that shrinks on the target, bursts), only at a subject believed and seen now,
##   never through a friend. It closes in past the profile's `engage_range` and backs off inside
##   `preferred_range - retreat_margin`; an empty magazine is reloaded.
## - **Melee** (fists, or `melee` on): walks in until the subject is within the weapon's own
##   `melee_reach` (plus `reach_slack`, never past the profile's `attack_range`), winds up for
##   `windup_seconds`, then swings. Measuring the swing from the weapon's reach, not a looser
##   number, is what lands a blow on a target 1.4 m away (Deadnight's reach fault).
##
## It succeeds when the subject dies, fails `TARGET_LOST` when the subject has been out of sight
## `lose_after` seconds (the brain's `lost_sight`: a chase) and `NO_AMMO` when the gun is dry with
## nothing to load (`no_ammo`). With `draw_fists` it puts the gun away for the fists first.

## Seconds `draw_fists` waits for the fists before it gives up (`NO_AMMO`).
const FISTS_SECONDS := 2.0
## Metres from the swing's distance where the fists come up.
const RAISE_FISTS := 0.6

## Fight hand to hand whatever the weapon (on by itself when the weapon is a melee one).
@export var melee := false
## Put the weapon away for the fists at the start (a dry gun's answer).
@export var draw_fists := false
## Keep to the profile's ranges (close in, back off); off stands where it is.
@export var keep_range := true

@export_group("Aim")
## The aim must be this near the target before the trigger is pulled.
@export_range(0.5, 45.0, 0.5, "suffix:°") var fire_cone_degrees := 6.0
## The tracking noise at accuracy 0, before it settles.
@export_range(0.0, 30.0, 0.1, "suffix:°") var noise_degrees := 8.0
## Seconds on the target that shrink the noise to a third.
@export_range(0.05, 10.0, 0.05, "suffix:s") var settle_seconds := 1.0
## Seconds the subject may be out of sight before it is lost.
@export_range(0.1, 30.0, 0.1, "suffix:s") var lose_after := 1.5

@export_group("Melee")
## The pause, standing in reach, before a swing.
@export_range(0.0, 3.0, 0.05, "suffix:s") var windup_seconds := 0.35
## Metres added to the weapon's reach for the distance a swing starts from.
@export_range(0.0, 1.0, 0.01, "suffix:m") var reach_slack := 0.15

## The aim model (a test reads its shots).
var gun := AiAim.new()
## Swings started.
var swings := 0

var _unseen := 0.0
var _windup := 0.0
var _press_fists := false
var _approach_at := Vector3.INF


func _init() -> void:
	id = &"engage"
	layer = Layer.RESPONSE
	channels = Channel.MOVE | Channel.ACTION | Channel.LOOK
	answers_threat = true
	hard_timeout = 0.0
	ends_on_condition = true


func start() -> void:
	gun = AiAim.new(hash(String(character.name)) if character != null else 0)
	_unseen = 0.0
	_windup = 0.0
	_approach_at = Vector3.INF
	_press_fists = draw_fists and body() != null and body().loadout != null and not _is_melee()


func update(delta: float) -> Status:
	# The empty-hands button is held for one think (the body reads a press between thinks).
	if controller != null:
		controller.unarmed = _press_fists
	_press_fists = false
	var foe := subject()
	var belief := belief_of(foe)
	if foe == null or belief == null:
		return _lose()
	last_known = belief.last_position
	if foe is Character and (foe as Character).is_dead():
		_stand()
		return Status.SUCCEEDED
	if not belief.can_fire_at():
		_unseen += delta
		controller.aim = false
		controller.fire = false
		look_toward(belief.last_position)
		_stand()
		return _lose() if _unseen >= lose_after else Status.RUNNING
	_unseen = 0.0
	return _fight(delta, belief)


func _fight(delta: float, belief: AiBelief) -> Status:
	if _is_melee():
		return _melee(delta, belief)
	var shot := AiAim.Shot.HELD
	if draw_fists:
		# The fists are on their way up: face the subject meanwhile.
		_stand()
		look_toward(belief.last_position)
		controller.aim = true
		if elapsed < FISTS_SECONDS:
			return Status.RUNNING
		shot = AiAim.Shot.DRY
	else:
		shot = gun.step(self, belief, delta, fire_cone_degrees, noise_degrees, settle_seconds)
	if shot == AiAim.Shot.DRY:
		_stand()
		reason = Reason.NO_AMMO
		return Status.FAILED
	if keep_range:
		_keep_range(belief)
	return Status.RUNNING


func event_for(why: Reason) -> StringName:
	return AiBehaviourSet.LOST_SIGHT if why == Reason.TARGET_LOST else super(why)


func resume() -> Resume:
	gun.reset()
	_approach_at = Vector3.INF
	return Resume.RESUME


func detail() -> String:
	return "melee" if _is_melee() else ("%d shots" % gun.shots)


func _is_melee() -> bool:
	var weapon := body().weapon if body() != null else null
	var kind_melee := (
		weapon != null
		and weapon.definition != null
		and weapon.definition.kind == WeaponDef.Kind.MELEE
	)
	return kind_melee or (melee and not draw_fists)


func _melee(delta: float, belief: AiBelief) -> Status:
	var weapon := body().weapon
	var profile := run_profile()
	var reach := weapon.definition.melee_reach if weapon != null and weapon.definition else 1.0
	var swing_at := minf(reach + reach_slack, profile.attack_range if profile else reach)
	var away := flat_distance(belief.last_position)
	controller.fire = false
	# Fists up only for the last steps: an aim slows the walk in.
	controller.aim = away <= swing_at + RAISE_FISTS
	look_toward(belief.last_position)
	if away > swing_at:
		_windup = 0.0
		_close_in(belief.last_position, away)
		return Status.RUNNING
	_stand()
	_windup += delta
	if _windup >= windup_seconds and weapon != null and weapon.can_fire():
		controller.fire = true
		swings += 1
		_windup = 0.0
	return Status.RUNNING


func _keep_range(belief: AiBelief) -> void:
	var profile := run_profile()
	var away := flat_distance(belief.last_position)
	if away > profile.engage_range:
		_close_in(belief.last_position, away)
	elif away < profile.preferred_range - profile.retreat_margin:
		stop_walk()
		var back := (character as Node3D).global_position - belief.last_position
		back.y = 0.0
		controller.walk_direction = (
			back.normalized() if back.length_squared() > 0.01 else Vector3.ZERO
		)
		controller.walk_strength = speed_share(Speed.WALK)
	else:
		_stand()


# Near, it walks straight at the subject; farther, the navigator takes it there.
func _close_in(point: Vector3, away: float) -> void:
	if away < 3.0:
		stop_walk()
		var toward := point - (character as Node3D).global_position
		toward.y = 0.0
		controller.walk_direction = toward.normalized()
		controller.walk_strength = speed_share(Speed.WALK)
		return
	if (
		_approach_at == Vector3.INF
		or _approach_at.distance_to(point) > 1.0
		or not nav().is_active()
	):
		_approach_at = point
		go(point, Speed.RUN)


func _stand() -> void:
	stop_walk()
	_approach_at = Vector3.INF
	if controller != null:
		controller.walk_direction = Vector3.ZERO


func _lose() -> Status:
	_stand()
	reason = Reason.TARGET_LOST
	return Status.FAILED

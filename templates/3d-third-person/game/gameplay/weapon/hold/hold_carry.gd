class_name HoldCarry
extends RefCounted
## How far a `TwoHandHold` carries the trunk upright at the low ready (kit #1348): the rifle's run
## leaned the trunk 13 degrees and the sprint 14, so while the character runs on its feet the
## stance raises a trunk that leans more than the hold's `carry_lean_limit` toward it
## (`TwoHandStance`). This is the share it does so by, eased over the hold's `carry_time`; the hold
## takes it off as the gun comes up, by its weight and under a melee blow
## (`TwoHandHold.carry_amount()`).

## The states the trunk is carried upright in.
const STATES: Array[Character.State] = [
	Character.State.IDLE,
	Character.State.WALK,
	Character.State.RUN,
	Character.State.JUMP,
	Character.State.FALL,
	Character.State.LAND,
]

## How far the trunk is carried upright now, 0 to 1, before the hold's own shares.
var amount := 0.0


## Eases `amount` toward what `body` wants (`wanted()`) over `seconds`, by `delta` seconds;
## `freed` is how far the left hand is let go (`FreeHand.amount()`).
func step(body: Character, freed: float, seconds: float, delta: float) -> void:
	amount = move_toward(amount, wanted(body, freed), delta / maxf(seconds, 0.001))


## How far `body`'s trunk is to be carried upright: in `STATES`, from none at the walk's speed to
## all of it at the run's (standing, the rifle's idle leans 10 degrees by itself, and that stays),
## never with the left hand away (`freed` above 0).
static func wanted(body: Character, freed: float) -> float:
	var tuning := body.tuning
	if tuning == null or freed > 0.0 or not body.state in STATES:
		return 0.0
	var walk := tuning.walk_speed
	return clampf((body.ground_speed() - walk) / maxf(tuning.run_speed - walk, 0.01), 0.0, 1.0)

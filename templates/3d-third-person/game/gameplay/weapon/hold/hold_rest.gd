class_name HoldRest
extends RefCounted
## Whether a `WeaponHold` can leave its left hand, its one-handed stance, its hands' floor keeper
## and its rack as its last refresh wrote them (kit #1478). With nothing aimed, no reload or rack
## playing and no hand let go for an action, every one of those modifiers is off whatever else the
## frame holds (how far the weapon is held, how far the body lies, the last shot's kick), so a
## second frame like that would write nothing that is drawn: the hold places only the grip and
## the slide. A walking crowd that never aims pays for those two alone.
##
## The modifiers made again (a new model, a new weapon) make a new grip, which starts over.

## On: never at rest, so every refresh works everything out (the pose test compares the two).
var off := false
## How many refreshes it has let rest so far (the tests read it).
var rested := 0

var _was := false
var _grip := 0


## True when this refresh (`aim` how far the weapon is aimed, `busy` how much a reload or the rack
## holds the body, `free` how far a hand is let go) and the last one on the same `grip` modifier
## both had none of the three. Called once a refresh.
func holds(grip: Object, aim: float, busy: float, free: float) -> bool:
	var now := not off and aim <= 0.0 and busy <= 0.0 and free <= 0.0
	var id := grip.get_instance_id()
	var held := now and _was and id == _grip
	_was = now
	_grip = id
	if held:
		rested += 1
	return held

class_name CharacterState
extends RefCounted
## Everything a character's step reads from the tick before: where the body is, how it moves and
## every timer and latch. `Character.state_snapshot()` fills one and `Character.restore()` puts one
## back, so a test or a client that predicts can set a body to an earlier tick.
##
## `values` holds the `Character` members named in `FIELDS`, in that order;
## `test_character_state.gd` fails when the body gains a variable that is neither in `FIELDS` nor
## on its list of things that are not step state. Not here on purpose: what the character holds
## (`items`), death (`die()` and `revive()` are events), and the engine's own floor contact, which
## a script cannot set (the body finds the floor again on its next move).
##
## A step also does things a snapshot cannot take back (it pushes props, opens a door, fires a
## projectile, collects a pickup), so stepping the same commands again after `restore()` repeats
## them: use it to put a body where the server says, not to replay.

## The `Character` members a snapshot copies by name.
const FIELDS: Array[StringName] = [
	&"state",
	&"facing",
	&"view_yaw",
	&"view_pitch",
	&"crouching",
	&"aiming",
	&"aim_held",
	&"fire_held",
	&"aim_amount",
	&"_coyote",
	&"_jump_buffer",
	&"_action_lock",
	&"_land_timer",
	&"_fall_speed",
	&"_was_airborne",
	&"_grounded",
	&"_fallen",
	&"_pushing",
	&"_push_cap",
	&"_push_hold",
	&"_jump_held",
	&"_sprinting",
	&"_wants_crouch",
	&"_crouch_amount",
	&"_fire_buffer",
]

## Where the body is, metres.
var position := Vector3.ZERO
## How it moves, m/s.
var velocity := Vector3.ZERO
## The members of `FIELDS`, in that order.
var values: Array = []
## The step state of the character's weapon (`Weapon.save_step_state()`: its cooldown and its
## place in the spread's seeded order), so a body put back shoots again on the same tick and in
## the same direction. Empty for a character with no weapon.
var weapon: Array = []
## The step state of the character's `WeaponLoadout` (`save_step_state()`: what is in the hands,
## where a switch is, each slot's ammunition). Empty for a character with no loadout.
var loadout: Array = []
## The prone stance (`CharacterProne.save_step_state()`: lying or not, how far down, the time
## off the ground).
var prone: Array = []
## The step state of the character's slide (`CharacterSlide.save_step_state()`: whether it slides,
## for how long, how low, its cooldowns and the speed a slide jump carries).
var slide: Array = []

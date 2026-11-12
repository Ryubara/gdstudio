class_name CharacterState
extends RefCounted
## Everything a character's step reads from the tick before: where the body is, how it moves and
## every timer and latch. `Character.state_snapshot()` fills one (`take()`) and
## `Character.restore()` puts one back (`put_back()`), so a test or a client that predicts can set
## a body to an earlier tick. A module of the body with step state of its own (`CharacterProne`,
## `CharacterSlide`) saves it in an array here, written in `take()` and read in `put_back()`.
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
	&"_fire_was",
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
## The step state of the character's vault (`CharacterVault.save_step_state()`: the time into the
## crossing, its cooldown and the plan's path), so a body put back mid-vault crosses on the same
## path.
var vault: Array = []
## The step state of the character's `WeaponLoadout` (`save_step_state()`: what is in the hands,
## where a switch is, each slot's ammunition). Empty for a character with no loadout.
var loadout: Array = []
## The prone stance (`CharacterProne.save_step_state()`: lying or not, how far down, the time
## off the ground).
var prone: Array = []
## The step state of the character's slide (`CharacterSlide.save_step_state()`: whether it slides,
## for how long, how low, its cooldowns and the speed a slide jump carries).
var slide: Array = []


## Copies `body`'s step state into this one (what `Character.state_snapshot()` returns).
func take(body: Character) -> void:
	position = body.global_position
	velocity = body.velocity
	values.resize(FIELDS.size())
	for index in FIELDS.size():
		values[index] = body.get(FIELDS[index])
	if body.weapon != null:
		body.weapon.save_step_state(weapon)
	else:
		weapon.clear()
	body.vault_motion.save_step_state(vault)
	if body.loadout != null:
		body.loadout.save_step_state(loadout)
	else:
		loadout.clear()
	body._prone.save_step_state(prone)
	body._slide.save_step_state(slide)


## Puts this step state back into `body` (`Character.restore()`, which then fits the capsule and
## shows the facing).
func put_back(body: Character) -> void:
	body.global_position = position
	body.velocity = velocity
	for index in FIELDS.size():
		body.set(FIELDS[index], values[index])
	if body.loadout != null:
		body.loadout.load_step_state(loadout)
	if body.weapon != null:
		body.weapon.load_step_state(weapon)
	body.vault_motion.load_step_state(vault)
	body._prone.load_step_state(prone)
	body._slide.load_step_state(slide)

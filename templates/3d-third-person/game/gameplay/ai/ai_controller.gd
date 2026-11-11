class_name AiController
extends CharacterController
## What an AI character's body steps: the same `PlayerCommand` a human's does, built once a tick
## from two channels that the AI's parts write and never the command itself.
##
## - The movement channel (the navigator): `walk_direction`, a flat direction in the world, and
##   `walk_strength`, the share of a full push (a walk is less than a run).
## - The moves the navigator asks for on the way: `jump`, `crouch` and `sprint`, held while on (a
##   jump that starts is a press in exactly one command, as fire is).
## - The action channel (aiming and shooting): `look_direction`, where the eyes and the gun
##   point in the world, and `aim` and `fire`, held while they are on.
##
## `sample()` turns them into the command with `PlayerCommand.set_from_world()`: a zero look keeps
## the view level and lets a body that does not aim face where it walks. A fire that starts is a
## press (`fire_pressed`) in exactly one command, as the contract of `CharacterController` asks.
## It reads no input and no camera, and nobody watches through it (`viewer_position()` is
## `Vector3.INF`, so its character always gets its ragdoll).

## Where to walk, in the world (only its flat part counts); zero stands still.
var walk_direction := Vector3.ZERO
## The share of a full push, 0 to 1.
var walk_strength := 1.0
## Where to look and aim, in the world; zero looks level, along where it walks.
var look_direction := Vector3.ZERO
## Holds the aim (the body turns to `look_direction`).
var aim := false
## Holds the trigger.
var fire := false
## Holds the jump button: a jump (or a vault, at a `Vaultable`) starts on the tick it goes on.
var jump := false
## Holds crouch (at a sprint, a press starts a slide).
var crouch := false
## Holds sprint.
var sprint := false
## Holds the reload button: a reload starts on the tick it goes on (a press, as fire is).
var reload := false
## Holds the use button: the body uses the `Interactable` in front on the tick it goes on.
var interact := false
## Holds the empty-hands button: the loadout puts the weapon away for the fists (or takes it
## back) on the tick it goes on.
var unarmed := false

var _fire_was := false
var _jump_was := false
var _reload_was := false
var _interact_was := false
var _unarmed_was := false
var _built := false
var _repeat := false
var _walk_was := Vector3.ZERO
var _look_was := Vector3.ZERO
var _strength_was := 1.0


func _init() -> void:
	# An AI walks far more ticks than it does anything else: its body takes the lean tick then.
	lean_step = true


func sample() -> PlayerCommand:
	var command := _command
	var fire_pressed := fire and not _fire_was
	var jump_pressed := jump and not _jump_was
	var reload_pressed := reload and not _reload_was
	var interact_pressed := interact and not _interact_was
	var unarmed_pressed := unarmed and not _unarmed_was
	_fire_was = fire
	_jump_was = jump
	_reload_was = reload
	_interact_was = interact
	_unarmed_was = unarmed
	var other_press := reload_pressed or interact_pressed or unarmed_pressed
	# The channels as they were at the last call, with no press then or now: the same command,
	# not built again (an AI's channels change at its thinks, a few times a second).
	if (
		_built
		and not fire_pressed
		and not jump_pressed
		and not other_press
		and not command.fire_pressed
		and not command.jump_pressed
		and not command.reload_pressed
		and not command.interact_pressed
		and not command.unarmed_pressed
		and walk_direction == _walk_was
		and look_direction == _look_was
		and walk_strength == _strength_was
		and aim == command.aim
		and fire == command.fire
		and jump == command.jump
		and crouch == command.crouch
		and sprint == command.sprint
	):
		_repeat = true
		return command
	_repeat = false
	command.clear()
	command.set_from_world(walk_direction, look_direction, walk_strength)
	command.aim = aim
	command.fire = fire
	command.fire_pressed = fire_pressed
	command.jump = jump
	command.jump_pressed = jump_pressed
	command.crouch = crouch
	command.sprint = sprint
	command.reload_pressed = reload_pressed
	command.interact_pressed = interact_pressed
	command.unarmed_pressed = unarmed_pressed
	_built = true
	_walk_was = walk_direction
	_look_was = look_direction
	_strength_was = walk_strength
	return command


func repeats(command_handed: PlayerCommand) -> bool:
	return _repeat and command_handed == _command


## True when it asks for nothing: no walk, no aim, no trigger, no jump, crouch or sprint.
func is_still() -> bool:
	return walk_direction == Vector3.ZERO and not aim and not fire and not jump and not crouch


## Lets go of everything: stands still, looks level, no aim, no trigger.
func release() -> void:
	walk_direction = Vector3.ZERO
	walk_strength = 1.0
	look_direction = Vector3.ZERO
	aim = false
	fire = false
	jump = false
	crouch = false
	sprint = false
	reload = false
	interact = false
	unarmed = false

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

var _fire_was := false
var _jump_was := false


func sample() -> PlayerCommand:
	var command := _command
	command.clear()
	command.set_from_world(walk_direction, look_direction, walk_strength)
	command.aim = aim
	command.fire = fire
	command.fire_pressed = fire and not _fire_was
	_fire_was = fire
	command.jump = jump
	command.jump_pressed = jump and not _jump_was
	_jump_was = jump
	command.crouch = crouch
	command.sprint = sprint
	return command


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

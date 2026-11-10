class_name PlayerCommand
extends RefCounted
## What one physics tick of a player asks for: the stick, the camera's heading and pitch, the held
## buttons, the presses since the last command and, when a shot goes off, where it starts and where
## it points. The same object drives a body offline, on a client that predicts and on the server
## (issue #901 makes `Player.step(command, delta)` read it); `CommandCodec` writes it to the wire.
##
## A field added here travels only once `CommandCodec` writes it (and `NetWire.VERSION` goes up).

## Set by whoever sends it (a client numbers its commands from 1); 0 offline.
var seq := 0
## The stick, -1..1 on each axis, not rotated by the camera (x right, y forward).
var move := Vector2.ZERO
## The camera's heading, radians (0 faces -Z).
var yaw := 0.0
## The camera's look up (positive) or down, radians, held to a quarter turn either way.
var pitch := 0.0

# Held buttons.
var sprint := false
var walk := false
## Held while the player is crouched (the input turns the crouch toggle into a held bit).
var crouch := false
var aim := false
var fire := false
var jump := false

# Pressed since the last command (a press survives two commands arriving together).
var jump_pressed := false
var fire_pressed := false
var interact_pressed := false
var ragdoll_pressed := false

# The shot block.
## A shot left the muzzle this tick: `origin`, `shot_yaw`, `shot_pitch` and `view_tick` say which.
var has_shot := false
## Where the crosshair ray starts (the camera), metres.
var origin := Vector3.ZERO
## The crosshair ray's heading and pitch, radians.
var shot_yaw := 0.0
var shot_pitch := 0.0
## The server tick of the snapshot the shooter was looking at (the low 16 bits travel).
var view_tick := 0


## The command as the server will read it (the decode of its encode), for a client that predicts
## with the server's numbers; null when a number in it is not finite.
static func quantized(command: PlayerCommand) -> PlayerCommand:
	return CommandCodec.quantized(command)


## Every number is finite (a NaN or an infinity never reaches the wire or a body).
func all_finite() -> bool:
	return (
		move.is_finite()
		and is_finite(yaw)
		and is_finite(pitch)
		and origin.is_finite()
		and is_finite(shot_yaw)
		and is_finite(shot_pitch)
	)

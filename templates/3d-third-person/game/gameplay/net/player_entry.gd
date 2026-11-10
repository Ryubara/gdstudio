class_name PlayerEntry
extends RefCounted
## One player as a TICK carries it (12 bytes, `SnapshotCodec`): what another screen needs to draw
## the body (where, facing, the animation state, the locomotion flags, the aim pitch). Velocity,
## the aim and crouch amounts and the timers are not sent: a client derives them.

## The player's place in the game, 0 to `NetLimits.MAX_PLAYERS` - 1.
var slot := 0
## Metres (centimetres on the wire, `NetLimits.POSITION_RANGE` either way).
var position := Vector3.ZERO
## The body's facing, radians.
var yaw := 0.0
## `Player.state` (a byte).
var state := 0
var crouch := false
var aim := false
var sprint := false
## Off the floor.
var air := false
## Off the floor and going up.
var rising := false
var dead := false
## The aim's look up or down, radians (a signed byte, about 1.4 degrees a step).
var pitch := 0.0
## The player's name; only a WELCOME carries it (a TICK does not).
var player_name := ""


func all_finite() -> bool:
	return position.is_finite() and is_finite(yaw) and is_finite(pitch)

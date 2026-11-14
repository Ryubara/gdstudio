class_name CharacterController
extends Node
## What decides a character's next physics tick. The body asks for one `PlayerCommand` a tick
## (`sample()`) and steps it; where the command comes from is this node's business: the keys and
## the camera (`PlayerInput`), a plan (an AI), a recording (a test). On its own it asks for
## nothing, so a body with this node stands still.
##
## The contract of `sample()`: it is called once per physics tick by the body, and a press
## (`jump_pressed`, `fire_pressed`, `interact_pressed`, `ragdoll_pressed`) is true in exactly one
## returned command. A controller that returns a command it made earlier (it thinks less often
## than the body steps) calls `PlayerCommand.clear_edges()` on it after the first time.
##
## The returned command is this node's own and is written again on the next call: copy it
## (`PlayerCommand.clone()`) to keep it.

## On: the body takes its lean tick (`CharacterLean`) on the ticks it only walks or stands, the
## same result with fewer modules run. An AI's controller turns it on; a human's, a network's and a
## test's leave it off, so the body they drive steps exactly the full tick.
var lean_step := false
## On: a body this drives that reverses or cuts off at a run is moved by the clip's own root
## (`CharacterTurnMotion`), committed to it until its turn is made. An AI's controller turns it
## off, so its body keeps to the navigator's path (a reversal carries a body 3.7 m past the point
## it turned at from a jog and 6.3 m from a sprint, and a pivot cuts its corner by 0.58 m).
var turn_clips := true

var _command := PlayerCommand.new()


## The command for this physics tick.
func sample() -> PlayerCommand:
	return _command


## True when `command` is the one the last `sample()` handed out and it was not written since the
## call before (the body then keeps the copy it made: an AI's command between its thinks). False
## here: a human's, a network's and a test's command is copied on every step.
func repeats(_command_handed: PlayerCommand) -> bool:
	return false


## Where the person who watches this character is (the local camera), for what only matters to
## the eye (how far a death may be a ragdoll). `Vector3.INF`: nobody watches here (an AI on a
## server, a test, a body stepped from the network).
func viewer_position() -> Vector3:
	return Vector3.INF

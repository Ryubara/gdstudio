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

var _command := PlayerCommand.new()


## The command for this physics tick.
func sample() -> PlayerCommand:
	return _command


## Where the person who watches this character is (the local camera), for what only matters to
## the eye (how far a death may be a ragdoll). `Vector3.INF`: nobody watches here (an AI on a
## server, a test, a body stepped from the network).
func viewer_position() -> Vector3:
	return Vector3.INF

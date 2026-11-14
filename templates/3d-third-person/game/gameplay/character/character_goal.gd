## Where a body is asked to go. A stepped body's goal is its last command's (`Character.goal_speed`,
## `direction`); a body drawn from the network that never steps (a puppet) has no command, so its
## goal is `motion`, the velocity its drawn motion heads for, which whoever places it sets
## (`PlayerPuppet.make` turns on `from_motion`, `RemotePlayers` sets `motion`; gdstudio #1420).
class_name CharacterGoal
extends RefCounted

## On for a body that never steps (a puppet): its goal is `motion`.
var from_motion := false
## The velocity, m/s, a body with `from_motion` heads for.
var motion := Vector3.ZERO


## The ground speed of `motion`, m/s.
func speed() -> float:
	return Vector2(motion.x, motion.z).length()


## The way on the ground `body` is asked to go (not normalized; zero for no move): its last
## command's, or `motion`'s for a body that never steps. `GaitTransitions` reads it.
func direction(body: Character) -> Vector3:
	if from_motion:
		return Vector3(motion.x, 0.0, motion.z)
	return body.last_command.world_move()

class_name RouteController
extends CharacterController
## A scripted controller, as an AI's will be: it walks its character through `points` in order,
## one command a tick built from world directions (`PlayerCommand.set_from_world`), and stands
## still after the last. It reads no input and no camera.

## How near a point counts as reached (metres, on the ground plane).
const REACH := 0.3

## The points to walk through, in the world.
var points: PackedVector3Array = []
## How many points were reached.
var reached := 0


func sample() -> PlayerCommand:
	var command := _command
	command.clear()
	var body := get_parent() as Node3D
	if body == null or reached >= points.size():
		return command
	var way := points[reached] - body.global_position
	way.y = 0.0
	if way.length() < REACH:
		reached += 1
		return command
	command.set_from_world(way.normalized())
	return command

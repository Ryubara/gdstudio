class_name ScriptedController
extends CharacterController
## A controller a test writes: `plan` (a Callable of the tick number, from 0, answering a
## `PlayerCommand`) or, with no plan, `next`, whose presses are cleared after each sample so a press
## is one command. `install` puts one in place of a player's `PlayerInput`.

var next := PlayerCommand.new()
var plan := Callable()
## Samples taken.
var ticks := 0


## Frees `player`'s controller and makes a `ScriptedController` its controller.
static func install(player: Player) -> ScriptedController:
	var old := player.controller
	if old != null:
		if old.get_parent() == player:
			player.remove_child(old)
		old.free()
	var scripted := ScriptedController.new()
	scripted.name = "ScriptedController"
	player.add_child(scripted)
	player.controller = scripted
	return scripted


func sample() -> PlayerCommand:
	if plan.is_valid():
		_command.copy_from(plan.call(ticks))
	else:
		_command.copy_from(next)
		next.clear_edges()
	ticks += 1
	return _command

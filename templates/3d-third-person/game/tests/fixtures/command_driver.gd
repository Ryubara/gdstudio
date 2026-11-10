class_name CommandDriver
extends RefCounted
## Steps characters by commands and nothing else, as a server will: it turns a body's own physics
## processing off and calls `step()` once a physics frame with the physics step. No input action
## is pressed and no controller is asked.


## The physics step, from the project's tick rate.
static func tick_seconds() -> float:
	return 1.0 / Engine.physics_ticks_per_second


## Takes `player` over: frees its controller and stops it stepping itself.
static func take(player: Player) -> void:
	if player.controller != null:
		player.controller.queue_free()
		player.controller = null
	player.set_physics_process(false)


## Steps every body in `players` with a copy of `command` for `count` physics ticks. The presses
## of the command are stepped once, on the first tick. `each_tick`, when given, is called after
## every tick with its number (from 0).
static func run(
	tree: SceneTree,
	players: Array[Player],
	command: PlayerCommand,
	count: int,
	each_tick := Callable()
) -> void:
	var stepped := command.clone()
	for tick in count:
		await tree.physics_frame
		for player in players:
			player.step(stepped, tick_seconds())
		stepped.clear_edges()
		if each_tick.is_valid():
			each_tick.call(tick)


## A command that walks along `direction` in the world (flat), looking along `look` when it is
## not zero.
static func walking(direction: Vector3, look := Vector3.ZERO) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.set_from_world(direction, look)
	return command

class_name CirclingController
extends CharacterController
## The plan of a predicting client under test: circles of `radius` round `start`, a lap every
## `lap_seconds`, sprinting every other lap and jumping every `jump_every` seconds, for `seconds`;
## then it stands, so the gap to the server can be read once both bodies settle. Counted in ticks
## (`NetLimits.TICK_RATE`), never the clock, so a run repeats. Used by the native bot
## (`tools/net/predict_bot.gd`) and the browser's `NetPlayProbe`; `stop()` ends the walk early.

## The circle's radius, metres, and seconds a lap.
@export var radius := 3.0
@export var lap_seconds := 6.0
## Seconds between two jumps.
@export var jump_every := 3.0
## Seconds of walking before it stands.
@export var seconds := 30.0
## Whether every other lap sprints (off: every lap runs, and overshoots the circle less).
@export var sprints := true

## The body steered (its position and view are read).
var body: Character
## The centre of the circles (set it where the body starts).
var start := Vector3.ZERO
## Ticks sampled since `restart`.
var tick := 0


## Starts the plan again from `at`.
func restart(at: Vector3) -> void:
	start = at
	tick = 0


## Stands from the next tick on.
func stop() -> void:
	seconds = minf(seconds, float(tick) / NetLimits.TICK_RATE)


## Whether the walk is over (the body stands).
func is_standing() -> bool:
	return float(tick) / NetLimits.TICK_RATE >= seconds


func sample() -> PlayerCommand:
	var command := _command
	command.clear()
	var at := float(tick) / NetLimits.TICK_RATE
	tick += 1
	if at >= seconds or body == null:
		command.yaw = body.view_yaw if body != null else 0.0
		return command
	var angle := TAU * at / lap_seconds
	var target := start + Vector3(cos(angle), 0.0, sin(angle)) * radius
	var way := target - body.global_position
	way.y = 0.0
	var ahead := Vector3(-sin(angle), 0.0, cos(angle))
	command.set_from_world(way + ahead, ahead)
	command.sprint = sprints and int(at / lap_seconds) % 2 == 1
	var jump := tick % roundi(jump_every * NetLimits.TICK_RATE) == 0
	command.jump = jump
	command.jump_pressed = jump
	return command

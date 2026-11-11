class_name PlayerBot
extends Node
## A player that is a program, for tests, captures and probes of online play (`--bot` after `--`,
## `?bot` in a page's address: `OnlineMain` adds one). It presses the input actions a person would
## (`Input.action_press`) and turns the camera the way the mouse does (`PlayerCamera.orbit`), so the
## player's own `PlayerInput` samples the commands; nothing reaches the body another way, and the
## server hears what a person's keys would send.
##
## Two plans, counted in physics steps (never the clock), so a run repeats:
## - `ROUTE` walks to each point of `route`, faces `door_side` and presses interact (the door of
##   the template's map opens), comes back to `stand_at`, turns `miss_degrees` beside the nearest
##   other player, aims and fires `shots` past them, then stands facing them.
## - `WATCH` keeps the nearest other player (a puppet of `remote_players`) in the middle of the view
##   and, `fire_after` seconds after it first sees one, aims at its chest and fires until it is
##   down.
## A bot whose player is dead lets go of every key and waits.

enum Plan { ROUTE, WATCH }

## How close to a point counts as there, metres.
const ARRIVE_DISTANCE := 0.6
## Within this many degrees of the way to a point the bot walks; past it, it turns first.
const WALK_CONE_DEGREES := 35.0
## Steps a fire or interact press is held, and steps between two shots.
const PRESS_STEPS := 2
const SHOT_GAP_STEPS := 24
## Height above the feet the bot looks and shoots at (the chest of the template's character).
const CHEST_HEIGHT := 1.2

@export var plan := Plan.ROUTE
## Degrees the camera turns at most a physics step (a quick mouse hand).
@export_range(0.5, 30.0, 0.5, "suffix:deg") var turn_speed := 6.0

@export_group("Route")
## The points walked in turn, in the map's coordinates (the template's: to the main door).
@export var route := PackedVector3Array([Vector3(7.0, 0.0, -5.5), Vector3(13.0, 0.0, -8.0)])
## Where the bot looks when it presses interact at the last point (the door's middle).
@export var door_side := Vector3(13.0, 1.2, -9.5)
## Seconds it waits after interact (the door opening).
@export_range(0.0, 10.0, 0.1, "suffix:s") var door_wait := 1.5
## Where it comes back to before it shoots.
@export var stand_at := Vector3(1.0, 0.0, -4.0)
## Shots fired past the other player, and how far beside them, degrees.
@export_range(0, 30) var shots := 3
@export_range(0.0, 90.0, 1.0, "suffix:deg") var miss_degrees := 25.0

@export_group("Watch")
## Seconds after the first sight of another player before the bot fires at it.
@export_range(0.0, 120.0, 0.5, "suffix:s") var fire_after := 14.0

@export_group("Nodes")
## The body whose input the bot presses.
@export var player: Player
## The camera the bot turns.
@export var camera_rig: PlayerCamera
## Where the other players are drawn (an online game); empty sees no other player.
@export var remote_players: RemotePlayers

## The step of the plan it is on (`ROUTE`: the index of its stage), for tests and probes.
var stage := 0
## Physics steps since the plan began.
var steps := 0
## Shots fired so far.
var fired := 0

var _waited := 0
var _held: Dictionary[StringName, bool] = {}
var _press_steps := 0
var _seen_at := -1


func _ready() -> void:
	# Before the client samples the input (`NetClient`, -20) and before the body steps.
	process_physics_priority = -30


func _exit_tree() -> void:
	release_all()


func _physics_process(_delta: float) -> void:
	if player == null or camera_rig == null:
		return
	steps += 1
	if player.is_dead():
		release_all()
		return
	_end_press()
	match plan:
		Plan.ROUTE:
			_route_step()
		Plan.WATCH:
			_watch_step()


## Lets go of every action the bot holds.
func release_all() -> void:
	for action: StringName in _held:
		if InputMap.has_action(action):
			Input.action_release(action)
	_held.clear()
	_press_steps = 0


## The nearest other player drawn on this screen, or null.
func nearest_other() -> Player:
	if remote_players == null:
		return null
	var best: Player = null
	var best_distance := INF
	for slot in remote_players.slots():
		var puppet := remote_players.puppet_at(slot)
		if puppet == null:
			continue
		var distance := puppet.global_position.distance_squared_to(player.global_position)
		if distance < best_distance:
			best = puppet
			best_distance = distance
	return best


## Turns the camera toward `point` by at most `turn_speed` degrees, with `beside` degrees added to
## the heading; the degrees still to turn about the up axis. The way is measured from where the
## crosshair's ray starts (an over-the-shoulder lens is shifted to the side), so a shot fired once
## it faces the point goes through it.
func face(point: Vector3, beside := 0.0) -> float:
	var way := point - _ray_origin()
	var flat := Vector2(way.x, way.z).length()
	if flat < 0.01:
		return 0.0
	var heading := rad_to_deg(atan2(-way.x, -way.z)) + beside
	var turn := wrapf(heading - camera_rig.yaw, -180.0, 180.0)
	# The orbit's pitch is positive looking down.
	var pitch := -rad_to_deg(atan2(way.y, flat))
	var lift := pitch - camera_rig.pitch
	camera_rig.orbit(
		Vector2(-clampf(turn, -turn_speed, turn_speed), clampf(lift, -turn_speed, turn_speed))
	)
	return turn - clampf(turn, -turn_speed, turn_speed)


# One step toward `point` on the ground: turns, walks inside the cone; true once there.
func _walk_to(point: Vector3) -> bool:
	var flat := player.global_position - point
	flat.y = 0.0
	if flat.length() <= ARRIVE_DISTANCE:
		_hold(&"move_forward", false)
		return true
	var left := face(Vector3(point.x, player.global_position.y + CHEST_HEIGHT, point.z))
	_hold(&"move_forward", absf(left) <= WALK_CONE_DEGREES)
	return false


func _route_step() -> void:
	var legs := route.size()
	if stage < legs:
		if _walk_to(route[stage]):
			stage += 1
		return
	var at := stage - legs
	match at:
		0:  # Face the door, press interact.
			if absf(face(door_side)) < 1.0:
				_press(&"interact")
				_next()
		1:  # The door opens.
			_wait_then_next(door_wait)
		2:
			if _walk_to(stand_at):
				_next()
		3:  # Beside the other player, aimed.
			var other := nearest_other()
			var turned := absf(face(_chest_of(other), miss_degrees)) < 1.0 if other else true
			_hold(&"aim", true)
			if turned:
				_wait_then_next(0.5)
		4:
			_hold(&"aim", true)
			if fired >= shots:
				_next()
			elif _waited % SHOT_GAP_STEPS == 0:
				_press(&"fire")
				fired += 1
			_waited += 1
		_:  # Stands, facing the other player.
			_hold(&"aim", false)
			var other := nearest_other()
			if other != null:
				face(_chest_of(other))


func _watch_step() -> void:
	var other := nearest_other()
	if other == null:
		_hold(&"aim", false)
		return
	if _seen_at < 0:
		_seen_at = steps
	var left := face(_chest_of(other))
	var firing := steps - _seen_at >= roundi(fire_after * Engine.physics_ticks_per_second)
	firing = firing and not other.is_dead()
	_hold(&"aim", firing)
	stage = 1 if firing else 0
	if firing and absf(left) < 2.0 and (steps - _seen_at) % SHOT_GAP_STEPS == 0:
		_press(&"fire")
		fired += 1


# Where the crosshair's ray starts: the camera's ray through the middle of the screen, or the
# body's chest without a camera.
func _ray_origin() -> Vector3:
	var camera := camera_rig.camera
	if camera == null or not camera.is_inside_tree():
		return player.global_position + Vector3.UP * CHEST_HEIGHT
	return camera.project_ray_origin(camera.get_viewport().get_visible_rect().size / 2.0)


func _chest_of(other: Player) -> Vector3:
	return other.global_position + Vector3.UP * CHEST_HEIGHT


func _next() -> void:
	stage += 1
	_waited = 0


func _wait_then_next(seconds: float) -> void:
	_waited += 1
	if _waited >= roundi(seconds * Engine.physics_ticks_per_second):
		_next()


# Holds or lets go of `action`. A hold is pressed again when the action came up on its own: the
# engine lets go of every pressed action when the window loses the focus, as a window on another
# desktop (`gds godot`) does now and then.
func _hold(action: StringName, down: bool) -> void:
	if not InputMap.has_action(action):
		return
	if down and not (_held.get(action, false) and Input.is_action_pressed(action)):
		Input.action_press(action)
		_held[action] = true
	elif not down and _held.get(action, false):
		Input.action_release(action)
		_held.erase(action)


# A press of `action` held for `PRESS_STEPS` steps.
func _press(action: StringName) -> void:
	_hold(action, true)
	_press_steps = PRESS_STEPS
	_held[action] = true


func _end_press() -> void:
	if _press_steps <= 0:
		return
	_press_steps -= 1
	if _press_steps == 0:
		_hold(&"fire", false)
		_hold(&"interact", false)

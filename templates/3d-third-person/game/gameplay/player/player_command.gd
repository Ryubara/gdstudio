class_name PlayerCommand
extends RefCounted
## What one physics tick of a player asks for: the stick, the camera's heading and pitch, the held
## buttons, the presses since the last command and, when a shot goes off, where it starts and where
## it points. The same object drives a body offline, on a client that predicts and on the server
## (`Player.step(command, delta)` reads it); `CommandCodec` writes it to the wire.
##
## A field added here travels only once `CommandCodec` writes it (and `NetWire.VERSION` goes up).

## Set by whoever sends it (a client numbers its commands from 1); 0 offline.
var seq := 0
## The stick in the view's own axes, -1..1 each and no longer than 1 together: x to the view's
## right, y forward (away from the camera). `Character.step` turns it by `yaw`.
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
## The reload button, the next and previous weapon buttons and the switch to the empty hands (and
## back), pressed since the last command (`WeaponLoadout`).
var reload_pressed := false
var next_weapon_pressed := false
var previous_weapon_pressed := false
var unarmed_pressed := false

# The shot block.
## A shot may leave the muzzle this tick (the fire button was pressed or is buffered and the weapon
## is ready): `origin`, `shot_yaw`, `shot_pitch` and `view_tick` say where it would go. Without it
## a body that shoots uses its eye point and `yaw` and `pitch`.
var has_shot := false
## Where the crosshair ray starts (the camera), metres.
var origin := Vector3.ZERO
## The crosshair ray's heading and pitch, radians. Not the same as `yaw` and `pitch` in general:
## an over-the-shoulder view shifts the lens, and the ray goes through the middle of the screen.
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


## Copies every field of `other` into this command and returns this one. A controller hands out
## one command it writes again each tick, so whoever keeps a command copies it.
func copy_from(other: PlayerCommand) -> PlayerCommand:
	seq = other.seq
	move = other.move
	yaw = other.yaw
	pitch = other.pitch
	sprint = other.sprint
	walk = other.walk
	crouch = other.crouch
	aim = other.aim
	fire = other.fire
	jump = other.jump
	jump_pressed = other.jump_pressed
	fire_pressed = other.fire_pressed
	interact_pressed = other.interact_pressed
	ragdoll_pressed = other.ragdoll_pressed
	reload_pressed = other.reload_pressed
	next_weapon_pressed = other.next_weapon_pressed
	previous_weapon_pressed = other.previous_weapon_pressed
	unarmed_pressed = other.unarmed_pressed
	has_shot = other.has_shot
	origin = other.origin
	shot_yaw = other.shot_yaw
	shot_pitch = other.shot_pitch
	view_tick = other.view_tick
	return self


## A new command with the same fields.
func clone() -> PlayerCommand:
	return PlayerCommand.new().copy_from(self)


## Lets go of everything: no push, no button, no press, no shot. The view (`yaw`, `pitch`) and
## `seq` stay.
func clear() -> void:
	move = Vector2.ZERO
	sprint = false
	walk = false
	crouch = false
	aim = false
	fire = false
	jump = false
	clear_edges()


## Takes the presses and the shot block out, and keeps the push, the view and the held buttons.
## A press is true in exactly one command a body steps: whoever steps a command again (a server
## repeating the last one, a controller that thinks less often than the body steps) calls this
## on it first, or the body jumps, shoots and uses a door on every repeat.
func clear_edges() -> void:
	jump_pressed = false
	fire_pressed = false
	interact_pressed = false
	ragdoll_pressed = false
	reload_pressed = false
	next_weapon_pressed = false
	previous_weapon_pressed = false
	unarmed_pressed = false
	has_shot = false
	origin = Vector3.ZERO
	shot_yaw = 0.0
	shot_pitch = 0.0
	view_tick = 0


## Keeps the presses of `earlier`, a command that was never stepped, in this later one (two
## commands arrived in one tick and only this one is stepped). When this one has no shot block
## it takes `earlier`'s.
func merge_edges_from(earlier: PlayerCommand) -> void:
	jump_pressed = jump_pressed or earlier.jump_pressed
	fire_pressed = fire_pressed or earlier.fire_pressed
	interact_pressed = interact_pressed or earlier.interact_pressed
	ragdoll_pressed = ragdoll_pressed or earlier.ragdoll_pressed
	reload_pressed = reload_pressed or earlier.reload_pressed
	next_weapon_pressed = next_weapon_pressed or earlier.next_weapon_pressed
	previous_weapon_pressed = previous_weapon_pressed or earlier.previous_weapon_pressed
	unarmed_pressed = unarmed_pressed or earlier.unarmed_pressed
	if earlier.has_shot and not has_shot:
		has_shot = true
		origin = earlier.origin
		shot_yaw = earlier.shot_yaw
		shot_pitch = earlier.shot_pitch
		view_tick = earlier.view_tick


## Writes the view and the push from directions in the world, for a controller with no stick and
## no camera (an AI): it looks along `look` and walks along `walk_direction` (flat, any length)
## as hard as `strength` (0 to 1). A `look` of zero leaves the view level along -Z, and a body
## that is not aiming turns to where it walks on its own.
func set_from_world(walk_direction: Vector3, look := Vector3.ZERO, strength := 1.0) -> void:
	var angles := CommandCodec.direction_angles(look)
	yaw = angles.x
	pitch = angles.y
	var flat := Vector2(walk_direction.x, walk_direction.z)
	if not flat.is_finite() or flat.length_squared() < 0.000001:
		move = Vector2.ZERO
		return
	flat = flat.normalized() * clampf(strength, 0.0, 1.0)
	# The view's right is (cos yaw, -sin yaw) and its forward (-sin yaw, -cos yaw) on (x, z).
	move = Vector2(flat.x * cos(yaw) - flat.y * sin(yaw), -flat.x * sin(yaw) - flat.y * cos(yaw))


## The flat direction in the world `move` asks for, as long as the push (never longer than 1).
func world_move() -> Vector3:
	var push := move.limit_length(1.0)
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return right * push.x + forward * push.y

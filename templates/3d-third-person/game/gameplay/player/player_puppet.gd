class_name PlayerPuppet
extends RefCounted
## A `Player` drawn from the network: another player's body on this screen (`RemotePlayers`), the
## same `player.tscn` as the local one so it looks, stands and animates the same
## (`multiplayer.md#appearance`). `Player.make_puppet()` turns one into a puppet and
## `Player.puppet_to()` places it; the functions here are the work, static and keeping nothing.
##
## A puppet has no input (its `PlayerInput` is freed), no camera and no simulation (its
## `_physics_process` returns at once, so `step` never runs: no move, no weapon tick, no pickup),
## is in no group a HUD, minimap or camera zone looks for, and no other body meets it (collision
## layer 0; the mask keeps the world, for the floor test below). Its parts that draw read what
## `place` writes, exactly what they read from a stepped body: `state` (the clip), `velocity`
## (`ground_speed()`, the locomotion blend and the footsteps), `aim_amount`, `view_pitch` and
## `view_yaw` (the aim pose, the barrel's pitch and the aim layer's turn off the body),
## `crouching`, `is_sprinting()`, the prone amount, and the engine's floor contact, which only a
## move finds, so each placing ends with a short move down onto the floor (or up off it while the
## entry says it is in the air) and puts the body back on the entry's point.

## Metres the floor test starts above the point and moves down through it (the point is in whole
## centimetres, up to half of one inside the floor).
const FLOOR_PROBE := 0.03


## Makes `player` a puppet; call before it enters the tree (its `_ready` then joins no group and
## goes to no spawn point).
static func make(player: Player) -> void:
	player.is_puppet = true
	player.start_at_spawn = false
	player.input_enabled = false
	player.ragdoll_by_command = false
	player.goal_from_motion = true
	player.collision_layer = 0
	player.collision_mask = PhysicsLayers.WORLD
	var input := player.controller
	player.controller = null
	if input != null:
		if input.get_parent() == player:
			player.remove_child(input)
		input.free()


## Puts `puppet` where `entry` says, moving at `moving` (metres a second), and brings the parts
## that are eased on a stepped body (the aim pose, lying down) along by `delta`.
static func place(puppet: Player, entry: PlayerEntry, moving: Vector3, delta: float) -> void:
	# A dead puppet lies in its own ragdoll (its DIED event started it); a snapshot that says dead
	# before the event came, or alive after a REVIVED that never came, does it here instead.
	if entry.dead:
		if not puppet.is_dead():
			puppet.velocity = moving
			puppet.die()
		return
	if puppet.is_dead():
		puppet.revive_at(entry.position)
	_touch_floor(puppet, entry.position, entry.air)
	puppet.global_position = entry.position
	puppet.velocity = moving
	# The goal the animation's starts and stops read: none once the player asked for no move, else
	# the drawn motion (`RemotePlayers` sets where the snapshots head after this).
	puppet.motion_goal = Vector3.ZERO if entry.halt else moving
	puppet.facing = entry.yaw
	# The view along the body, turned by the aim's heading off it while aiming (0 otherwise), so
	# the aim layer turns the puppet's upper body as it turns the stepped one.
	puppet.view_yaw = entry.yaw - PI + entry.aim_yaw
	puppet.view_pitch = entry.pitch
	puppet._present_facing()
	puppet._sprinting = entry.sprint
	if puppet.crouching != entry.crouch:
		puppet.crouching = entry.crouch
		puppet.crouch_changed.emit(entry.crouch)
	if puppet.aiming != entry.aim:
		puppet.aiming = entry.aim
		puppet.aim_held = entry.aim
		puppet.aim_changed.emit(entry.aim)
	var tuning := puppet.tuning
	puppet.aim_amount = move_toward(
		puppet.aim_amount, 1.0 if entry.aim else 0.0, delta / maxf(tuning.aim_pose_time, 0.001)
	)
	var shape_before := Vector2(puppet._crouch_amount, puppet._prone.amount)
	puppet._crouch_amount = move_toward(
		puppet._crouch_amount, 1.0 if entry.crouch else 0.0, delta / maxf(tuning.crouch_time, 0.001)
	)
	var lying := entry.state == Character.State.PRONE
	if lying != puppet._prone.down:
		puppet._prone.down = lying
		puppet.prone_changed.emit(lying)
	var prone_time := puppet.prone_tuning.enter_time if lying else puppet.prone_tuning.exit_time
	puppet._prone.amount = move_toward(
		puppet._prone.amount, 1.0 if lying else 0.0, delta / maxf(prone_time, 0.001)
	)
	if Vector2(puppet._crouch_amount, puppet._prone.amount) != shape_before:
		puppet._fit_body()
	puppet.state = entry.state as Character.State
	# A vault or a mantle: its plan and clip are worked out here (nothing about it is sent).
	PuppetVault.follow(puppet, delta, PhysicsLayers.WORLD)


## Puts `puppet` at `spot` at once (a join, a warp): nothing eased is left over.
static func warp(puppet: Player, entry: PlayerEntry) -> void:
	puppet.global_position = entry.position
	puppet.aim_amount = 1.0 if entry.aim else 0.0
	puppet._crouch_amount = 1.0 if entry.crouch else 0.0
	puppet._prone.down = entry.state == Character.State.PRONE
	puppet._prone.amount = 1.0 if puppet._prone.down else 0.0
	puppet._fit_body()
	place(puppet, entry, Vector3.ZERO, 0.0)
	puppet.reset_physics_interpolation()


# The engine's floor contact for a body that is not moved by physics: a short move through the
# point (down on the ground, up in the air), then the body goes back to the point.
static func _touch_floor(puppet: Player, spot: Vector3, air: bool) -> void:
	var kept := puppet.velocity
	var ticks := float(Engine.physics_ticks_per_second)
	if air:
		puppet.global_position = spot
		puppet.velocity = Vector3.UP * FLOOR_PROBE * ticks
	else:
		puppet.global_position = spot + Vector3.UP * FLOOR_PROBE
		puppet.velocity = Vector3.DOWN * 2.0 * FLOOR_PROBE * ticks
	puppet.move_and_slide()
	puppet.velocity = kept

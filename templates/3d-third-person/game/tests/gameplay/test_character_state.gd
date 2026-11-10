# `CharacterState`: everything a step reads from the tick before, taken with
# `Player.state_snapshot()` and put back with `Player.restore()`. A body put back to an earlier
# tick and stepped with the same commands goes the same way again.
extends GdUnitTestSuite

## The `Player` variables that are not step state, each with why. A new variable of the body must
## be named here or in `CharacterState.FIELDS`, or the suite fails.
const NOT_STATE := {
	&"tuning": "an export",
	&"start_at_spawn": "an export",
	&"model": "an export (a node)",
	&"controller": "an export (a node)",
	&"weapon": "an export (a node)",
	&"ragdoll_body": "an export (a node)",
	&"ragdoll": "an export; death is an event (die, revive), not restored",
	&"ragdoll_key": "an export",
	&"ragdoll_by_command": "an export",
	&"input_enabled": "an export",
	&"died_by_clip": "how a death looks; death is not restored",
	&"items": "what the character holds: the game's state, not the step's",
	&"last_command": "written again by every step before it is read",
	&"slide": "an object; its step state is CharacterState.slide",
	&"_stand_probe": "a shape made for a query",
	&"_spawn_rng": "only respawn() reads it, and the step never calls that",
	&"_interactor": "a node",
	&"_body": "a node",
	&"_camera_target": "a node",
}

var _arena: PlayArena
var _player: Player
var _players: Array[Player] = []
var _trace: Array[Vector3] = []


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_arena.add_block(Vector2(0.0, -6.0), Vector3(4.0, 0.3, 2.0), 0.3)
	_player = _arena.add_player(Vector3.ZERO)
	CommandDriver.take(_player)
	_players = [_player]
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	AudioDrain.stop_all(_arena)


func _run(command: PlayerCommand, count: int) -> void:
	await CommandDriver.run(get_tree(), _players, command, count)


func _record(_tick: int) -> void:
	_trace.append(_player.global_position)
	_trace.append(_player.velocity)


# The second half of a walk: a turn, a jump, a crouch, an aim. Returns its trace.
func _second_half() -> Array[Vector3]:
	_trace = []
	var turn := CommandDriver.walking(Vector3(1.0, 0.0, -1.0))
	turn.sprint = true
	await CommandDriver.run(get_tree(), _players, turn, 30, _record)
	turn.jump = true
	turn.jump_pressed = true
	await CommandDriver.run(get_tree(), _players, turn, 40, _record)
	var low := CommandDriver.walking(Vector3.LEFT, Vector3(0.0, 0.0, -1.0))
	low.crouch = true
	low.aim = true
	await CommandDriver.run(get_tree(), _players, low, 50, _record)
	return _trace.duplicate()


func _largest_gap(a: Array[Vector3], b: Array[Vector3]) -> float:
	var gap := 0.0
	for index in a.size():
		gap = maxf(gap, a[index].distance_to(b[index]))
	return gap


func test_every_variable_of_the_body_is_step_state_or_named_as_not() -> void:
	var unclassified: Array[StringName] = []
	var both: Array[StringName] = []
	var names: Array[StringName] = []
	for property in _player.get_script().get_script_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var field: StringName = property["name"]
		names.append(field)
		var kept := CharacterState.FIELDS.has(field)
		if kept and NOT_STATE.has(field):
			both.append(field)
		elif not kept and not NOT_STATE.has(field):
			unclassified.append(field)
	assert_array(unclassified).is_empty()
	assert_array(both).is_empty()
	for field in CharacterState.FIELDS:
		assert_bool(names.has(field)).override_failure_message("no such member: " + field).is_true()
	for field: StringName in NOT_STATE:
		assert_bool(names.has(field)).override_failure_message("no such member: " + field).is_true()


func test_a_snapshot_holds_the_body_and_every_field() -> void:
	var command := CommandDriver.walking(Vector3.FORWARD)
	command.crouch = true
	await _run(command, 25)
	var kept := _player.state_snapshot()
	assert_vector(kept.position).is_equal(_player.global_position)
	assert_vector(kept.velocity).is_equal(_player.velocity)
	assert_int(kept.values.size()).is_equal(CharacterState.FIELDS.size())
	for index in CharacterState.FIELDS.size():
		var field := CharacterState.FIELDS[index]
		assert_that(kept.values[index]).override_failure_message(field).is_equal(_player.get(field))
	# A snapshot into an object that is kept makes no new one.
	assert_object(_player.state_snapshot(kept)).is_same(kept)


func test_restore_on_the_floor_goes_the_same_way_again() -> void:
	await _run(CommandDriver.walking(Vector3.FORWARD), 40)
	var kept := _player.state_snapshot()
	var first := await _second_half()
	_player.restore(kept)
	assert_vector(_player.global_position).is_equal(kept.position)
	var second := await _second_half()
	var gap := _largest_gap(first, second)
	print("restore on the floor: largest gap over 120 ticks %.9f m" % gap)
	assert_float(gap).is_less(0.001)


func test_restore_in_the_air_goes_the_same_way_again() -> void:
	var jump := CommandDriver.walking(Vector3.FORWARD)
	jump.jump = true
	jump.jump_pressed = true
	await _run(jump, 12)
	assert_bool(_player.is_on_floor()).is_false()
	var kept := _player.state_snapshot()
	var first := await _second_half()
	# From the floor back into the air: the engine's floor contact is not part of the state.
	assert_bool(_player.is_on_floor()).is_true()
	_player.restore(kept)
	var second := await _second_half()
	var gap := _largest_gap(first, second)
	print("restore in the air: largest gap over 120 ticks %.9f m" % gap)
	assert_float(gap).is_less(0.001)


func test_restore_puts_back_the_crouch_the_aim_and_the_timers() -> void:
	var low := CommandDriver.walking(Vector3.ZERO, Vector3.RIGHT)
	low.crouch = true
	low.aim = true
	await _run(low, 30)
	var kept := _player.state_snapshot()
	var height := _player.body_height()
	await _run(PlayerCommand.new(), 40)
	assert_bool(_player.crouching or _player.aiming).is_false()
	assert_float(_player.body_height()).is_greater(height + 0.3)
	_player.restore(kept)
	assert_bool(_player.crouching and _player.aiming).is_true()
	assert_float(_player.aim_amount).is_equal(1.0)
	assert_float(_player.body_height()).is_equal(height)
	var capsule := (_player.get_node("%Body") as CollisionShape3D).shape as CapsuleShape3D
	assert_float(capsule.height).is_equal_approx(height, 0.0001)
	assert_int(_player.state).is_equal(Player.State.CROUCH)


# Aims, presses fire on the first tick and steps `count` ticks. Returns the tick the shot left
# on and the way it flew (x, y, z), or an empty array when none left.
func _press_fire(count: int) -> Array:
	var seen: Array = []
	var tick_now: Array[int] = [0]
	var on_shot := func(shot: Projectile) -> void:
		seen.append(tick_now[0])
		seen.append(shot.velocity)
	_player.weapon.fired.connect(on_shot)
	var command := CommandDriver.walking(Vector3.ZERO, Vector3.FORWARD)
	command.aim = true
	command.fire = true
	command.fire_pressed = true
	await CommandDriver.run(
		get_tree(), _players, command, count, func(tick: int) -> void: tick_now[0] = tick + 1
	)
	_player.weapon.fired.disconnect(on_shot)
	return seen


func test_restore_puts_back_the_weapons_cooldown_and_its_place_in_the_spread() -> void:
	_player.weapon.spread = 5.0
	var aim := CommandDriver.walking(Vector3.ZERO, Vector3.FORWARD)
	aim.aim = true
	await _run(aim, 30)
	# A first shot, then ten ticks into its quarter second of cooldown.
	assert_array(await _press_fire(10)).has_size(2)
	var kept := _player.state_snapshot()
	assert_array(kept.weapon).has_size(2)
	assert_float(kept.weapon[0]).is_between(0.06, 0.11)
	# The next press waits for the rest of the cooldown, then the shot leaves, off the aim.
	var first := await _press_fire(40)
	assert_array(first).has_size(2)
	assert_int(first[0]).is_between(4, 8)
	await _run(aim, 40)
	_player.restore(kept)
	var second := await _press_fire(40)
	assert_array(second).has_size(2)
	# The same tick and the same turn off the aim. The shot starts at the muzzle, which the
	# animation holds (a few millimetres apart between the two runs), so the direction is the
	# same to a thousandth; another place in the spread's order would be degrees away.
	assert_int(second[0]).is_equal(first[0])
	assert_vector(second[1]).is_equal_approx(first[1], Vector3.ONE * 0.05)
	var third := await _press_fire(40)
	assert_float((third[1] as Vector3).distance_to(first[1])).is_greater(0.3)
	# A character with no weapon keeps an empty share and restores without one.
	_player.weapon = null
	assert_array(_player.state_snapshot(kept).weapon).is_empty()
	_player.restore(kept)

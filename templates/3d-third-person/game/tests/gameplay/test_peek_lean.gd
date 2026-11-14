# The peek lean around cover (gdstudio #1400): the command's lean bits tilt the upper body from the
# hips, so the eye point (where a shot without a crosshair ray leaves) goes about 0.35 m to the
# side while the feet stay; a shape along the bent spine is what a shot meets outside the upright
# capsule; a wall stops the lean short; a sprint, lying down, a jump and a death end it; the body
# walks slowly at most. A lean from behind a wall's edge sees and shoots a target the upright body
# cannot, on the server's bare body and on the dressed player. The keys (Q and E), the toggle
# setting, the pad's aim and d-pad and a touch control make the bits.
extends GdUnitTestSuite

const BODY := "res://gameplay/character/character.tscn"
const PLAYER := "res://gameplay/player/player.tscn"
## Where the wall's edge is (x), in front of the body at the origin facing -Z.
const EDGE_X := 0.25
const TARGET := Vector3(1.0, 1.5, -8.0)

var _arena: PlayArena
var _toggle_was: Variant = null


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)


func after_test() -> void:
	InputSim.release_all()
	if _toggle_was != null:
		Settings.set_value(PeekInput.SETTING, _toggle_was)
		_toggle_was = null
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


# A body of `scene` at the origin facing -Z, stepped by hand (`_step`).
func _body(scene := PLAYER) -> Character:
	var body: Character
	if scene == PLAYER:
		body = _arena.add_player(Vector3.ZERO)
		CommandDriver.take(body as Player)
	else:
		body = (load(scene) as PackedScene).instantiate() as Character
		_arena.add_child(body)
		body.facing = PI
		body.set_physics_process(false)
	await InputSim.ticks(get_tree(), 2)
	return body


func _step(body: Character, command: PlayerCommand, count: int, plan := Callable()) -> void:
	var stepped := command.clone()
	for tick in count:
		await get_tree().physics_frame
		if plan.is_valid():
			plan.call(stepped)
		body.step(stepped, CommandDriver.tick_seconds())
		stepped.clear_edges()


func _leaning(side: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.lean_left = side < 0
	command.lean_right = side > 0
	return command


func _eye(body: Character) -> Vector3:
	return (body.get_node("CameraTarget") as Node3D).global_position


func test_a_lean_tilts_the_eye_to_the_side_and_keeps_the_feet() -> void:
	var body := await _body()
	var feet := body.global_position
	var upright := _eye(body)
	await _step(body, _leaning(1), 6)
	# A fifth of a second to lean all the way: about half way after a tenth.
	assert_float(body.peek_motion.amount).is_between(0.4, 0.6)
	await _step(body, _leaning(1), 20)
	assert_float(body.peek_motion.amount).is_equal(1.0)
	var shift := _eye(body) - upright
	# The body faces -Z, so its right is +X.
	assert_float(shift.x).is_between(0.32, 0.37)
	assert_float(absf(shift.z)).is_less(0.01)
	assert_float(shift.y).is_between(-0.12, 0.0)
	var angle := body.peek_motion.full_angle(body, CharacterCapsule.eye_height(body))
	assert_float(rad_to_deg(angle)).is_between(25.0, 30.0)
	assert_vector(body.global_position).is_equal_approx(feet, Vector3.ONE * 0.001)
	await _step(body, _leaning(-1), 30)
	assert_float(body.peek_motion.amount).is_equal(-1.0)
	assert_float((_eye(body) - upright).x).is_between(-0.37, -0.32)
	await _step(body, PlayerCommand.new(), 15)
	assert_float(body.peek_motion.amount).is_equal(0.0)
	assert_vector(_eye(body)).is_equal_approx(upright, Vector3.ONE * 0.001)
	assert_vector(body.global_position).is_equal_approx(feet, Vector3.ONE * 0.001)


func test_a_held_lean_follows_the_tuning_changed_while_it_is_held() -> void:
	# A steady lean skips placing the eye again; a live change of the tuning places it again.
	var body := await _body()
	var upright := _eye(body)
	await _step(body, _leaning(1), 20)
	var tuning := body.peek_tuning
	var offset_was := tuning.side_offset
	tuning.side_offset = 0.2
	await _step(body, _leaning(1), 2)
	var shift := (_eye(body) - upright).x
	tuning.side_offset = offset_was
	assert_float(shift).is_between(0.18, 0.21)
	await _step(body, _leaning(1), 2)
	assert_float((_eye(body) - upright).x).is_between(0.32, 0.37)


func test_both_sides_at_once_lean_neither_way() -> void:
	var body := await _body()
	var both := _leaning(1)
	both.lean_left = true
	await _step(body, both, 20)
	assert_float(body.peek_motion.amount).is_equal(0.0)


func test_the_shape_stands_for_the_leaning_shoulders_and_head() -> void:
	var body := await _body()
	var shape := body.get_node("PeekShape") as CollisionShape3D
	assert_bool(shape.disabled).is_true()
	# Beside the upright capsule at the shoulders' height, a ray from the front meets nothing.
	var from := Vector3(0.45, 1.45, -3.0)
	var to := Vector3(0.45, 1.45, 3.0)
	assert_object(_ray(from, to)).is_null()
	await _step(body, _leaning(1), 20)
	assert_bool(shape.disabled).is_false()
	assert_object(_ray(from, to)).is_same(body)
	await _step(body, PlayerCommand.new(), 20)
	assert_bool(shape.disabled).is_true()
	assert_object(_ray(from, to)).is_null()


# What a shot from `from` to `to` meets, as a shot sees it: a body's shot hull gives the part on
# the line or is passed (`ShotHull.ray_as_shot`, kit #1431).
func _ray(from: Vector3, to: Vector3, exclude: Array[RID] = []) -> Object:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = exclude
	var space := _arena.get_world_3d().direct_space_state
	var hit := ShotHull.ray_as_shot(space, query, (to - from).normalized())
	return hit.collider if not hit.is_empty() else null


func test_a_wall_beside_the_body_stops_the_lean_short() -> void:
	var body := await _body()
	var feet := body.global_position
	var upright := _eye(body)
	var wall := _arena.add_block(Vector2(0.8, 0.0), Vector3(0.5, 3.0, 3.0), 3.0)
	await _step(body, _leaning(1), 30)
	var room := body.peek_motion.room
	assert_float(room).is_greater(0.1).is_less(0.95)
	assert_float(body.peek_motion.amount).is_equal(room)
	var shift := (_eye(body) - upright).x
	assert_float(shift).is_greater(0.03).is_less(0.32)
	# The leaning shape is clear of the wall, and the body was not pushed off its feet.
	var shape := body.get_node("PeekShape") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.transform = shape.global_transform
	# The body and its own shot hull (kit #1431), around it on every layer.
	query.exclude = ShotHull.rids_of(body)
	var met := _arena.get_world_3d().direct_space_state.intersect_shape(query, 4)
	assert_array(met).is_empty()
	assert_vector(body.global_position).is_equal_approx(feet, Vector3.ONE * 0.001)
	# The other way is open.
	await _step(body, _leaning(-1), 40)
	assert_float(body.peek_motion.amount).is_equal(-1.0)
	# Against the wall, it hardly leans into it at all.
	wall.position.x = 0.34 + 0.25 + 0.01
	await _step(body, _leaning(1), 40)
	assert_float(body.peek_motion.amount).is_less(0.35)
	assert_vector(body.global_position).is_equal_approx(feet, Vector3.ONE * 0.001)


func test_crouched_it_leans_and_walking_it_walks_slowly() -> void:
	var body := await _body()
	var upright := _eye(body)
	var crouched := _leaning(1)
	crouched.crouch = true
	await _step(body, crouched, 40)
	assert_bool(body.crouching).is_true()
	assert_float(body.peek_motion.amount).is_equal(1.0)
	assert_float(_eye(body).x - upright.x).is_between(0.25, 0.33)
	var walking := _leaning(1)
	walking.move = Vector2(0.0, 1.0)
	await _step(body, walking, 60)
	assert_float(body.peek_motion.amount).is_equal(1.0)
	assert_float(body.ground_speed()).is_less_equal(body.peek_tuning.move_speed + 0.01)
	assert_float(body.ground_speed()).is_greater(body.peek_tuning.move_speed * 0.8)


func test_a_sprint_lying_down_a_jump_and_a_death_end_it() -> void:
	var body := await _body()
	var sprint := _leaning(1)
	sprint.move = Vector2(0.0, 1.0)
	sprint.sprint = true
	await _step(body, _leaning(1), 20)
	await _step(body, sprint, 30)
	assert_float(body.peek_motion.amount).is_equal(0.0)
	assert_bool(body.is_sprinting()).is_true()
	await _step(body, PlayerCommand.new(), 60)
	var prone := _leaning(1)
	await _step(body, prone, 20)
	assert_float(body.peek_motion.amount).is_equal(1.0)
	prone.prone = true
	await _step(body, prone, 40)
	assert_bool(body.prone).is_true()
	assert_float(body.peek_motion.amount).is_equal(0.0)
	await _step(body, PlayerCommand.new(), 120)
	await _step(body, _leaning(-1), 20)
	assert_float(body.peek_motion.amount).is_equal(-1.0)
	var jump := _leaning(-1)
	jump.jump = true
	jump.jump_pressed = true
	var airborne := [0.0]
	await _step(
		body,
		jump,
		20,
		func(_c: PlayerCommand) -> void:
			if not body.is_on_floor():
				airborne[0] = body.peek_motion.amount
	)
	assert_float(airborne[0]).is_greater(-0.5)
	await _step(body, PlayerCommand.new(), 60)
	await _step(body, _leaning(1), 20)
	body.die()
	await _step(body, _leaning(1), 2)
	assert_float(body.peek_motion.amount).is_equal(0.0)
	assert_bool((body.get_node("PeekShape") as CollisionShape3D).disabled).is_true()


func test_the_lean_is_step_state_a_snapshot_puts_back() -> void:
	var body := await _body()
	await _step(body, _leaning(1), 8)
	var kept := body.state_snapshot()
	var eye := _eye(body)
	await _step(body, _leaning(-1), 30)
	body.restore(kept)
	assert_float(body.peek_motion.amount).is_equal(kept.peek[0])
	assert_vector(_eye(body)).is_equal_approx(eye, Vector3.ONE * 0.001)


func test_a_lean_shows_and_shoots_a_target_the_upright_body_cannot(
	scene: String, _test_parameters := [[BODY], [PLAYER]]
) -> void:
	var body := await _body(scene)
	_arena.add_block(Vector2(EDGE_X - 1.625, -1.0), Vector3(3.25, 3.0, 0.3), 3.0)
	var target := _arena.add_block(Vector2(TARGET.x, TARGET.z), Vector3(0.6, 0.6, 0.6), 1.8)
	var health := Health.new()
	health.max_value = 100.0
	target.add_child(health)
	await get_tree().physics_frame
	var wall_first := _ray(_eye(body), TARGET, ShotHull.rids_of(body))
	assert_object(wall_first).is_not_same(target)
	await _fire(body, false)
	assert_float(health.value).override_failure_message("upright hit through the wall").is_equal(
		100.0
	)
	await _step(body, _leaning(1), 20)
	assert_object(_ray(_eye(body), TARGET, ShotHull.rids_of(body))).is_same(target)
	await _fire(body, true)
	assert_float(health.value).override_failure_message("the lean's shot missed").is_less(100.0)


# Aims at the target from the eye for half a second, then presses fire and waits for the round.
func _fire(body: Character, lean: bool) -> void:
	var aim := _leaning(1 if lean else 0)
	aim.aim = true
	var look := func(command: PlayerCommand) -> void:
		var angles := CommandCodec.direction_angles(TARGET - _eye(body))
		command.yaw = angles.x
		command.pitch = angles.y
	await _step(body, aim, 30, look)
	var fire := aim.clone()
	fire.fire = true
	fire.fire_pressed = true
	await _step(body, fire, 2, look)
	await _step(body, aim, 40, look)


func test_q_and_e_lean_while_held_or_toggled() -> void:
	var player := _arena.add_player(Vector3.ZERO)
	var view := Camera3D.new()
	view.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(view)
	view.make_current()
	await InputSim.ticks(get_tree(), 4)
	InputSim.key(KEY_E, true)
	await InputSim.ticks(get_tree(), 20)
	assert_bool(player.last_command.lean_right).is_true()
	assert_float(player.peek_motion.amount).is_equal(1.0)
	InputSim.key(KEY_E, false)
	InputSim.key(KEY_Q, true)
	await InputSim.ticks(get_tree(), 30)
	assert_bool(player.last_command.lean_left).is_true()
	assert_float(player.peek_motion.amount).is_equal(-1.0)
	InputSim.key(KEY_Q, false)
	await InputSim.ticks(get_tree(), 20)
	assert_float(player.peek_motion.amount).is_equal(0.0)
	# Toggled: a press leans until the next press.
	_toggle_was = Settings.get_value(PeekInput.SETTING)
	Settings.set_value(PeekInput.SETTING, true)
	await _tap(KEY_Q)
	await InputSim.ticks(get_tree(), 20)
	assert_float(player.peek_motion.amount).is_equal(-1.0)
	await _tap(KEY_E)
	await InputSim.ticks(get_tree(), 30)
	assert_float(player.peek_motion.amount).is_equal(1.0)
	await _tap(KEY_E)
	await InputSim.ticks(get_tree(), 20)
	assert_float(player.peek_motion.amount).is_equal(0.0)
	# A sprint stands a toggled lean up.
	await _tap(KEY_E)
	await InputSim.ticks(get_tree(), 10)
	InputSim.key(KEY_W, true)
	InputSim.key(KEY_SHIFT, true)
	await InputSim.ticks(get_tree(), 30)
	assert_bool(player.last_command.lean_right).is_false()
	assert_float(player.peek_motion.amount).is_equal(0.0)


func _tap(key: Key) -> void:
	InputSim.key(key, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(key, false)


func test_the_pad_leans_on_the_d_pad_while_aiming_and_switches_weapons_otherwise() -> void:
	var player := _arena.add_player(Vector3.ZERO)
	await InputSim.ticks(get_tree(), 4)
	var presses := [0]
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await InputSim.ticks(get_tree(), 4)
	InputSim.pad_button(JOY_BUTTON_DPAD_LEFT, true)
	for _tick in 20:
		await get_tree().physics_frame
		presses[0] += int(player.last_command.previous_weapon_pressed)
	assert_bool(player.last_command.lean_left).is_true()
	assert_int(presses[0]).is_equal(0)
	assert_float(player.peek_motion.amount).is_less(-0.9)
	InputSim.pad_button(JOY_BUTTON_DPAD_LEFT, false)
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await InputSim.ticks(get_tree(), 20)
	InputSim.pad_button(JOY_BUTTON_DPAD_LEFT, true)
	for _tick in 6:
		await get_tree().physics_frame
		presses[0] += int(player.last_command.previous_weapon_pressed)
	assert_bool(player.last_command.lean_left).is_false()
	assert_int(presses[0]).is_equal(1)


func test_a_touch_control_leans() -> void:
	var player := _arena.add_player(Vector3.ZERO)
	await InputSim.ticks(get_tree(), 4)
	Input.action_press(&"lean_right")
	await InputSim.ticks(get_tree(), 20)
	Input.action_release(&"lean_right")
	assert_float(player.peek_motion.amount).is_equal(1.0)


func test_the_lean_travels_as_two_command_bits_and_a_byte_of_the_entry() -> void:
	for side in [-1, 1]:
		var command := _leaning(side)
		var packet := CommandCodec.encode(command)
		assert_int(packet.size()).is_equal(NetWire.COMMAND_SIZE)
		var read := CommandCodec.decode(packet)
		assert_bool(read.lean_left).is_equal(side < 0)
		assert_bool(read.lean_right).is_equal(side > 0)
		assert_int(CharacterPeek.asked_side(read)).is_equal(side)
	var entry := PlayerEntry.new()
	entry.slot = 3
	entry.aim = true
	entry.aim_yaw = 0.4
	entry.peek = -0.5
	assert_int(SnapshotCodec.player_size(entry)).is_equal(SnapshotCodec.MAX_PLAYER_SIZE)
	var read_back := SnapshotCodec.snap_player(entry)
	assert_float(read_back.peek).is_equal_approx(-0.5, 1.0 / 127.0)
	assert_float(read_back.aim_yaw).is_equal_approx(0.4, 0.03)
	entry.aim = false
	assert_int(SnapshotCodec.player_size(entry)).is_equal(SnapshotCodec.PLAYER_SIZE + 1)
	assert_float(SnapshotCodec.snap_player(entry).peek).is_equal_approx(-0.5, 1.0 / 127.0)
	entry.peek = 0.0
	assert_int(SnapshotCodec.player_size(entry)).is_equal(SnapshotCodec.PLAYER_SIZE)
	assert_float(SnapshotCodec.snap_player(entry).peek).is_equal(0.0)

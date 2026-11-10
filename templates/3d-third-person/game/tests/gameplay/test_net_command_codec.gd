# The COMMAND on the wire: round trips, the snap steps, what a predicting client moves with, and
# every hostile packet a client could send (each dropped with a reason, none throws).
extends GdUnitTestSuite


func _full_command() -> PlayerCommand:
	var command := PlayerCommand.new()
	command.seq = 4_000_000_123
	command.move = Vector2(0.31, -0.77)
	command.yaw = 2.4
	command.pitch = -0.41
	command.sprint = true
	command.crouch = true
	command.aim = true
	command.fire = true
	command.jump_pressed = true
	command.fire_pressed = true
	command.ragdoll_pressed = true
	return command


func _with_shot(command: PlayerCommand) -> PlayerCommand:
	command.has_shot = true
	command.origin = Vector3(12.345, 1.6, -301.004)
	command.shot_yaw = -2.9
	command.shot_pitch = 0.2
	command.view_tick = 70_001
	return command


func _assert_same(actual: PlayerCommand, expected: PlayerCommand) -> void:
	assert_int(actual.seq).is_equal(expected.seq)
	assert_vector(actual.move).is_equal(expected.move)
	assert_float(actual.yaw).is_equal(expected.yaw)
	assert_float(actual.pitch).is_equal(expected.pitch)
	for field in [
		"sprint",
		"walk",
		"crouch",
		"aim",
		"fire",
		"jump",
		"jump_pressed",
		"fire_pressed",
		"interact_pressed",
		"ragdoll_pressed",
		"reload_pressed",
		"next_weapon_pressed",
		"previous_weapon_pressed",
		"unarmed_pressed",
		"has_shot",
	]:
		assert_bool(actual.get(field)).override_failure_message(field).is_equal(expected.get(field))
	assert_vector(actual.origin).is_equal(expected.origin)
	assert_float(actual.shot_yaw).is_equal(expected.shot_yaw)
	assert_float(actual.shot_pitch).is_equal(expected.shot_pitch)
	assert_int(actual.view_tick).is_equal(expected.view_tick)


func test_a_command_is_15_bytes_and_27_with_a_shot_block() -> void:
	assert_int(CommandCodec.encode(_full_command()).size()).is_equal(15)
	assert_int(CommandCodec.encode(_with_shot(_full_command())).size()).is_equal(27)
	assert_int(NetWire.COMMAND_SIZE).is_less_equal(15)
	assert_int(NetWire.COMMAND_SHOT_SIZE).is_less_equal(27)


func test_every_field_and_flag_comes_back() -> void:
	var command := _with_shot(_full_command())
	command.walk = true
	command.jump = true
	command.interact_pressed = true
	var decoded := CommandCodec.decode(CommandCodec.encode(command))
	assert_object(decoded).is_not_null()
	assert_int(decoded.seq).is_equal(4_000_000_123)
	assert_vector(decoded.move).is_equal_approx(command.move, Vector2(0.005, 0.005))
	assert_float(decoded.yaw).is_equal_approx(2.4, 0.0001)
	assert_float(decoded.pitch).is_equal_approx(-0.41, 0.0001)
	assert_vector(decoded.origin).is_equal_approx(command.origin, Vector3(0.005, 0.005, 0.005))
	assert_float(decoded.shot_yaw).is_equal_approx(-2.9, 0.0001)
	assert_float(decoded.shot_pitch).is_equal_approx(0.2, 0.0001)
	assert_int(decoded.view_tick).is_equal(70_001 & 0xFFFF)
	_assert_same(decoded, CommandCodec.quantized(command))
	for field in ["sprint", "walk", "crouch", "aim", "fire", "jump", "jump_pressed"]:
		assert_bool(decoded.get(field)).override_failure_message(field).is_true()
	for field in ["fire_pressed", "interact_pressed", "ragdoll_pressed", "has_shot"]:
		assert_bool(decoded.get(field)).override_failure_message(field).is_true()


func test_each_flag_travels_alone() -> void:
	for field in [
		"sprint",
		"walk",
		"crouch",
		"aim",
		"fire",
		"jump",
		"jump_pressed",
		"fire_pressed",
		"interact_pressed",
		"ragdoll_pressed",
		"reload_pressed",
		"next_weapon_pressed",
		"previous_weapon_pressed",
		"unarmed_pressed",
	]:
		var command := PlayerCommand.new()
		command.set(field, true)
		var decoded := CommandCodec.decode(CommandCodec.encode(command))
		_assert_same(decoded, command)


func test_the_weapon_presses_take_bits_11_to_14_and_bit_15_is_still_refused() -> void:
	var bits := {
		"reload_pressed": CommandCodec.F_RELOAD_PRESSED,
		"next_weapon_pressed": CommandCodec.F_NEXT_WEAPON_PRESSED,
		"previous_weapon_pressed": CommandCodec.F_PREVIOUS_WEAPON_PRESSED,
		"unarmed_pressed": CommandCodec.F_UNARMED_PRESSED,
	}
	var shift := 11
	for field: String in bits:
		assert_int(bits[field]).override_failure_message(field).is_equal(1 << shift)
		var command := PlayerCommand.new()
		command.set(field, true)
		assert_int(CommandCodec.encode(command).decode_u16(11)).is_equal(1 << shift)
		shift += 1
	assert_int(CommandCodec.F_UNUSED).is_equal(1 << 15)
	# A press survives two commands arriving together, and a repeat drops it.
	var earlier := PlayerCommand.new()
	earlier.reload_pressed = true
	earlier.unarmed_pressed = true
	var later := PlayerCommand.new()
	later.merge_edges_from(earlier)
	assert_bool(later.reload_pressed and later.unarmed_pressed).is_true()
	later.clear_edges()
	assert_bool(later.reload_pressed or later.unarmed_pressed).is_false()
	# The layout changed: the version went up past the first one.
	assert_int(NetWire.VERSION).is_greater_equal(2)
	assert_bool(NetWire.accepts(1)).is_false()


func test_a_quantized_command_equals_what_the_codec_decodes() -> void:
	var command := _with_shot(_full_command())
	var quantized := PlayerCommand.quantized(command)
	_assert_same(quantized, CommandCodec.decode(CommandCodec.encode(command)))
	# And it is a fixed point: quantizing again changes nothing, byte for byte.
	_assert_same(PlayerCommand.quantized(quantized), quantized)
	assert_array(CommandCodec.encode(quantized)).is_equal(CommandCodec.encode(command))


func test_every_snap_is_idempotent() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 902
	for _index in 500:
		var move := Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
		var yaw := rng.randf_range(-20.0, 20.0)
		var pitch := rng.randf_range(-2.0, 2.0)
		var point := Vector3(
			rng.randf_range(-400.0, 400.0), rng.randf_range(-50.0, 50.0), rng.randf_range(-9.0, 9.0)
		)
		var move_once := CommandCodec.snap_move(move)
		assert_vector(CommandCodec.snap_move(move_once)).is_equal(move_once)
		assert_float(move_once.length()).is_less_equal(1.0 + 1e-6)
		var yaw_once := CommandCodec.snap_yaw(yaw)
		assert_float(CommandCodec.snap_yaw(yaw_once)).is_equal(yaw_once)
		assert_bool(yaw_once >= -PI and yaw_once < PI).is_true()
		var pitch_once := CommandCodec.snap_pitch(pitch)
		assert_float(CommandCodec.snap_pitch(pitch_once)).is_equal(pitch_once)
		var point_once := CommandCodec.snap_point(point)
		assert_vector(CommandCodec.snap_point(point_once)).is_equal(point_once)
		# A Vector3 holds float32: 327.67 reads 327.670013.
		assert_float(absf(point_once.x)).is_less_equal(NetLimits.POSITION_RANGE + 0.0001)


func test_a_snapped_move_never_pushes_harder_than_the_stick() -> void:
	for angle_step in 64:
		var stick := Vector2.from_angle(angle_step * TAU / 64.0)
		assert_float(CommandCodec.snap_move(stick).length()).is_less_equal(1.0 + 1e-6)
	# A hostile full byte on both axes is a full push, not 1.41.
	assert_float(CommandCodec.move_from_bytes(127, 127).length()).is_less_equal(1.0 + 1e-6)
	assert_float(CommandCodec.move_from_bytes(-128, -128).length()).is_less_equal(1.0 + 1e-6)


func test_a_command_with_a_number_that_is_not_finite_is_not_sent() -> void:
	var cases := {
		"move nan": func(c: PlayerCommand) -> void: c.move = Vector2(NAN, 0.0),
		"move inf": func(c: PlayerCommand) -> void: c.move = Vector2(0.0, INF),
		"yaw nan": func(c: PlayerCommand) -> void: c.yaw = NAN,
		"pitch inf": func(c: PlayerCommand) -> void: c.pitch = -INF,
		"origin nan": func(c: PlayerCommand) -> void: c.origin = Vector3(0.0, NAN, 0.0),
		"shot yaw inf": func(c: PlayerCommand) -> void: c.shot_yaw = INF,
		"shot pitch nan": func(c: PlayerCommand) -> void: c.shot_pitch = NAN,
	}
	for label: String in cases:
		var command := _with_shot(_full_command())
		(cases[label] as Callable).call(command)
		var drops := NetDrops.new()
		assert_array(CommandCodec.encode(command, drops)).override_failure_message(label).is_empty()
		assert_int(drops.of(NetDrops.NOT_FINITE)).override_failure_message(label).is_equal(1)
		assert_object(PlayerCommand.quantized(command)).override_failure_message(label).is_null()


func test_hostile_commands_are_dropped_with_a_reason() -> void:
	var good := CommandCodec.encode(_full_command())
	var shot := CommandCodec.encode(_with_shot(_full_command()))
	var unknown_flag := good.duplicate()
	unknown_flag.encode_u16(11, unknown_flag.decode_u16(11) | (1 << 15))
	var shot_flag_short := good.duplicate()
	shot_flag_short.encode_u16(11, shot_flag_short.decode_u16(11) | CommandCodec.F_SHOT)
	var shot_block_no_flag := shot.duplicate()
	shot_block_no_flag.encode_u16(11, shot.decode_u16(11) & ~CommandCodec.F_SHOT)
	var wrong_type := good.duplicate()
	wrong_type[0] = 99
	var long := shot.duplicate()
	long.append(0)
	var cases := {
		NetDrops.EMPTY: PackedByteArray(),
		NetDrops.TOO_SHORT: good.slice(0, 14),
		NetDrops.TOO_LONG: long,
		NetDrops.UNKNOWN_TYPE: wrong_type,
		NetDrops.BAD_VALUE: unknown_flag,
		NetDrops.WRONG_SIZE: shot_flag_short,
	}
	for reason: StringName in cases:
		var drops := NetDrops.new()
		(
			assert_object(CommandCodec.decode(cases[reason], drops))
			. override_failure_message(reason)
			. is_null()
		)
		assert_int(drops.of(reason)).override_failure_message(reason).is_equal(1)
		assert_int(drops.total()).is_equal(1)
	var drops := NetDrops.new()
	assert_object(CommandCodec.decode(shot_block_no_flag, drops)).is_null()
	assert_str(drops.last).is_equal(NetDrops.WRONG_SIZE)
	# Every length from 0 to 40 bytes is either a command or a counted drop, never an error.
	for size in 41:
		var counted := NetDrops.new()
		var packet := shot.slice(0, mini(size, shot.size()))
		packet.resize(size)
		var decoded := CommandCodec.decode(packet, counted)
		assert_bool(decoded != null or counted.total() == 1).is_true()


func test_every_decoded_number_is_finite_whatever_the_bytes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1902
	for _index in 300:
		var packet := PackedByteArray()
		packet.resize(27)
		for at in 27:
			packet[at] = rng.randi_range(0, 255)
		packet[0] = NetWire.Type.COMMAND
		packet.encode_u16(11, packet.decode_u16(11) & 0x7FF | CommandCodec.F_SHOT)
		var decoded := CommandCodec.decode(packet, NetDrops.new())
		assert_object(decoded).is_not_null()
		assert_bool(decoded.all_finite()).is_true()
		assert_float(decoded.move.length()).is_less_equal(1.0 + 1e-6)

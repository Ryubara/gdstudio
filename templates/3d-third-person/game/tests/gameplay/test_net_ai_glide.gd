# How a client draws an AI character between the server's rows (gdstudio #970, `AiGlide`): even
# steps at 3 m/s from rows every second tick (Deadnight's check: 0.045 to 0.055 m a tick), the
# first row and a jump set down at once, a far character glides as evenly between rarer rows, and
# a guess ahead stops after 100 ms and at a wall.
extends GdUnitTestSuite

const SPEED := 3.0
const SEND_EVERY := NetLimits.TICK_RATE / NetLimits.SNAPSHOT_RATE


func _row(at: Vector3, speed := SPEED) -> AiRow:
	var row := AiRow.new()
	row.id = 1
	row.position = at
	row.speed = speed
	row.state = Character.State.RUN
	return row


# Rows of a character walking along +X at `SPEED`, one every `every` ticks, from tick `from`.
func _walk(glide: AiGlide, from: int, count: int, every := SEND_EVERY) -> void:
	for index in count:
		var tick := from + index * every
		glide.push(tick, _row(Vector3(SPEED * tick / NetLimits.TICK_RATE, 0.0, 0.0)))


func _steps(glide: AiGlide, from: int, ticks: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for tick in range(from, from + ticks):
		var was := glide.position
		glide.step(tick)
		out.append(glide.position.distance_to(was))
	return out


func test_glide_steps_are_even_at_3_m_s_and_30_hz_sends() -> void:
	var glide := AiGlide.new()
	_walk(glide, 0, 60)
	var steps := _steps(glide, 0, 110)
	# The first row sets it down and it stands until the second; every tick after that moves
	# 0.05 m.
	var worst_low := INF
	var worst_high := 0.0
	for index in range(SEND_EVERY, steps.size()):
		worst_low = minf(worst_low, steps[index])
		worst_high = maxf(worst_high, steps[index])
	print("ai glide: steps %.4f to %.4f m at 3 m/s" % [worst_low, worst_high])
	assert_float(worst_low).is_greater_equal(0.045)
	assert_float(worst_high).is_less_equal(0.055)
	assert_int(glide.jumps).is_equal(0)


func test_a_far_character_sent_7_5_times_a_second_glides_as_evenly() -> void:
	var glide := AiGlide.new()
	_walk(glide, 0, 20, 8)
	var steps := _steps(glide, 0, 150)
	for index in range(8, steps.size()):
		assert_float(steps[index]).is_between(0.045, 0.055)


func test_the_first_row_and_a_jump_set_it_down_at_once() -> void:
	var glide := AiGlide.new()
	glide.push(10, _row(Vector3(5.0, 0.0, 5.0)))
	glide.step(9)
	assert_bool(glide.placed).is_false()
	glide.step(10)
	assert_bool(glide.placed).is_true()
	assert_vector(glide.position).is_equal(Vector3(5.0, 0.0, 5.0))
	# 6 m on: a teleport, not a walk.
	glide.push(12, _row(Vector3(11.0, 0.0, 5.0)))
	glide.step(12)
	assert_vector(glide.position).is_equal(Vector3(11.0, 0.0, 5.0))
	assert_int(glide.jumps).is_equal(1)
	# 0.1 m on: walked over the two ticks.
	glide.push(14, _row(Vector3(11.1, 0.0, 5.0)))
	glide.step(14)
	assert_float(glide.position.x).is_equal_approx(11.05, 0.0001)
	glide.step(15)
	assert_float(glide.position.x).is_equal_approx(11.1, 0.0001)


func test_rows_wait_in_the_buffer_until_their_tick_is_drawn() -> void:
	var glide := AiGlide.new()
	_walk(glide, 100, 3)
	assert_int(glide.waiting()).is_equal(3)
	glide.step(99)
	assert_bool(glide.placed).is_false()
	glide.step(100)
	assert_int(glide.waiting()).is_equal(2)
	# A row older than the newest held is ignored.
	glide.push(101, _row(Vector3(9.0, 0.0, 0.0)))
	assert_int(glide.waiting()).is_equal(2)


func test_the_guess_ahead_is_capped_at_100_ms() -> void:
	var glide := AiGlide.new()
	_walk(glide, 0, 10)
	_steps(glide, 0, 20)
	var last := glide.position
	# No row for half a second: it goes on for 6 ticks at 3 m/s, then holds.
	_steps(glide, 20, 30)
	assert_int(glide.guessed).is_equal(6)
	assert_float(glide.position.x - last.x).is_equal_approx(SPEED * 0.1, 0.001)


func test_the_guess_ahead_never_goes_through_a_wall() -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 3.0, 3.0)
	shape.shape = box
	wall.add_child(shape)
	wall.collision_layer = PhysicsLayers.WORLD
	var holder := Node3D.new()
	holder.add_child(wall)
	add_child(auto_free(holder))
	# The rows stop at x = 0.9; the wall's face is 0.12 m past the reach of the first guess.
	var face := 0.9 + AiGlide.GUESS_REACH + 0.12
	wall.global_position = Vector3(face + box.size.x / 2.0, 1.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := holder.get_world_3d().direct_space_state
	var glide := AiGlide.new()
	_walk(glide, 0, 10)
	for tick in 20:
		glide.step(tick, space, PhysicsLayers.WORLD)
	for tick in range(20, 40):
		glide.step(tick, space, PhysicsLayers.WORLD)
	# Two guesses of 0.05 m fit before the wall; the third would reach it.
	assert_int(glide.guessed).is_equal(2)
	assert_float(glide.position.x + AiGlide.GUESS_REACH).is_less_equal(face)

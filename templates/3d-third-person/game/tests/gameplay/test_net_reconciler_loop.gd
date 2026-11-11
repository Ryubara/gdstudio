# The prediction loop closed in plain numbers: a client predicts its body with each command at
# once, a server applies the same commands half a round trip later and answers every second tick
# with its point in centimetres and the last command applied, half a round trip later again. The
# server's body is pushed (a thing the client never sees) twice. At 50, 100, 200 and 400 ms round
# trip no run ends more than 0.05 m off and none diverges (Deadnight #483 grew without bound at
# 300 ms when the remembered points were not shifted by the corrections).
extends GdUnitTestSuite

const TICKS := 900
const STOP_AT := 600
const PUSHES := {200: Vector3(1.2, 0.0, -0.4), 420: Vector3(-3.5, 0.0, 0.0)}
const STEP := 1.0 / NetLimits.TICK_RATE


# The client's velocity at tick t: walks, turns, sprints, stops at `STOP_AT`.
static func velocity_at(t: int) -> Vector3:
	if t >= STOP_AT:
		return Vector3.ZERO
	var heading := t * 0.01
	var speed := 3.0 if (t / 90) % 2 == 0 else 6.0
	return Vector3(sin(heading), 0.0, cos(heading)) * speed


# Runs the loop at `round_trip_ms`; answers the worst gap, the gap at the end and the reconciler.
static func run_loop(round_trip_ms: int) -> Dictionary:
	var one_way := roundi(round_trip_ms / 2.0 / 1000.0 * NetLimits.TICK_RATE)
	var reconciler := Reconciler.new()
	var client := Vector3.ZERO
	var server := Vector3.ZERO
	var to_server: Dictionary[int, Array] = {}
	var to_client: Dictionary[int, Array] = {}
	var ack := 0
	var worst := 0.0
	for t in TICKS:
		for answer: Array in to_client.get(t, []):
			reconciler.answer(answer[0], answer[1])
		client += reconciler.take()
		var seq := t + 1
		var velocity := velocity_at(t)
		client += velocity * STEP
		reconciler.record(seq, client)
		to_server.get_or_add(t + one_way, []).append([seq, velocity])
		for command: Array in to_server.get(t, []):
			server += command[1] * STEP
			ack = command[0]
		if PUSHES.has(t):
			server += PUSHES[t]
		if t % 2 == 0 and ack > 0:
			var sent := CommandCodec.snap_point(server)
			to_client.get_or_add(t + one_way, []).append([ack, sent])
		worst = maxf(worst, client.distance_to(server))
	return {"worst": worst, "end": client.distance_to(server), "reconciler": reconciler}


func test_the_loop_settles_at_every_round_trip_with_a_push() -> void:
	for round_trip in [50, 100, 200, 400]:
		var result := run_loop(round_trip)
		var reconciler: Reconciler = result["reconciler"]
		prints(
			"reconciler loop",
			round_trip,
			"ms: end %.4f m, worst %.3f m" % [result["end"], result["worst"]],
			"corrections",
			reconciler.corrections,
			"snaps",
			reconciler.snaps,
			"lost",
			reconciler.lost
		)
		(
			assert_float(result["end"])
			. override_failure_message("%d ms ended %.4f m off" % [round_trip, result["end"]])
			. is_less(0.05)
		)
		# Bounded: the pushes are 1.3 and 3.5 m, a round trip of motion is at most 2.4 m more.
		assert_float(result["worst"]).is_less(8.0)
		assert_int(reconciler.lost).is_equal(0)


func test_a_correction_is_counted_once() -> void:
	# Many commands in flight: the body moves by the error once, not once per answer in flight.
	var reconciler := Reconciler.new()
	for seq in range(1, 25):
		reconciler.record(seq, Vector3.ZERO)
	reconciler.answer(1, Vector3(1.0, 0.0, 0.0))
	var moved := Vector3.ZERO
	for _frame in 30:
		moved += reconciler.take()
	assert_float(moved.x).is_equal_approx(1.0, 0.002)
	# The next answer, from a server that has not moved, finds the shifted points and corrects
	# nothing more.
	reconciler.answer(5, Vector3(1.0, 0.0, 0.0))
	assert_vector(reconciler.pending()).is_equal(Vector3.ZERO)
	assert_int(reconciler.corrections).is_equal(1)


func test_a_rounding_error_is_not_corrected() -> void:
	var reconciler := Reconciler.new()
	reconciler.record(1, Vector3(0.004, 0.0, -0.004))
	reconciler.answer(1, CommandCodec.snap_point(Vector3(0.004, 0.0, -0.004)))
	assert_vector(reconciler.take()).is_equal(Vector3.ZERO)
	assert_int(reconciler.corrections).is_equal(0)


func test_a_far_error_snaps_and_a_very_far_one_is_lost() -> void:
	var reconciler := Reconciler.new()
	reconciler.record(1, Vector3.ZERO)
	reconciler.record(2, Vector3(0.1, 0.0, 0.0))
	reconciler.answer(1, Vector3(3.0, 0.0, 0.0))
	assert_vector(reconciler.take()).is_equal(Vector3(3.0, 0.0, 0.0))
	assert_int(reconciler.snaps).is_equal(1)
	assert_int(reconciler.lost).is_equal(0)
	# Command 2's point moved with the snap: an answer of the same place corrects nothing.
	reconciler.answer(2, Vector3(3.1, 0.0, 0.0))
	assert_vector(reconciler.take()).is_equal(Vector3.ZERO)
	reconciler.record(3, Vector3.ZERO)
	reconciler.answer(3, Vector3(0.0, 0.0, 7.0))
	assert_int(reconciler.lost).is_equal(1)

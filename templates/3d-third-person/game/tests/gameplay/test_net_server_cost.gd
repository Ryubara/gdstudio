# What the game server's step costs with eight players in the template's map, each sending a
# command a tick over a real socket (`tools/bench/server_bench.tscn`): the step's 95th percentile
# stays under `NetServer.STEP_BUDGET_MS` (6 ms of the 16.7 ms tick), and what each client is sent
# and sends stays inside the budgets of the networking research (down under 5 KB/s at eight
# players, up under 2 KB/s). Prints the numbers.
extends GdUnitTestSuite

const BENCH := "res://tools/bench/server_bench.tscn"


func test_eight_players_step_under_the_budget() -> void:
	var bench := (load(BENCH) as PackedScene).instantiate() as ServerBench
	bench.bodies = 8
	bench.ticks = 600
	bench.quit_when_done = false
	add_child(bench)
	var done := func() -> bool: return not bench.result.is_empty()
	for _frame in 1200:
		if done.call():
			break
		await get_tree().physics_frame
	assert_bool(done.call()).is_true()
	var result := bench.result
	prints("server step, 8 players:", JSON.stringify(result))
	assert_float(result["step_ms_p95"]).is_less(NetServer.STEP_BUDGET_MS)
	assert_int(result["down_bytes_per_s_per_client"]).is_less(5000)
	assert_int(result["up_bytes_per_s_per_client"]).is_less(2000)
	# Every client was sent a TICK of eight players thirty times a second: 107 bytes.
	assert_int(result["down_bytes_per_s_per_client"]).is_greater(107 * 25)
	bench.queue_free()
	await get_tree().physics_frame

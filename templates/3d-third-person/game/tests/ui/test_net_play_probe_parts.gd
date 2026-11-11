# The parts the bad-network gate shares between the native bot (`tools/net/predict_bot.gd`) and the
# browser's `NetPlayProbe`: the walk of `CirclingController` and the numbers of `NetPlayReport`.
extends GdUnitTestSuite

const BODY := "res://gameplay/character/character.tscn"


func _walker() -> CirclingController:
	var body := auto_free((load(BODY) as PackedScene).instantiate()) as Character
	add_child(body)
	var walker := auto_free(CirclingController.new()) as CirclingController
	walker.body = body
	walker.seconds = 1.0
	walker.jump_every = 0.5
	walker.restart(Vector3.ZERO)
	return walker


func test_the_walk_moves_jumps_on_its_beat_and_stands_after_its_seconds() -> void:
	var walker := _walker()
	var moved := 0
	var jumps := 0
	for _tick in NetLimits.TICK_RATE:
		var command := walker.sample()
		moved += 1 if command.move != Vector2.ZERO else 0
		jumps += 1 if command.jump_pressed else 0
	assert_int(moved).is_equal(NetLimits.TICK_RATE)
	assert_int(jumps).is_equal(2)
	assert_bool(walker.is_standing()).is_true()
	assert_vector(walker.sample().move).is_equal(Vector2.ZERO)


func test_stop_stands_from_the_next_tick() -> void:
	var walker := _walker()
	walker.seconds = 30.0
	for _tick in 10:
		walker.sample()
	walker.stop()
	assert_bool(walker.is_standing()).is_true()
	assert_vector(walker.sample().move).is_equal(Vector2.ZERO)


func test_the_report_counts_starving_per_puppet_step_and_has_no_gap_before_a_tick() -> void:
	var client := auto_free(NetClient.new()) as NetClient
	client.reconciler.corrections = 3
	var report := NetPlayReport.of(client, null, 120)
	assert_float(report["gap_m"]).is_equal(-1.0)
	assert_int(report["corrections"]).is_equal(3)
	assert_int(report["puppets"]).is_equal(0)
	assert_float(report["starved_share"]).is_equal(0.0)
	assert_int(NetPlayReport.percentile(PackedInt32Array([5, 1, 3, 2, 4]), 0.5)).is_equal(3)
	assert_int(NetPlayReport.percentile(PackedInt32Array(), 0.5)).is_equal(-1)

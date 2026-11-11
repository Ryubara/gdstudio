# `JoinWait`: the wait of a join for the level's warm-up (`EffectEmitter.warmed`) and then for its
# frames to settle (`FrameSettle`), shared by the online game's client and the bad-network probe.
extends GdUnitTestSuite


func test_without_an_emitter_it_waits_only_for_the_frames_to_settle() -> void:
	var node := auto_free(Node.new()) as Node
	add_child(node)
	var wait := JoinWait.new()
	wait.settle.frames = 5
	var stages: Array[JoinWait.Stage] = []
	wait.stage_changed.connect(func(stage: JoinWait.Stage) -> void: stages.append(stage))
	var ended := [false]
	wait.finished.connect(func() -> void: ended[0] = true)
	wait.run(node)
	assert_bool(wait.is_waiting()).is_true()
	assert_str(wait.stage_name()).is_equal("settling")
	for _i in 4:
		await get_tree().process_frame
	assert_bool(ended[0]).is_false()
	for _i in 4:
		await get_tree().process_frame
	assert_bool(ended[0]).is_true()
	assert_array(stages).contains_exactly([JoinWait.Stage.SETTLING, JoinWait.Stage.DONE])
	assert_int(wait.settle_ms).is_greater_equal(0)
	assert_int(wait.waited_ms).is_greater_equal(wait.settle_ms)
	assert_bool(wait.is_waiting()).is_false()


func test_it_waits_for_the_warm_up_before_it_counts_frames() -> void:
	var emitter := EffectEmitter.new()
	add_child(auto_free(emitter))
	assert_bool(emitter.is_warming()).is_true()
	var wait := JoinWait.new()
	wait.settle.frames = 2
	var settled_during_warm_up := [false]
	wait.stage_changed.connect(
		func(stage: JoinWait.Stage) -> void:
			if stage == JoinWait.Stage.SETTLING and emitter.is_warming():
				settled_during_warm_up[0] = true
	)
	wait.run(emitter)
	assert_str(wait.stage_name()).is_equal("warming")
	var frames := 0
	while wait.is_waiting() and frames < 120:
		await get_tree().process_frame
		frames += 1
	assert_str(wait.stage_name()).is_equal("done")
	assert_bool(settled_during_warm_up[0]).is_false()
	# Two frames for the emitter's camera, then the two settled frames.
	assert_int(frames).is_greater_equal(4)


func test_a_node_that_leaves_the_tree_stops_the_wait_without_finishing() -> void:
	var node := Node.new()
	add_child(node)
	var wait := JoinWait.new()
	var ended := [false]
	wait.finished.connect(func() -> void: ended[0] = true)
	wait.run(node)
	await get_tree().process_frame
	node.free()
	for _i in 30:
		await get_tree().process_frame
	assert_bool(ended[0]).is_false()

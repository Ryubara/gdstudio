# The step trace: commands of the step's number alone, so every platform steps the same body the
# same way.
extends GdUnitTestSuite


func test_the_commands_depend_on_the_number_alone() -> void:
	var a := StepTraceProbe.command_at(97, PlayerCommand.new())
	var b := StepTraceProbe.command_at(97, PlayerCommand.new())
	assert_float(a.yaw).is_equal(b.yaw)
	assert_bool(a.jump_pressed).is_true()
	assert_bool(StepTraceProbe.command_at(98, PlayerCommand.new()).jump_pressed).is_false()
	assert_bool(StepTraceProbe.command_at(StepTraceProbe.LEG, PlayerCommand.new()).sprint).is_true()
	assert_bool(StepTraceProbe.command_at(0, PlayerCommand.new()).sprint).is_false()
	assert_float(StepTraceProbe.command_at(10, PlayerCommand.new()).move.y).is_equal(1.0)


func test_it_is_asked_for_only_by_its_flag() -> void:
	assert_bool(StepTraceProbe.asked()).is_false()
	assert_object(StepTraceProbe.attach(self)).is_null()


func test_two_bodies_stepped_alike_end_at_the_same_float() -> void:
	var ends: Array[Vector3] = []
	for _run in 2:
		# One arena at a time: a second floor in the same place changes the contacts.
		var arena := PlayArena.new()
		add_child(arena)
		var body := (load(StepTraceProbe.BODY) as PackedScene).instantiate() as Character
		arena.add_child(body)
		body.set_physics_process(false)
		body.teleport(Vector3(0.0, 0.05, 0.0), 0.0)
		var command := PlayerCommand.new()
		for index in 240:
			# `Character.step` runs inside a physics frame.
			await get_tree().physics_frame
			body.step(StepTraceProbe.command_at(index, command), 1.0 / 60.0)
		ends.append(body.global_position)
		arena.free()
	assert_float(ends[0].distance_to(Vector3.ZERO)).is_greater(5.0)
	assert_vector(ends[0]).is_equal(ends[1])

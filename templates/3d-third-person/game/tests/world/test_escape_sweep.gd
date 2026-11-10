# The real body, started on everything it can stand on in the map and its sections and run
# at the walls with sprinting jumps in four directions, chained over three rounds, never ends on a
# boundary wall or outside the play areas (`EscapeSweep`; kit #885,
# docs/engines/godot/map-review.md, "Chains of props are stairs"). With the 4 m walls the map had
# before, the tower and the ragdoll ledge put the body on the wall tops.
extends GdUnitTestSuite


func test_no_run_from_any_top_leaves_the_map_or_stands_on_a_wall() -> void:
	var sweep: EscapeSweep = auto_free(EscapeSweep.new())
	add_child(sweep)
	sweep.setup(load("res://main.tscn").instantiate())
	await sweep.sweep(3)
	prints(
		"SWEEP runs",
		sweep.runs,
		"highest rest",
		snappedf(sweep.highest, 0.01),
		"faults",
		sweep.faults.size()
	)
	for place: String in sweep.high_places.values():
		prints("SWEEP high", place)
	assert_int(sweep.runs).is_greater(500)
	(
		assert_array(sweep.faults)
		. override_failure_message("\n".join(sweep.faults.slice(0, 20)))
		. is_empty()
	)

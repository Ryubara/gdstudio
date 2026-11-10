# How high a ledge the real player body gets onto from level ground. The jump is 1.25 m
# (`PlayerTuning.jump_height`), but the body also steps up at an edge and its capsule has a rounded
# foot, so it climbs a little higher; a map judges its walls against the measured number
# (`ReachBench.MEASURED_REACH`, read by `test_map_reach.gd`), never the tuning (kit
# docs/engines/godot/map-review.md, "Measure the reach").
extends GdUnitTestSuite

## How far the measure may move before this fails: the map tests read the number, so a move is a
## decision.
const TOLERANCE := 0.06


func test_the_body_climbs_the_measured_reach_and_no_more() -> void:
	var heights: Array[float] = [1.2, 1.25, 1.3, 1.35, 1.4, 1.45, 1.5]
	var bench: ReachBench = auto_free(ReachBench.new())
	add_child(bench)
	var climbed := await bench.measure(heights)
	(
		assert_float(ReachBench.highest(climbed))
		. override_failure_message("climbed: %s" % climbed)
		. is_between(ReachBench.MEASURED_REACH - TOLERANCE, ReachBench.MEASURED_REACH + TOLERANCE)
	)
	# The reason for the number: a block a little over the jump is climbed.
	assert_bool(climbed[1.3]).is_true()


func test_the_body_crosses_the_measured_gaps_onto_higher_tops_and_no_wider() -> void:
	# The map tests judge a jump from one top to another by these numbers (`MapReach.hop`).
	var rises: Array[float] = []
	for rise: float in ReachBench.MEASURED_CARRY:
		rises.append(rise)
	var gaps: Array[float] = []
	for quarter in range(10, 27):
		gaps.append(quarter * ReachBench.CARRY_STEP)
	var bench: ReachBench = auto_free(ReachBench.new())
	add_child(bench)
	var widest := await bench.measure_carry(rises, gaps)
	for rise in rises:
		(
			assert_float(widest[rise])
			. override_failure_message("rise %.2f: crossed %s" % [rise, widest])
			. is_equal_approx(ReachBench.MEASURED_CARRY[rise], ReachBench.CARRY_STEP + 0.01)
		)

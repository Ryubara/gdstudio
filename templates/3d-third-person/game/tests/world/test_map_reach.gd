# No wall that keeps the player in (the map's boundary and the sections') is within the player's
# reach of anything the player can stand on. The walls are judged against the measured reach
# (`ReachBench.MEASURED_REACH`, 1.35 m), not the jump, and against every top the body can get
# onto from the floor through others (a chain of blocks is a stair) and every walkable ramp and
# staircase (`MapReach`). The map with 4 m walls failed this: the tower (3 m, by its stairs) is
# 2 m from the west wall and the ragdoll ledge (3 m, by its ramp) 0.5 m from the south wall (kit
# #885; docs/engines/godot/map-review.md, "Compute the reach"). `test_escape_sweep.gd` runs the
# real body at the walls from those tops.
extends GdUnitTestSuite

## A wall top must clear the reach from any top within a jump by this much.
const MARGIN := 0.25
const MAIN := "res://main.tscn"

var _main: Node


func before() -> void:
	_main = load(MAIN).instantiate()
	(_main.get_node("Player") as Player).start_at_spawn = false
	add_child(_main)


func after() -> void:
	_main.free()


func test_no_boundary_wall_is_in_reach_of_a_top_the_player_gets_onto() -> void:
	var tops := MapReach.reachable_tops(_main)
	assert_int(tops.size()).is_greater(10)
	var faults: Array[String] = []
	for wall in MapReach.barriers(_main):
		var wall_box := MapReach.box_of(wall)
		for top: Dictionary in tops:
			var clearance: float = wall_box.end.y - top["height"]
			var apart := MapReach.gap(wall_box, top["box"])
			if apart <= MapReach.hop(clearance) and clearance < ReachBench.MEASURED_REACH + MARGIN:
				faults.append(
					(
						"%s (top %.2f m) is %.2f m from %s, %.2f m under its top"
						% [top["name"], top["height"], apart, wall.name, clearance]
					)
				)
	assert_array(faults).override_failure_message("\n".join(faults)).is_empty()


func test_the_props_stacked_against_a_wall_stay_out_of_reach_of_its_top() -> void:
	var highest := 0.0
	for prop: PhysicsProp in _main.find_children("*", "PhysicsProp", true, false):
		highest = maxf(highest, MapReach.visual_box(prop).end.y)
	assert_float(highest).is_greater(0.5)
	for wall in MapReach.barriers(_main):
		var over := MapReach.box_of(wall).end.y - highest
		(
			assert_float(over)
			. override_failure_message("%s: %.2f m over a %.2f m prop" % [wall.name, over, highest])
			. is_greater_equal(ReachBench.MEASURED_REACH + MARGIN)
		)


func test_the_doorways_to_the_sections_are_the_only_breaks_in_the_boundary() -> void:
	var names: Array[String] = []
	for wall in MapReach.barriers(_main):
		if wall.owner == _main.get_node("Level"):
			names.append(wall.name)
	names.sort()
	(
		assert_array(names)
		. contains_exactly(
			[
				"WallEastLintel",
				"WallEastNorth",
				"WallEastSouth",
				"WallNorth",
				"WallSouth",
				"WallWestLintel",
				"WallWestNorth",
				"WallWestSouth",
			]
		)
	)

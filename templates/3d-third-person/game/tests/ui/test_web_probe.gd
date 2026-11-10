# The web boot check waits for `ready` from the menu's probe and the touch smoke from the game's.
# No scene holds the game's probe: it is made at run time on a page opened with `?probe`, so a
# player's page pays for nothing. (This file replaces 3D Blank's test of the same name, which looks
# for the probe in its main scene.)
extends GdUnitTestSuite


func test_no_probe_is_made_off_the_web() -> void:
	var holder: Node = auto_free(Node.new())
	add_child(holder)
	assert_bool(WebProbe.asked()).is_false()
	assert_object(WebProbe.attach(holder, null, null, null)).is_null()
	assert_int(holder.get_child_count()).is_equal(0)


func test_a_probe_made_by_hand_does_nothing_off_the_web() -> void:
	var probe: WebProbe = auto_free(WebProbe.new())
	add_child(probe)
	await await_idle_frame()
	assert_bool(probe.is_processing()).is_false()

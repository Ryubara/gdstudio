# The online rig draws a new screen's reflection probes to the end before a capture films it
# (`ProbeSettle`): every probe of the world that updates once counts, seen or not (the level's
# effect warm-up visits them all), a hidden one or one that updates always does not, and a run that
# draws nothing settles at once. The capture's frames are the proof that the bodies stay lit.
extends GdUnitTestSuite

var _view: SubViewport


func before_test() -> void:
	_view = auto_free(SubViewport.new())
	_view.own_world_3d = true
	add_child(_view)


func _probe(mode := ReflectionProbe.UPDATE_ONCE) -> ReflectionProbe:
	var probe := ReflectionProbe.new()
	probe.update_mode = mode
	_view.add_child(probe)
	return probe


func test_every_probe_that_updates_once_counts() -> void:
	_probe()
	var room := Node3D.new()
	_view.add_child(room)
	room.add_child(ReflectionProbe.new())
	assert_int(ProbeSettle.probes_to_draw([_view])).is_equal(2)


func test_a_hidden_probe_or_one_that_updates_always_does_not() -> void:
	_probe()
	_probe().visible = false
	_probe(ReflectionProbe.UPDATE_ALWAYS)
	assert_int(ProbeSettle.probes_to_draw([_view])).is_equal(1)


func test_a_headless_run_settles_at_once() -> void:
	_probe()
	var rig: OnlineRig = auto_free(OnlineRig.new())
	add_child(rig)
	var frames := get_tree().get_frame()
	await rig.settle(_view)
	if ProbeSettle.draws_nothing():
		assert_int(get_tree().get_frame() - frames).is_equal(0)
	else:
		assert_int(get_tree().get_frame() - frames).is_less_equal(1)

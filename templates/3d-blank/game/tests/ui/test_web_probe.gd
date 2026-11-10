# The web boot check waits for the probe in the main scene: it is there, and it costs a player's
# page nothing (off the web, or without `?probe`, it never runs).
extends GdUnitTestSuite


func test_the_main_scene_holds_the_probe_the_boot_check_waits_for() -> void:
	var runner := scene_runner("res://main.tscn")
	await await_idle_frame()
	var probe: Node = runner.scene().get_node_or_null("WebProbe")
	assert_object(probe).is_not_null()
	assert_bool(probe is WebProbe).is_true()


func test_the_probe_does_nothing_off_the_web() -> void:
	var probe: WebProbe = auto_free(WebProbe.new())
	add_child(probe)
	await await_idle_frame()
	assert_bool(probe.is_processing()).is_false()

# The full-screen map: opens and closes by its action, fits the map (or the sections), shows every
# kind of marker, and does nothing while it is closed.
extends GdUnitTestSuite

const SCENE := "res://ui/minimap/map_screen.tscn"

var _root: Control
var _screen: MapScreen
var _subject: Node3D


func before_test() -> void:
	InputSim.release_all()
	_root = auto_free(Control.new()) as Control
	_root.size = Vector2(1920.0, 1080.0)
	add_child(_root)
	_subject = auto_free(Node3D.new()) as Node3D
	_subject.add_to_group(Player.GROUP)
	add_child(_subject)
	_screen = load(SCENE).instantiate() as MapScreen
	_screen.fade_time = 0.0
	_root.add_child(_screen)
	await get_tree().process_frame
	await get_tree().process_frame


func after_test() -> void:
	InputSim.release_all()
	for marker in get_tree().get_nodes_in_group(MinimapMarker.GROUP):
		marker.get_parent().queue_free()


func test_every_export_has_its_default_pinned() -> void:
	var fresh := auto_free(load(SCENE).instantiate()) as MapScreen
	var pins := {
		&"toggle_action": &"map",
		&"fit_bounds": Rect2(-26.0, -26.0, 52.0, 52.0),
		&"fit_to_sections": true,
		&"fit_margin": 1.06,
		&"fade_time": 0.15,
	}
	assert_array(ExportPins.differences(fresh, pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, pins)).is_empty()


func test_it_is_closed_at_first_and_the_map_key_opens_and_closes_it() -> void:
	assert_bool(_screen.visible).is_false()
	InputSim.key(KEY_M, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_M, false)
	await InputSim.ticks(get_tree(), 2)
	assert_bool(_screen.is_open()).is_true()
	InputSim.key(KEY_M, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_M, false)
	await InputSim.ticks(get_tree(), 2)
	assert_bool(_screen.visible).is_false()


func test_escape_closes_it() -> void:
	_screen.open()
	InputSim.key(KEY_ESCAPE, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_ESCAPE, false)
	await InputSim.ticks(get_tree(), 2)
	assert_bool(_screen.visible).is_false()


func test_it_fits_the_bounds_and_the_north_is_up() -> void:
	_screen.fit_bounds = Rect2(-10.0, -40.0, 60.0, 30.0)
	_screen.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var map := _screen.minimap()
	assert_vector(map.fixed_centre).is_equal(Vector2(20.0, -25.0))
	assert_float(map.current_range()).is_equal_approx(30.0 * 1.06, 0.001)
	assert_float(map.projector().turn).is_equal_approx(0.0, 0.0001)
	assert_vector(map.projector().centre).is_equal(Vector2(20.0, -25.0))


func test_it_fits_the_sections_when_there_are_some() -> void:
	_section(Vector3(0.0, 0.0, 0.0), Vector3(20.0, 4.0, 20.0))
	_section(Vector3(60.0, 0.0, 0.0), Vector3(20.0, 4.0, 20.0))
	_screen.open()
	assert_vector(_screen.minimap().fixed_centre).is_equal(Vector2(30.0, 0.0))
	assert_float(_screen.minimap().current_range()).is_equal_approx(40.0 * 1.06, 0.001)


func test_it_shows_every_marker_kind_where_the_small_one_may_not() -> void:
	var carrier := auto_free(Node3D.new()) as Node3D
	add_child(carrier)
	carrier.global_position = Vector3(20.0, 0.0, -20.0)
	var marker := MinimapMarker.new()
	marker.kind = &"pickup"
	carrier.add_child(marker)
	_screen.open()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_object(_screen.minimap().icon_for(marker)).is_not_null()


func test_it_renders_once_when_it_opens_and_nothing_while_it_is_closed() -> void:
	var map := _screen.minimap()
	var taken := map.snapshots_taken()
	for i in 4:
		await get_tree().process_frame
	assert_int(map.snapshots_taken()).is_equal(taken)
	_screen.open()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(map.snapshots_taken()).is_equal(taken + 1)
	for i in 4:
		await get_tree().process_frame
	assert_int(map.snapshots_taken()).is_equal(taken + 1)
	_screen.close()
	await get_tree().process_frame
	var closed_at := map.snapshots_taken()
	for i in 4:
		await get_tree().process_frame
	assert_int(map.snapshots_taken()).is_equal(closed_at)


func test_it_signals_opening_and_closing() -> void:
	var events: Array[String] = []
	_screen.opened.connect(func() -> void: events.append("opened"))
	_screen.closed.connect(func() -> void: events.append("closed"))
	_screen.open()
	_screen.close()
	assert_array(events).is_equal(["opened", "closed"])


func _section(at: Vector3, size: Vector3) -> MinimapSection:
	var section := auto_free(MinimapSection.new()) as MinimapSection
	section.size = size
	add_child(section)
	section.global_position = at
	return section

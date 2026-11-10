# The minimap in the template's own scene: it follows the character, shows the pickups, targets
# and doors of the map, and the full-screen map opens with its key.
extends GdUnitTestSuite

var _scene: Node
var _minimap: Minimap
var _player: Player


func before_test() -> void:
	InputSim.release_all()
	_scene = scene_runner("res://main.tscn").scene()
	_minimap = _scene.get_node("MinimapLayer/Minimap")
	_player = _scene.get_node("Player")
	await InputSim.ticks(get_tree(), 8)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_scene)


func test_the_minimap_follows_the_character() -> void:
	var was_at := _minimap.projector().centre
	_player.teleport(Vector3(-12.0, 0.5, 14.0))
	await InputSim.ticks(get_tree(), 4)
	await _frames(3)
	assert_vector(was_at).is_not_equal(_minimap.projector().centre)
	assert_vector(_minimap.projector().centre).is_equal_approx(
		Vector2(_player.global_position.x, _player.global_position.z), Vector2(0.05, 0.05)
	)


func test_it_sits_inside_the_screen_at_its_corner() -> void:
	var rect := _minimap.get_global_rect()
	var screen := _minimap.get_viewport().get_visible_rect()
	assert_bool(screen.encloses(rect)).is_true()
	assert_float(rect.size.x).is_equal(220.0)
	assert_float(rect.position.x + rect.size.x).is_greater(screen.size.x * 0.8)


func test_the_pickups_and_the_targets_of_the_map_carry_markers() -> void:
	var kinds := {}
	for marker: MinimapMarker in get_tree().get_nodes_in_group(MinimapMarker.GROUP):
		kinds[marker.kind] = kinds.get(marker.kind, 0) + 1
	assert_bool(kinds.get(&"pickup", 0) > 0).is_true()
	assert_bool(kinds.get(&"target", 0) > 0).is_true()
	assert_int(kinds.get(&"player", 0)).is_equal(1)


func test_the_pickups_near_the_character_are_on_the_minimap() -> void:
	var near := 0
	for marker: MinimapMarker in get_tree().get_nodes_in_group(MinimapMarker.GROUP):
		if marker.kind == &"pickup" and _minimap.icon_for(marker) != null:
			near += 1
	var expected := 0
	for marker: MinimapMarker in get_tree().get_nodes_in_group(MinimapMarker.GROUP):
		if marker.kind != &"pickup":
			continue
		var offset := _minimap.projector().to_local(marker.plane_position())
		if _minimap.projector().contains(offset):
			expected += 1
	assert_int(near).is_equal(expected)


func test_the_map_key_opens_the_whole_map() -> void:
	var screen := _scene.get_node("MinimapLayer/MapScreen") as MapScreen
	assert_bool(screen.visible).is_false()
	InputSim.key(KEY_M, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_M, false)
	await InputSim.ticks(get_tree(), 12)
	await _frames(4)
	assert_bool(screen.is_open()).is_true()
	# The player's own marker shows on the big map, since it does not follow.
	var own: MinimapMarker = null
	for marker: MinimapMarker in get_tree().get_nodes_in_group(MinimapMarker.GROUP):
		if marker.kind == &"player":
			own = marker
	assert_object(screen.minimap().icon_for(own)).is_not_null()


func test_the_workshop_is_a_section_that_names_the_map_and_slices_its_roof_off() -> void:
	_player.teleport(Vector3(14.0, 0.2, -15.0))
	await InputSim.ticks(get_tree(), 6)
	await _frames(3)
	assert_object(_minimap.current_section()).is_not_null()
	assert_str((_minimap.get_node("%SectionTitle") as Label).text).is_equal("Workshop")
	var camera := _minimap.get_node("%MapCamera") as Camera3D
	assert_float(camera.global_position.y).is_equal_approx(4.0, 0.01)
	_player.teleport(Vector3(-12.0, 0.5, 14.0))
	await InputSim.ticks(get_tree(), 6)
	await _frames(3)
	assert_object(_minimap.current_section()).is_null()


# The minimap updates on drawn frames, and a loaded machine can run physics ticks without one.
func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

# The heading component (#1047): a typed child that says which way its parent faces on the
# minimap, read by the marker and by a minimap that follows the parent. The dressed character
# carries one on its turning model, so its arrow still shows its facing; nothing in the minimap
# finds a heading by a method name.
extends GdUnitTestSuite

const DRESSED := "res://gameplay/character/character_dressed.tscn"
const DEFAULTS := {&"turns": null, &"front": 0}
## What the minimap must not use to find a heading: a method looked up or called by its name.
const NAME_LOOKUPS: Array[String] = ["has_method(", '.call(&"', '.call("']
const NEAR := Vector2(0.001, 0.001)


func test_every_export_has_its_default_pinned() -> void:
	var fresh := auto_free(MinimapHeading.new()) as MinimapHeading
	assert_array(ExportPins.differences(fresh, DEFAULTS)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, DEFAULTS)).is_empty()


func test_it_is_found_as_a_child_of_its_parent_and_not_elsewhere() -> void:
	var parent := auto_free(Node3D.new()) as Node3D
	add_child(parent)
	assert_object(MinimapHeading.of(parent)).is_null()
	assert_object(MinimapHeading.of(null)).is_null()
	var source := MinimapHeading.new()
	parent.add_child(source)
	assert_object(MinimapHeading.of(parent)).is_same(source)
	assert_object(MinimapHeading.of(source)).is_same(source)
	assert_object(MinimapHeading.of(self)).is_null()


func test_the_front_axis_decides_which_way_the_turning_node_faces() -> void:
	var parent := auto_free(Node3D.new()) as Node3D
	add_child(parent)
	var model := Node3D.new()
	parent.add_child(model)
	var source := MinimapHeading.new()
	source.turns = model
	parent.add_child(source)
	assert_vector(source.heading()).is_equal_approx(Vector2(0.0, -1.0), NEAR)
	source.front = MinimapHeading.Front.PLUS_Z
	assert_vector(source.heading()).is_equal_approx(Vector2(0.0, 1.0), NEAR)
	# Turning the parent turns the model with it: the heading is the model's, world space.
	parent.rotate_y(PI * 0.5)
	assert_vector(source.heading()).is_equal_approx(Vector2(1.0, 0.0), NEAR)


func test_with_nothing_to_turn_it_reads_its_parent_3d_or_2d() -> void:
	var parent := auto_free(Node3D.new()) as Node3D
	add_child(parent)
	var source := MinimapHeading.new()
	parent.add_child(source)
	parent.rotate_y(PI * 0.5)
	assert_vector(source.heading()).is_equal_approx(Vector2(-1.0, 0.0), NEAR)
	var flat := auto_free(Node2D.new()) as Node2D
	add_child(flat)
	var flat_source := MinimapHeading.new()
	flat.add_child(flat_source)
	flat.rotation = PI * 0.5
	assert_vector(flat_source.heading()).is_equal_approx(Vector2(0.0, 1.0), NEAR)


func test_it_warns_when_there_is_nothing_to_read() -> void:
	var holder := auto_free(Node.new()) as Node
	add_child(holder)
	var source := MinimapHeading.new()
	holder.add_child(source)
	assert_array(source._get_configuration_warnings()).is_not_empty()
	var model := Node3D.new()
	holder.add_child(model)
	source.turns = model
	assert_array(source._get_configuration_warnings()).is_empty()


func test_the_dressed_character_shows_its_facing_as_before() -> void:
	var body := load(DRESSED).instantiate() as Character
	add_child(body)
	auto_free(body)
	var marker := MinimapMarker.new()
	body.add_child(marker)
	assert_object(MinimapHeading.of(body)).is_not_null()
	for step in 8:
		var facing := -PI + step * TAU / 8.0 + 0.3
		body.teleport(Vector3.ZERO, facing)
		# What the character answered by name before #1047: (sin, cos) of its facing.
		var was := Vector2(sin(facing), cos(facing))
		assert_vector(marker.heading()).is_equal_approx(was, NEAR)


func test_nothing_in_the_minimap_finds_a_heading_by_a_method_name() -> void:
	var found: Array[String] = []
	for folder in ["res://core/minimap", "res://ui/minimap"]:
		for file in DirAccess.get_files_at(folder):
			if not file.ends_with(".gd"):
				continue
			var path: String = folder.path_join(file)
			var lines := FileAccess.get_file_as_string(path).split("\n")
			for index in lines.size():
				var line := lines[index].strip_edges()
				if line.begins_with("#"):
					continue
				for lookup in NAME_LOOKUPS:
					if line.contains(lookup):
						found.append("%s:%d %s" % [path, index + 1, line])
	assert_array(found).is_empty()

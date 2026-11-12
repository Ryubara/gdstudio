# The warm-up draws what the first shot will draw, the way it will draw it: after the reflection
# probes in view have begun (a surface a probe reaches takes another program), and with the marks
# a hit leaves as well as the effects, and inside every probe, the room the camera does not see
# included. The browser run counts the programs; these check the order.
extends GdUnitTestSuite

var _world: Node3D
var _camera: Camera3D


func before_test() -> void:
	_world = auto_free(Node3D.new())
	add_child(_world)
	_camera = Camera3D.new()
	_world.add_child(_camera)
	_camera.make_current()


func after_test() -> void:
	AudioDrain.stop_all(_world)


func _probe(at: Vector3, mode := ReflectionProbe.UPDATE_ONCE) -> ReflectionProbe:
	var probe := ReflectionProbe.new()
	probe.size = Vector3(4.0, 4.0, 4.0)
	probe.update_mode = mode
	_world.add_child(probe)
	probe.global_position = at
	return probe


func _emitter_with(effect: EffectDef) -> EffectEmitter:
	var emitter := EffectEmitter.new()
	emitter.warm_up = [effect]
	_world.add_child(emitter)
	return emitter


# Frames from now to the first warm-up draw.
func _frames_to_first_draw(emitter: EffectEmitter) -> int:
	var frames := 0
	while emitter.active_count() == 0 and emitter.is_warming():
		frames += 1
		await get_tree().process_frame
	return frames


func test_a_probe_in_view_is_counted_and_one_out_of_view_is_not() -> void:
	var emitter := _emitter_with(EffectProbe.def(true, false))
	assert_int(emitter.probe_frames(_camera)).is_equal(0)
	_probe(Vector3(0.0, 0.0, -6.0))
	assert_int(emitter.probe_frames(_camera)).is_equal(EffectEmitter.PROBE_FRAMES)
	_probe(Vector3(0.0, 0.0, 40.0))
	assert_int(emitter.probe_frames(_camera)).is_equal(EffectEmitter.PROBE_FRAMES)
	_probe(Vector3(3.0, 0.0, -10.0), ReflectionProbe.UPDATE_ALWAYS)
	assert_int(emitter.probe_frames(_camera)).is_equal(EffectEmitter.PROBE_FRAMES + 1)
	await emitter.warmed


func test_the_warm_up_waits_for_the_probes_in_view_before_it_draws() -> void:
	_probe(Vector3(0.0, 0.0, -6.0))
	var emitter := _emitter_with(EffectProbe.def(true, false))
	var frames: int = await _frames_to_first_draw(emitter)
	assert_int(frames).is_greater_equal(EffectEmitter.PROBE_FRAMES + 2)
	await emitter.warmed


func test_without_a_probe_the_warm_up_draws_at_once() -> void:
	var emitter := _emitter_with(EffectProbe.def(true, false))
	var frames: int = await _frames_to_first_draw(emitter)
	assert_int(frames).is_less_equal(3)
	await emitter.warmed


func test_the_impacts_marks_are_drawn_by_the_warm_up_and_freed_after_it() -> void:
	var emitter := _emitter_with(EffectProbe.def(true, false))
	var impacts := load("res://gameplay/impacts/impacts.tscn").instantiate() as Impacts
	_world.add_child(impacts)
	var seen: Array[Material] = []
	while emitter.is_warming():
		for speck in emitter.find_children("WarmSpeck*", "MeshInstance3D", false, false):
			var mesh := speck as MeshInstance3D
			if mesh.is_visible_in_tree() and not seen.has(mesh.material_override):
				seen.append(mesh.material_override)
		await get_tree().process_frame
	assert_object(impacts.mark_material).is_not_null()
	assert_bool(seen.has(impacts.mark_material)).is_true()
	for surface: ImpactSurface in impacts.surfaces_by_name().values():
		if surface.mark_material != null:
			assert_bool(seen.has(surface.mark_material)).is_true()
	await get_tree().process_frame
	assert_array(emitter.find_children("WarmSpeck*", "", false, false)).is_empty()


func test_a_listed_material_is_drawn_lit_when_no_effect_brings_a_light() -> void:
	var emitter := EffectEmitter.new()
	var material := StandardMaterial3D.new()
	emitter.warm_up_materials = [material]
	_world.add_child(emitter)
	var lit := false
	var drawn := false
	while emitter.is_warming():
		drawn = drawn or not emitter.find_children("WarmSpeck*", "", false, false).is_empty()
		lit = lit or not emitter.find_children("WarmLight*", "OmniLight3D", false, false).is_empty()
		await get_tree().process_frame
	assert_bool(drawn).is_true()
	assert_bool(lit).is_true()


# The places the warm-up's own camera stood at while it was warming, and the materials of the
# specks drawn while it stood inside `probe`.
func _watch_tour(emitter: EffectEmitter, probe: ReflectionProbe) -> Dictionary:
	var places: Array[Vector3] = []
	var inside: Array[Material] = []
	while emitter.is_warming():
		for view in emitter.find_children("WarmTour*", "SubViewport", false, false):
			var eye := (view as SubViewport).get_camera_3d()
			if eye == null:
				continue
			if not places.has(eye.global_position):
				places.append(eye.global_position)
			if probe != null and eye.global_position.is_equal_approx(probe.global_position):
				for speck in emitter.find_children("WarmSpeck*", "MeshInstance3D", false, false):
					var material := (speck as MeshInstance3D).material_override
					if not inside.has(material):
						inside.append(material)
		await get_tree().process_frame
	return {"places": places, "inside": inside}


func test_a_probe_out_of_view_is_visited_and_the_view_freed_after() -> void:
	var behind := _probe(Vector3(0.0, 0.0, 40.0))
	var ahead := _probe(Vector3(0.0, 0.0, -6.0))
	var emitter := _emitter_with(EffectProbe.def(true, false))
	var seen: Dictionary = await _watch_tour(emitter, behind)
	var places: Array[Vector3] = seen["places"]
	assert_bool(places.has(behind.global_position)).is_true()
	# The one in view is visited too: what is drawn inside it is under two probes there.
	assert_bool(places.has(ahead.global_position)).is_true()
	await get_tree().process_frame
	assert_array(emitter.find_children("WarmTour*", "", false, false)).is_empty()


func test_the_tour_waits_for_a_probe_the_camera_did_not_see() -> void:
	_probe(Vector3(0.0, 0.0, 40.0))
	var emitter := _emitter_with(EffectProbe.def(true, false))
	var frames := 0
	while emitter.is_warming():
		frames += 1
		await get_tree().process_frame
	# Two frames for the camera, the probe's frames, a look each way and two draws of two frames.
	var least := 2 + EffectEmitter.PROBE_FRAMES + EffectEmitter.TOUR_FACINGS.size() + 4
	assert_int(frames).is_greater_equal(least)


func test_without_the_tour_no_probe_is_visited() -> void:
	var behind := _probe(Vector3(0.0, 0.0, 40.0))
	var emitter := EffectEmitter.new()
	emitter.warm_up = [EffectProbe.def(true, false)]
	emitter.warm_up_every_probe = false
	_world.add_child(emitter)
	var seen: Dictionary = await _watch_tour(emitter, behind)
	assert_array(seen["places"]).is_empty()


func test_a_groups_meshes_are_drawn_inside_each_probe() -> void:
	var behind := _probe(Vector3(0.0, 0.0, 40.0))
	var body := MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	var skin := StandardMaterial3D.new()
	body.set_surface_override_material(0, skin)
	body.add_to_group(&"warm_up_test_body")
	_world.add_child(body)
	var emitter := EffectEmitter.new()
	emitter.warm_up = [EffectProbe.def(true, false)]
	emitter.warm_up_groups = [&"warm_up_test_body"]
	_world.add_child(emitter)
	var seen: Dictionary = await _watch_tour(emitter, behind)
	assert_bool((seen["inside"] as Array).has(skin)).is_true()


# A view of its own that draws `_world` (a live minimap): a flat environment and no shadow atlas.
func _other_view(own_world := false) -> SubViewport:
	var view := SubViewport.new()
	view.size = Vector2i(32, 32)
	view.own_world_3d = own_world
	view.positional_shadow_atlas_size = 0
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var look := Camera3D.new()
	look.environment = Environment.new()
	look.cull_mask = 5
	view.add_child(look)
	_world.add_child(view)
	look.make_current()
	return view


# The eyes of the warm-up's views while it warms: [environment, cull mask, shadow atlas size].
func _watch_eyes(emitter: EffectEmitter) -> Array:
	var eyes := []
	while emitter.is_warming():
		for view in emitter.find_children("WarmTour*", "SubViewport", false, false):
			var eye := (view as SubViewport).get_camera_3d()
			if eye == null:
				continue
			var seen := [
				eye.environment, eye.cull_mask, (view as SubViewport).positional_shadow_atlas_size
			]
			if not eyes.has(seen):
				eyes.append(seen)
		await get_tree().process_frame
	return eyes


func test_another_view_of_the_world_is_drawn_as_it_draws() -> void:
	var view := _other_view()
	var look := view.get_camera_3d()
	var emitter := _emitter_with(EffectProbe.def(true, false))
	assert_array(emitter.other_views()).contains_exactly([look])
	var eyes: Array = await _watch_eyes(emitter)
	assert_array(eyes).contains([[look.environment, 5, 0]])


func test_another_view_is_drawn_without_the_probe_tour() -> void:
	_probe(Vector3(0.0, 0.0, 40.0))
	var look := _other_view().get_camera_3d()
	var emitter := EffectEmitter.new()
	emitter.warm_up = [EffectProbe.def(true, false)]
	emitter.warm_up_every_probe = false
	_world.add_child(emitter)
	var eyes: Array = await _watch_eyes(emitter)
	assert_array(eyes).contains_exactly([[look.environment, 5, 0]])


func test_a_view_of_another_world_or_one_never_drawn_is_left_alone() -> void:
	_other_view(true)
	var idle := _other_view()
	idle.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var emitter := _emitter_with(EffectProbe.def(true, false))
	assert_array(emitter.other_views()).is_empty()
	var eyes: Array = await _watch_eyes(emitter)
	assert_array(eyes).is_empty()

# The warm-up draws what the first shot will draw, the way it will draw it: after the reflection
# probes in view have begun (a surface a probe reaches takes another program), and with the marks
# a hit leaves as well as the effects. The browser run counts the programs; these check the order.
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

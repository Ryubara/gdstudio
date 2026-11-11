# The inspector contract of `Impacts` and `ImpactSurface`: each export has its default pinned, and
# the scene opens with no configuration warning and nothing empty that it needs.
extends GdUnitTestSuite

const IMPACTS := "res://gameplay/impacts/impacts.tscn"
const MARK_MATERIAL := "res://assets/materials/impacts/impact_mark.tres"

var _impacts: Impacts


func before_test() -> void:
	_impacts = auto_free(load(IMPACTS).instantiate()) as Impacts
	add_child(_impacts)


func after_test() -> void:
	AudioDrain.stop_all(_impacts)


func test_every_impacts_export_has_its_default_pinned() -> void:
	var pins := {
		&"marks_enabled": true,
		&"max_marks": 64,
		&"mark_lifetime": 30.0,
		&"mark_fade_time": 4.0,
		&"mark_material": _impacts.mark_material,
		&"mark_size": 0.12,
		&"size_variation": 0.3,
		&"random_rotation": true,
		&"surface_offset": 0.004,
		&"random_seed": 1,
		&"effects_enabled": true,
		&"sounds_enabled": true,
		&"default_surface": _impacts.default_surface,
	}
	assert_array(ExportPins.differences(_impacts, pins)).is_empty()
	assert_array(ExportPins.wrong_values(_impacts, pins)).is_empty()
	assert_str(_impacts.mark_material.resource_path).is_equal(MARK_MATERIAL)
	assert_str(_impacts.default_surface.surface_name).is_equal("default")


func test_every_surface_export_has_its_default_pinned() -> void:
	var fresh := auto_free(ImpactSurface.new()) as ImpactSurface
	var pins := {
		&"surface_name": &"default",
		&"leaves_mark": true,
		&"mark_material": null,
		&"mark_scale": 1.0,
		&"effect": null,
	}
	assert_array(ExportPins.differences(fresh, pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, pins)).is_empty()


func test_the_scene_opens_with_no_warning_and_every_surface_has_what_it_needs() -> void:
	assert_array(_impacts._get_configuration_warnings()).is_empty()
	for surface: ImpactSurface in _impacts.surfaces_by_name().values():
		assert_array(surface._get_configuration_warnings()).is_empty()
		var burst := surface.effect.particles.instantiate() as CPUParticles3D
		assert_bool(burst != null and burst.one_shot).is_true()
		assert_bool(burst.emitting).is_false()
		burst.free()


func test_an_impacts_with_no_surface_says_so() -> void:
	var bare := auto_free(Impacts.new()) as Impacts
	assert_int(bare._get_configuration_warnings().size()).is_equal(1)


func test_the_default_mark_material_draws_the_hole_with_a_fade_the_marks_can_set() -> void:
	var material := _impacts.mark_material as ShaderMaterial
	assert_object(material).is_not_null()
	var uniforms: Array[String] = []
	for uniform in material.shader.get_shader_uniform_list(false):
		uniforms.append(String(uniform["name"]))
	for needed in ["use_texture", "mark_texture", "hole_color", "ring_color", "lift"]:
		(
			assert_bool(uniforms.has(needed))
			. override_failure_message("%s is not a uniform: %s" % [needed, uniforms])
			. is_true()
		)
	# An instance uniform is not in that list: the marks set it by name.
	assert_bool(material.shader.code.contains("instance uniform float fade")).is_true()

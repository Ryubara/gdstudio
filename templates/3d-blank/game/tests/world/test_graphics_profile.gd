# The graphics profile's inspector contract: every export has its default pinned, and each one is
# changed while the level runs and its effect read on the environment, the sun and the lightmaps.
# The renderer of a test run is not Forward+, so a test says it is.
extends GdUnitTestSuite

var _world: WorldEnvironment
var _sun: DirectionalLight3D
var _lightmap: LightmapGI
var _profile: GraphicsProfile
var _source: Environment


func before_test() -> void:
	_source = Environment.new()
	_world = WorldEnvironment.new()
	_world.environment = _source
	_sun = DirectionalLight3D.new()
	_sun.directional_shadow_max_distance = 60.0
	_lightmap = LightmapGI.new()
	_profile = GraphicsProfile.new()
	_profile.world_environment = _world
	_profile.sun = _sun
	_profile.lightmap = _lightmap
	_profile._supported = true
	for node in [_world, _sun, _lightmap, _profile]:
		add_child(node)


func after_test() -> void:
	for node in [_world, _sun, _lightmap, _profile]:
		node.free()


func _environment() -> Environment:
	return _world.environment


func test_every_export_has_its_default_pinned() -> void:
	var fresh := GraphicsProfile.new()
	var pins := {
		&"world_environment": null,
		&"sun": null,
		&"lightmap": null,
		&"enabled": true,
		&"global_light": GraphicsProfile.GlobalLight.BAKED,
		&"ambient_occlusion": true,
		&"indirect_light": true,
		&"reflections": true,
		&"volumetric_fog": true,
		&"volumetric_density": 0.012,
		&"exposure_match": 1.35,
		&"finer_shadows": true,
	}
	assert_array(ExportPins.differences(fresh, pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, pins)).is_empty()
	fresh.free()


func test_the_defaults_turn_the_extras_on_a_copy_of_the_environment() -> void:
	assert_object(_environment()).is_not_same(_source)
	assert_bool(_environment().ssao_enabled).is_true()
	assert_bool(_source.ssao_enabled).is_false()


func test_each_extra_follows_its_switch_at_once() -> void:
	_profile.ambient_occlusion = false
	assert_bool(_environment().ssao_enabled).is_false()
	_profile.indirect_light = false
	assert_bool(_environment().ssil_enabled).is_false()
	_profile.reflections = false
	assert_bool(_environment().ssr_enabled).is_false()
	_profile.volumetric_fog = false
	assert_bool(_environment().volumetric_fog_enabled).is_false()
	_profile.ambient_occlusion = true
	assert_bool(_environment().ssao_enabled).is_true()


func test_the_haze_and_the_exposure_follow_their_numbers_without_stacking() -> void:
	_profile.volumetric_density = 0.05
	assert_float(_environment().volumetric_fog_density).is_equal_approx(0.05, 0.0001)
	_profile.exposure_match = 2.0
	assert_float(_environment().tonemap_exposure).is_equal_approx(2.0, 0.0001)
	_profile.exposure_match = 1.0
	assert_float(_environment().tonemap_exposure).is_equal_approx(1.0, 0.0001)


func test_the_global_light_chooses_between_baked_and_live_bounce_light() -> void:
	assert_bool(_lightmap.visible).is_true()
	_profile.global_light = GraphicsProfile.GlobalLight.SDFGI
	assert_bool(_environment().sdfgi_enabled).is_true()
	assert_bool(_lightmap.visible).is_false()
	_profile.global_light = GraphicsProfile.GlobalLight.BAKED
	assert_bool(_environment().sdfgi_enabled).is_false()
	assert_bool(_lightmap.visible).is_true()


func test_the_finer_shadows_switch_the_suns_cascades_and_back() -> void:
	assert_int(_sun.directional_shadow_mode).is_equal(DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	_profile.finer_shadows = false
	assert_int(_sun.directional_shadow_mode).is_equal(DirectionalLight3D.SHADOW_ORTHOGONAL)
	assert_float(_sun.directional_shadow_max_distance).is_equal(60.0)


func test_enabled_off_gives_the_level_its_own_environment_back() -> void:
	_profile.enabled = false
	assert_object(_environment()).is_same(_source)
	assert_bool(_lightmap.visible).is_true()
	_profile.enabled = true
	assert_bool(_environment().ssao_enabled).is_true()


func test_a_new_target_gets_the_extras() -> void:
	var other := WorldEnvironment.new()
	other.environment = Environment.new()
	add_child(other)
	_profile.world_environment = other
	assert_bool(other.environment.ssao_enabled).is_true()
	other.free()


func test_a_build_that_cannot_draw_the_extras_is_left_alone() -> void:
	var plain := Environment.new()
	var world := WorldEnvironment.new()
	world.environment = plain
	var profile := GraphicsProfile.new()
	profile._supported = false
	profile.world_environment = world
	add_child(world)
	add_child(profile)
	profile.ambient_occlusion = false
	profile.exposure_match = 2.0
	assert_object(world.environment).is_same(plain)
	profile.free()
	world.free()

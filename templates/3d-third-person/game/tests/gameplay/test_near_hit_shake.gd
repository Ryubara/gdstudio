# A hit near the player shakes the camera (gdstudio #1068), on the real rig in the main scene: a hit
# the level's `Impacts` plays 2 m from the camera shakes it, one 20 m away does not, and the
# player's shake setting (`CameraShake.strength`) at zero turns it off. Online:
# `test_near_hit_shake_online.gd`. Stepped by hand, no real time.
extends GdUnitTestSuite

const STEP := 1.0 / 60.0
const NEAR_HIT := "res://core/camera_shake/presets/near_hit.tres"

var _scene: Node
var _rig: PlayerCamera
var _shake: NearHitShake
var _impacts: Impacts


func before_test() -> void:
	InputSim.release_all()
	CameraShake.strength = 1.0
	_scene = scene_runner("res://main.tscn").scene()
	_rig = _scene.get_node("PlayerRig/PlayerCamera")
	_shake = _rig.get_node_or_null("NearHitShake") as NearHitShake
	_impacts = Impacts.find(_rig)
	await InputSim.ticks(get_tree(), 8)
	_rig.shaker.clear()


func after_test() -> void:
	InputSim.release_all()
	CameraShake.strength = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioDrain.stop_all(_scene)


# A point `metres` in front of the camera that draws the rig's view.
func _ahead(metres: float) -> Vector3:
	var camera := _rig.get_viewport().get_camera_3d()
	return camera.global_position - camera.global_basis.z * metres


func _hit_at(point: Vector3) -> void:
	_impacts.impact(null, point, Vector3.UP)


# Steps the rig and returns the largest turn of the view seen, in degrees.
func _step(seconds: float) -> float:
	var peak := 0.0
	for _i in roundi(seconds / STEP):
		_rig.advance(STEP)
		peak = maxf(peak, _rig.current_shake().length())
	return peak


func test_the_rig_has_a_near_hit_shake_listening_to_the_level() -> void:
	assert_object(_shake).is_not_null()
	assert_object(_shake.preset).is_not_null()
	assert_str(_shake.preset.resource_path).is_equal(NEAR_HIT)
	assert_object(_shake._shaker()).is_same(_rig.shaker)
	assert_object(_impacts).is_not_null()
	assert_object(_shake.listening_to()).is_same(_impacts)


func test_every_export_has_its_default_pinned() -> void:
	var fresh := auto_free(NearHitShake.new()) as NearHitShake
	var pins := {
		&"enabled": true,
		&"preset": null,
		&"strength": 1.0,
		&"shaker": null,
		&"impacts": null,
	}
	assert_array(ExportPins.differences(fresh, pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, pins)).is_empty()
	# The preset's numbers: felt beside the player, gone past 12 m, a tenth of a degree at most.
	var preset := load(NEAR_HIT) as ShakePreset
	assert_float(preset.trauma).is_equal(0.4)
	assert_float(preset.duration).is_equal(0.3)
	assert_float(preset.radius).is_equal(12.0)
	assert_vector(preset.max_rotation).is_equal(Vector3(0.8, 0.8, 0.4))


func test_a_hit_2_m_from_the_camera_shakes_it() -> void:
	_hit_at(_ahead(2.0))
	assert_float(_rig.shaker.trauma_of(_shake.preset)).is_greater(0.35)
	var peak := _step(0.2)
	assert_float(peak).is_greater(0.01)
	# Subtle: a tenth of a degree or so, so the crosshair barely moves.
	assert_float(peak).is_less(0.2)
	_step(0.3)
	assert_bool(_rig.shaker.is_shaking()).is_false()


func test_a_hit_20_m_from_the_camera_does_not() -> void:
	_hit_at(_ahead(20.0))
	assert_float(_rig.shaker.trauma_of(_shake.preset)).is_equal(0.0)
	assert_float(_step(0.2)).is_equal(0.0)
	assert_bool(_rig.shaker.is_shaking()).is_false()


func test_the_shake_setting_at_zero_turns_it_off() -> void:
	CameraShake.strength = 0.0
	_hit_at(_ahead(2.0))
	assert_float(_step(0.2)).is_equal(0.0)
	assert_bool(_rig.shaker.is_shaking()).is_false()
	# Half the setting is a quarter of the trauma's square: less than at full.
	CameraShake.strength = 1.0
	_hit_at(_ahead(2.0))
	var full := _step(0.1)
	_rig.shaker.clear()
	CameraShake.strength = 0.5
	_hit_at(_ahead(2.0))
	assert_float(_step(0.1)).is_less(full)


func test_its_own_strength_and_switch_scale_it() -> void:
	_shake.enabled = false
	_hit_at(_ahead(2.0))
	assert_bool(_rig.shaker.is_shaking()).is_false()
	_shake.enabled = true
	_shake.strength = 0.5
	_hit_at(_ahead(2.0))
	var half := _rig.shaker.trauma_of(_shake.preset)
	_rig.shaker.clear()
	_shake.strength = 1.0
	_hit_at(_ahead(2.0))
	assert_float(half).is_equal_approx(_rig.shaker.trauma_of(_shake.preset) * 0.5, 0.001)

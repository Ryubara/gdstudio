# The player's camera shake option: `controls/camera_shake` (0 to 100 %) sets the global
# `CameraShake.strength` at start and on every change, 0 turns every shake off (a one-shot at a
# position, one felt in full, a held source), and the value survives a restart of the service. The
# service is made from its scene on a file of its own (TempUserFile), so the autoload and the
# person's file are never touched.
extends GdUnitTestSuite

const SCENE := "res://core/settings/settings_service.tscn"
const IMPACT := preload("res://core/camera_shake/presets/impact.tres")
const SHOT := preload("res://core/camera_shake/presets/shot.tres")
const SPRINT := preload("res://core/camera_shake/presets/sprint.tres")
const STEP := 1.0 / 60.0

## This run's own file, so a run beside it never reads or deletes it (TempUserFile).
var _path := TempUserFile.path("settings_camera_shake_test")
var _shaker: CameraShake


func before_test() -> void:
	TempUserFile.remove(_path)
	CameraShake.strength = 1.0
	var eye: Camera3D = auto_free(Camera3D.new())
	add_child(eye)
	_shaker = auto_free(CameraShake.new())
	_shaker.auto_advance = false
	_shaker.reference = eye
	add_child(_shaker)


func after_test() -> void:
	CameraShake.strength = 1.0
	TempUserFile.remove(_path)


func _make(path := "") -> SettingsService:
	var service := load(SCENE).instantiate() as SettingsService
	service.path = path
	service.is_web = false
	service.window_setter = func(_mode: int) -> void: pass
	add_child(service)
	return auto_free(service)


## Plays every kind of shake on the shaker and returns the largest turn seen in half a second.
func _peak_of_every_shake() -> float:
	_shaker.clear()
	CameraShake.shake(IMPACT, Vector3(2.0, 0.0, 0.0))
	CameraShake.shake(SHOT)
	_shaker.hold(&"sprint", SPRINT, 1.0)
	var peak := 0.0
	for _i in 30:
		_shaker.advance(STEP)
		peak = maxf(peak, _shaker.rotation_degrees().length())
	return peak


func test_the_option_is_full_by_default_and_ranges_from_0_to_100() -> void:
	var service := _make()
	assert_int(service.get_value(SettingsService.CAMERA_SHAKE)).is_equal(100)
	assert_int(service.default_value(SettingsService.CAMERA_SHAKE)).is_equal(100)
	service.set_value(SettingsService.CAMERA_SHAKE, 250)
	assert_int(service.get_value(SettingsService.CAMERA_SHAKE)).is_equal(100)
	service.set_value(SettingsService.CAMERA_SHAKE, -5)
	assert_int(service.get_value(SettingsService.CAMERA_SHAKE)).is_equal(0)


func test_a_change_sets_the_global_strength_at_once() -> void:
	var service := _make()
	service.set_value(SettingsService.CAMERA_SHAKE, 40)
	assert_float(CameraShake.strength).is_equal_approx(0.4, 0.0001)
	service.set_value(SettingsService.CAMERA_SHAKE, 0)
	assert_float(CameraShake.strength).is_equal(0.0)
	service.reset_defaults()
	assert_float(CameraShake.strength).is_equal(1.0)


func test_zero_turns_every_shake_off_and_full_leaves_them_on() -> void:
	var service := _make()
	assert_float(_peak_of_every_shake()).is_greater(0.05)
	service.set_value(SettingsService.CAMERA_SHAKE, 0)
	assert_float(_peak_of_every_shake()).is_equal(0.0)
	assert_bool(_shaker.is_shaking()).is_false()


func test_a_near_hit_two_metres_away_shakes_nothing_at_zero() -> void:
	var service := _make()
	service.set_value(SettingsService.CAMERA_SHAKE, 0)
	_shaker.clear()
	CameraShake.shake(IMPACT, Vector3(2.0, 0.0, 0.0))
	_shaker.advance(STEP)
	assert_float(_shaker.trauma_of(IMPACT)).is_equal(0.0)
	assert_vector(_shaker.rotation_degrees()).is_equal(Vector3.ZERO)


func test_half_halves_the_turn() -> void:
	var service := _make()
	var full := _peak_of_every_shake()
	service.set_value(SettingsService.CAMERA_SHAKE, 50)
	assert_float(_peak_of_every_shake()).is_equal_approx(full * 0.5, full * 0.01)


func test_the_value_survives_a_restart_and_is_applied_at_start() -> void:
	var first := _make(_path)
	first.set_value(SettingsService.CAMERA_SHAKE, 25)
	assert_int(first.save()).is_equal(OK)
	CameraShake.strength = 1.0
	var second := _make(_path)
	assert_int(second.get_value(SettingsService.CAMERA_SHAKE)).is_equal(25)
	assert_float(CameraShake.strength).is_equal_approx(0.25, 0.0001)


func test_a_restart_at_zero_starts_with_every_shake_off() -> void:
	var first := _make(_path)
	first.set_value(SettingsService.CAMERA_SHAKE, 0)
	first.save()
	CameraShake.strength = 1.0
	_make(_path)
	assert_float(CameraShake.strength).is_equal(0.0)
	assert_float(_peak_of_every_shake()).is_equal(0.0)

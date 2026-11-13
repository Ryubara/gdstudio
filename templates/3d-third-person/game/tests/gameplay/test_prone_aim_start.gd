# Aiming and letting the aim go while lying down (kit #1356), in the template's main scene through
# simulated input, on both `form` bodies: on every drawn update while the prone aim blends in from
# the prone idle and back out, read as drawn after every modifier (`ProneAimWatch`), neither hand
# goes under the floor, neither arm folds back under the chest, and the pistol never shows under
# the floor. The aim layer once solved on the drawn pose and turned the chest down 30 degrees at a
# tenth of the blend (the hands 0.3 m under the floor), and the blend of the two clips takes the
# left hand 6 to 7 cm under it on the way (`HandFloor` raises the arms).
extends GdUnitTestSuite

## Open ground on the east side of the map, where the prone aim tour lies down too.
const OPEN_GROUND := Vector3(5.5, 0.0, 8.0)

var _runner: GdUnitSceneRunner
var _player: Player


func before_test() -> void:
	InputSim.release_all()
	_runner = scene_runner("res://main.tscn")
	_player = _runner.scene().get_node("PlayerRig/Player")
	await InputSim.ticks(get_tree(), 12)
	_player.teleport(OPEN_GROUND, PI)
	await InputSim.ticks(get_tree(), 20)


func after_test() -> void:
	InputSim.release_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _aim_in_and_out(label: String) -> void:
	InputSim.key(KEY_Z, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_Z, false)
	await InputSim.ticks(get_tree(), 60)
	assert_bool(_player.prone).is_true()
	var watch := ProneAimWatch.new(_player)
	watch.start()
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	for _frame in 30:
		await get_tree().process_frame
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)
	for _frame in 30:
		await get_tree().process_frame
	watch.stop()
	var fails := watch.failures(label)
	assert_array(fails).override_failure_message("\n".join(fails)).is_empty()


func test_the_arms_stay_over_the_floor_as_the_aim_starts_and_ends_lying() -> void:
	await _aim_in_and_out("female")


func test_the_same_on_the_male_body() -> void:
	var model := _player.get_node("Model") as CharacterModel
	model.variant = load(CharacterBodies.MALE)
	await InputSim.ticks(get_tree(), 4)
	await _aim_in_and_out("male")

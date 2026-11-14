# The arms stay out of the chest on a rifle peek lean (gdstudio #1436): aiming the rifle and
# leaning, crouched or standing, either way, on both prototype bodies, no vertex of the upper arms'
# and forearms' skin is inside the torso's skin as drawn (`BodyClearance.arms_in_torso()`, read
# after the hold's modifiers every update for a while), nor any point of the rifle in the torso.
# Before, leaning swung the shoulders round past the hold's chest turn and the right arm went
# 29 to 42 mm into the chest crouched and 31 to 72 mm leaning left (its upright aim: 0).
extends GdUnitTestSuite

const RIFLE := "res://gameplay/weapon/rifle.tres"
## How deep an arm's skin may be in the torso's, metres (the shoulder's own skin, which meets the
## chest's in every pose, is left out by `BodyClearance.SHOULDER`; every case measures 0 now).
const ARM_SLACK := 0.004
## How deep a point of the rifle may be in the torso, metres (`test_rifle_hold`'s stock test).
const RIFLE_SLACK := 0.01
## Ticks for the lean and the aim to settle, then how many updates are read.
const SETTLE := 50
const UPDATES := 12

var _arena: PlayArena
var _player: Player
var _skeleton: Skeleton3D
var _contact: HandContact
var _clearance: BodyClearance
var _near: Node3D
var _deepest := {}


func before_test() -> void:
	InputSim.release_all()


func after_test() -> void:
	InputSim.release_all()
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


func test_the_arms_stay_out_of_the_chest_on_a_rifle_lean(
	body: String,
	crouched: bool,
	_test_parameters := [["female", true], ["female", false], ["male", true], ["male", false]]
) -> void:
	await _player_with_rifle(body)
	if crouched:
		InputSim.key(KEY_C, true)
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), SETTLE)
	var upright := await _deepest_while("%s %s upright" % [body, _stance(crouched)])
	for key: Key in [KEY_E, KEY_Q]:
		InputSim.key(key, true)
		await InputSim.ticks(get_tree(), SETTLE)
		var tag := "%s %s lean %s" % [body, _stance(crouched), OS.get_keycode_string(key)]
		assert_float(absf(_player.peek_motion.amount)).override_failure_message(tag).is_equal(1.0)
		var leaning := await _deepest_while(tag)
		(
			assert_float(leaning.arm)
			. override_failure_message(
				(
					"%s: the %s's skin %.1f mm in the %s (upright %.1f)"
					% [tag, leaning.bone, leaning.arm * 1000.0, leaning.torso, upright.arm * 1000.0]
				)
			)
			. is_less(ARM_SLACK)
		)
		(
			assert_float(leaning.rifle)
			. override_failure_message(
				"%s: the rifle %.1f mm in the body" % [tag, leaning.rifle * 1000.0]
			)
			. is_less(RIFLE_SLACK)
		)
		InputSim.key(key, false)
		await InputSim.ticks(get_tree(), SETTLE)


func _stance(crouched: bool) -> String:
	return "crouched" if crouched else "standing"


func _player_with_rifle(body: String) -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_player._present_facing()
	if body == "male":
		var slot := _player.model
		var old := slot.rig()
		slot.remove_child(old)
		old.free()
		slot.add_child((load(CharacterBodies.MALE) as PackedScene).instantiate())
	var view := Camera3D.new()
	view.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(view)
	view.make_current()
	await InputSim.ticks(get_tree(), 10)
	_skeleton = _player.model.skeleton()
	_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	await InputSim.ticks(get_tree(), 60)
	assert_str(_player.weapon.definition.display_name).is_equal("Rifle")
	var hold := _player.model.get_node("RifleHeld") as TwoHandHold
	_near = hold.get_node(^"Pivot/Rifle/Near") as Node3D
	_contact = HandContact.new(_skeleton)
	_contact.set_weapon(_near)
	_clearance = BodyClearance.new(_skeleton, _contact, _near)


# The deepest an arm's skin went into the torso, and the rifle into it, over `UPDATES` updates of
# the skeleton: {"arm", "bone", "torso", "rifle", "rifle_bone", "right", "left"}, the last two each
# arm's deepest in millimetres and that vertex's distance from its shoulder in centimetres.
func _deepest_while(tag: String) -> Dictionary:
	_deepest = {
		"arm": 0.0,
		"bone": &"",
		"torso": &"",
		"rifle": 0.0,
		"rifle_bone": &"",
		"right": [0.0, 0.0],
		"left": [0.0, 0.0],
	}
	_skeleton.skeleton_updated.connect(_contact.snapshot)
	_skeleton.skeleton_updated.connect(_read)
	for update in UPDATES:
		await _skeleton.skeleton_updated
	_skeleton.skeleton_updated.disconnect(_read)
	_skeleton.skeleton_updated.disconnect(_contact.snapshot)
	prints(
		"peek arms",
		tag,
		"arm mm",
		snappedf(_deepest.arm * 1000.0, 0.1),
		_deepest.bone,
		_deepest.torso,
		"rifle mm",
		snappedf(_deepest.rifle * 1000.0, 0.1),
		_deepest.rifle_bone,
		"right",
		_deepest.right,
		"left",
		_deepest.left
	)
	return _deepest.duplicate()


func _read() -> void:
	var arms := _clearance.arms_in_torso()
	if arms.depth > _deepest.arm:
		_deepest.arm = arms.depth
		_deepest.bone = arms.bone
		_deepest.torso = arms.torso
	var gun := _clearance.deepest(_near)
	if gun.depth > _deepest.rifle:
		_deepest.rifle = gun.depth
		_deepest.rifle_bone = gun.bone
	for pair: Array in [["right", &"upperarm_r"], ["left", &"upperarm_l"]]:
		var per: Dictionary = arms.sides[pair[1]]
		if per.depth * 1000.0 > _deepest[pair[0]][0]:
			_deepest[pair[0]] = [
				snappedf(per.depth * 1000.0, 0.1), snappedf(per.from_shoulder * 100.0, 0.1)
			]

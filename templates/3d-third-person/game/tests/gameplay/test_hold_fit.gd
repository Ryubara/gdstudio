# Each body holds each weapon with its own solved hold (kit #1187): the hold scene's own poses, seat
# and markers are the default body's (the female), and `WeaponHold.fits` (the pistol) and
# `TwoHandHold.fits` (the rifle) give the male his `HoldFit`, put on when the model is his file and
# taken off again when the model changes back.
extends GdUnitTestSuite

const MALE_FIT := "res://gameplay/weapon/hold/pistol_fit_male.tres"
const MALE_RIFLE_FIT := "res://gameplay/weapon/hold/rifle_fit_male.tres"

var _holder: Node3D


func before_test() -> void:
	_holder = auto_free(Node3D.new())
	add_child(_holder)


func test_the_template_wears_the_form_bodies() -> void:
	var dressed := (
		(load("res://gameplay/character/character_dressed.tscn") as PackedScene).instantiate()
	)
	var slot := dressed.get_node("Model") as CharacterModel
	assert_str(slot.rig().scene_file_path).is_equal(CharacterBodies.FEMALE)
	dressed.free()
	for kind in ["enemy_grunt", "enemy_shooter"]:
		var scene := load("res://gameplay/ai/characters/%s.tscn" % kind) as PackedScene
		var enemy := scene.instantiate()
		var model := enemy.get_node("Model") as CharacterModel
		assert_str(model.variant.resource_path).is_equal(CharacterBodies.MALE)
		enemy.free()


func test_the_male_body_holds_with_his_fit() -> void:
	var fit := load(MALE_FIT) as HoldFit
	assert_str(fit.body).is_equal(CharacterBodies.MALE.get_file())
	var stage := HoldStage.make(_holder, "male")
	await _frames(2)
	assert_object(stage.hold.call(&"fit")).is_same(fit)
	assert_bool(stage.pistol.transform.is_equal_approx(fit.seat)).is_true()
	var support := stage.pistol.get_node("SupportHand") as Node3D
	assert_bool(support.transform.is_equal_approx(fit.support_hand)).is_true()
	assert_object(stage.hold.get(&"grip_pose")).is_same(fit.grip_pose)
	assert_vector(stage.hold.get(&"support_way")).is_equal(fit.support_way)
	stage.free()


func test_the_female_body_keeps_the_scenes_own_hold() -> void:
	var held := (load(HoldStage.PISTOL_HELD) as PackedScene).instantiate() as Node3D
	var own_seat := (held.get_child(0) as Node3D).transform
	held.free()
	var stage := HoldStage.make(_holder, "female")
	await _frames(2)
	assert_str((stage.hold.call(&"fit") as HoldFit).body).is_empty()
	assert_bool(stage.pistol.transform.is_equal_approx(own_seat)).is_true()
	assert_object(stage.hold.get(&"grip_pose")).is_same(
		load("res://gameplay/weapon/hold/pistol_grip_pose.tres")
	)
	stage.free()


func test_a_swap_to_the_male_and_back_puts_each_hold_on() -> void:
	var stage := HoldStage.make(_holder, "female")
	await _frames(2)
	var own_seat := stage.pistol.transform
	var fit := load(MALE_FIT) as HoldFit
	_swap(stage, CharacterBodies.MALE)
	await _frames(3)
	assert_bool(stage.pistol.transform.is_equal_approx(fit.seat)).is_true()
	_swap(stage, CharacterBodies.FEMALE)
	await _frames(3)
	assert_bool(stage.pistol.transform.is_equal_approx(own_seat)).is_true()
	stage.free()


func test_the_male_body_holds_the_rifle_with_his_fit() -> void:
	var fit := load(MALE_RIFLE_FIT) as HoldFit
	assert_str(fit.body).is_equal(CharacterBodies.MALE.get_file())
	var stage := RifleStage.make_rifle(_holder, "male", false)
	await _frames(2)
	assert_object(stage.hold.call(&"fit")).is_same(fit)
	_assert_rifle_places(stage, fit)
	assert_object(stage.hold.get(&"grip_pose")).is_same(fit.grip_pose)
	assert_object(stage.hold.get(&"support_pose")).is_same(fit.support_pose)
	# His trigger finger has its own way round the guard too (kit #1036).
	assert_object(fit.trigger_way).is_not_null()
	assert_object(stage.hold.get(&"trigger_way")).is_same(fit.trigger_way)
	stage.free()


func test_a_swap_keeps_the_rifles_own_hold_for_the_female() -> void:
	var stage := RifleStage.make_rifle(_holder, "female", false)
	await _frames(2)
	var own := stage.hold.call(&"fit") as HoldFit
	assert_str(own.body).is_empty()
	assert_object(stage.hold.get(&"grip_pose")).is_same(
		load("res://gameplay/weapon/hold/rifle_grip_pose.tres")
	)
	var own_way: Object = stage.hold.get(&"trigger_way")
	assert_object(own_way).is_same(load("res://gameplay/weapon/hold/rifle_trigger_way.tres"))
	_swap(stage, CharacterBodies.MALE)
	await _frames(3)
	_assert_rifle_places(stage, load(MALE_RIFLE_FIT) as HoldFit)
	assert_object(stage.hold.get(&"trigger_way")).is_not_same(own_way)
	_swap(stage, CharacterBodies.FEMALE)
	await _frames(3)
	_assert_rifle_places(stage, own)
	assert_object(stage.hold.get(&"trigger_way")).is_same(own_way)
	stage.free()


# The rifle's hands' places are the fit's: the right hand's the inverse of its seat.
func _assert_rifle_places(stage: RifleStage, fit: HoldFit) -> void:
	var right := stage.rifle.get_node("RightHandTarget") as Node3D
	var left := stage.rifle.get_node("LeftHandTarget") as Node3D
	var magazine := stage.rifle.get_node("MagazineHand") as Node3D
	assert_bool(right.transform.is_equal_approx(fit.seat.affine_inverse())).is_true()
	assert_bool(left.transform.is_equal_approx(fit.support_hand)).is_true()
	assert_bool(magazine.transform.is_equal_approx(fit.magazine_hand)).is_true()


# Replaces the stage's model the way the slot's `variant` does it in the game.
func _swap(stage: HoldStage, path: String) -> void:
	stage.slot.variant = load(path) as PackedScene


func _frames(count: int) -> void:
	for frame in count:
		await get_tree().process_frame

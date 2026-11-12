# The order in which `HandPoseModifier` opens a hand's bones (kit #889): the bones `open_first`
# names open over the first share of `open_weight` and the others after them, so fingers hooked
# over a part let go at the knuckles first; `open_together` opens every bone as one, which the
# rifle's hold switches on while the fingers close round the magazine.
extends GdUnitTestSuite

const KNUCKLE := &"finger_01"
const TIP := &"finger_02"

var _skeleton: Skeleton3D
var _modifier: HandPoseModifier
var _open_turn := Quaternion(Vector3.RIGHT, PI / 2.0)


func before_test() -> void:
	_skeleton = auto_free(Skeleton3D.new())
	add_child(_skeleton)
	_skeleton.add_bone(KNUCKLE)
	_skeleton.add_bone(TIP)
	_skeleton.set_bone_parent(1, 0)
	var closed := HandPose.new()
	closed.rotations = {KNUCKLE: Quaternion.IDENTITY, TIP: Quaternion.IDENTITY}
	var open := HandPose.new()
	open.rotations = {KNUCKLE: _open_turn, TIP: _open_turn}
	_modifier = HandPoseModifier.new()
	_modifier.pose = closed
	_modifier.open = open
	_modifier.open_first = [KNUCKLE]
	_skeleton.add_child(_modifier)


func test_the_knuckle_opens_before_the_rest_by_default() -> void:
	assert_bool(_modifier.open_together).is_false()
	assert_float(_modifier.open_first_share).is_equal(0.5)
	_modifier.open_weight = 0.25
	_modifier._process_modification_with_delta(0.0)
	assert_float(_opened(0)).is_equal_approx(0.5, 0.001)
	assert_float(_opened(1)).is_equal_approx(0.0, 0.001)
	_modifier.open_weight = 0.75
	_modifier._process_modification_with_delta(0.0)
	assert_float(_opened(0)).is_equal_approx(1.0, 0.001)
	assert_float(_opened(1)).is_equal_approx(0.5, 0.001)


func test_open_together_opens_every_bone_as_one_and_switches_live() -> void:
	_modifier.open_weight = 0.25
	_modifier.open_together = true
	_modifier._process_modification_with_delta(0.0)
	assert_float(_opened(0)).is_equal_approx(0.25, 0.001)
	assert_float(_opened(1)).is_equal_approx(0.25, 0.001)
	_modifier.open_together = false
	_modifier._process_modification_with_delta(0.0)
	assert_float(_opened(0)).is_equal_approx(0.5, 0.001)
	assert_float(_opened(1)).is_equal_approx(0.0, 0.001)


# How far bone `index` is turned from closed to the open pose (0 to 1).
func _opened(index: int) -> float:
	return _skeleton.get_bone_pose_rotation(index).angle_to(Quaternion.IDENTITY) / (PI / 2.0)

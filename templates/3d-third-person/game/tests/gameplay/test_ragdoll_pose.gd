# The animated pose's speed at a death, read once a tick while the animation moves on its own
# clock (gdstudio #1359): the character's tree runs on idle frames, so after a slow frame two or
# three ticks run with no frame between them, and a throttled tree is moved every few ticks.
extends GdUnitTestSuite

const BODIES := [{bone = &"hand"}]
const TICK := 1.0 / 60.0
## The hand's speed in the clip. Metres a second.
const SPEED := 3.0
## A body's speed is read in m/s; anything over this is a jump of the pose.
const FASTEST := 40.0

var _skeleton: Skeleton3D
var _pose: RagdollPose
var _hand := 0
# Where the clip has the hand: time in it, in seconds.
var _clip_time := 0.0


func before_test() -> void:
	_skeleton = auto_free(Skeleton3D.new())
	_hand = _skeleton.add_bone("hand")
	add_child(_skeleton)
	_pose = RagdollPose.new(BODIES)
	_clip_time = 0.0


# The animation runs `seconds` (an idle frame, or a throttled advance).
func _animate(seconds: float) -> void:
	_clip_time += seconds
	_skeleton.set_bone_pose_position(_hand, Vector3(SPEED * _clip_time, 0.0, 0.0))


func _speed() -> float:
	var found := _pose.body_velocity(&"hand", Transform3D.IDENTITY, TICK, FASTEST)
	return found[0].length() if not found.is_empty() else -1.0


func test_a_pose_moved_every_tick_gives_its_speed() -> void:
	for _tick in 4:
		_animate(TICK)
		_pose.sample(_skeleton)
	assert_bool(_pose.is_ready()).is_true()
	assert_float(_speed()).is_equal_approx(SPEED, 0.001)


# The engine runs a frame's physics ticks before its idle frame: a slow frame's three ticks read the
# pose of the frame before it, and the frame then moves the pose by the three ticks of time.
func test_a_slow_frame_s_ticks_give_the_clip_s_speed_on_every_tick() -> void:
	_frame(1)
	_frame(1)
	_frame(1)
	for ticks in [3, 1, 2, 1, 1, 3, 1]:
		for tick in ticks:
			_pose.sample(_skeleton)
			(
				assert_float(_speed())
				. override_failure_message(
					"tick %d of a %d-tick frame: %.2f m/s" % [tick, ticks, _speed()]
				)
				. is_equal_approx(SPEED, 0.001)
			)
		_animate(TICK * ticks)


# A frame of `ticks` physics ticks, then its idle frame.
func _frame(ticks: int) -> void:
	for _tick in ticks:
		_pose.sample(_skeleton)
	_animate(TICK * ticks)


func test_a_tree_moved_every_fourth_tick_gives_its_speed_on_any_tick() -> void:
	for tick in 16:
		if tick % 4 == 0:
			_animate(TICK * 4.0)
		_pose.sample(_skeleton)
		if tick >= 4:
			(
				assert_float(_speed())
				. override_failure_message("tick %d: %.2f m/s" % [tick, _speed()])
				. is_equal_approx(SPEED, 0.001)
			)


func test_a_pose_that_stopped_gives_no_speed() -> void:
	for _tick in 4:
		_animate(TICK)
		_pose.sample(_skeleton)
	for _tick in Engine.max_physics_steps_per_frame + 1:
		_pose.sample(_skeleton)
	assert_bool(_pose.is_still()).is_true()
	assert_float(_speed()).is_equal(0.0)


func test_a_jump_of_the_pose_is_no_speed() -> void:
	_animate(TICK)
	_pose.sample(_skeleton)
	_skeleton.set_bone_pose_position(_hand, Vector3(5.0, 0.0, 0.0))
	_pose.sample(_skeleton)
	assert_float(_speed()).is_equal(-1.0)

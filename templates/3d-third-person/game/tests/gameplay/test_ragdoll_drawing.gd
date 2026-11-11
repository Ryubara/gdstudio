# A ragdoll is drawn between physics ticks like everything else on screen (`RagdollDrawing`,
# gdstudio #1126). The physics runs at 25 ticks a second under the suite's 60 frames, 2.4 frames a
# tick as 144 frames a second give over 60 ticks, so most frames fall between two ticks. The body
# is pushed along by the map's moving block (`PathingSection/Obstacles/MoverA`) in the tree
# `main.tscn` builds, the way the report found it.
extends GdUnitTestSuite

## The ticks a second under the suite's 60 frames: 2.4 frames a tick.
const TICKS := 25
## How far the skin may be drawn from its body (metres): rounding only.
const DRAWN_SLACK := 0.002

var _ticks_before := 60
var _scene: Node
var _player: Player
var _ragdoll: CharacterRagdoll
var _mover: MovingPlatform


func before_test() -> void:
	InputSim.release_all()
	_ticks_before = Engine.physics_ticks_per_second
	# After the scene runner, which sets the project's rate when it is made.
	_scene = scene_runner("res://main.tscn").scene()
	Engine.physics_ticks_per_second = TICKS
	_player = _scene.get_node("PlayerRig/Player")
	_ragdoll = _player.ragdoll_body
	_mover = _scene.get_node("World/PathingSection/Obstacles/MoverA")
	await InputSim.ticks(get_tree(), 8)


func after_test() -> void:
	Engine.physics_ticks_per_second = _ticks_before
	InputSim.release_all()
	AudioDrain.stop_all(_scene)


# Kills the player in front of the moving block as it waits at its start, waits until the block
# has pushed the body a little, then records `ticks` ticks of drawn frames.
func _pushed_body(ticks: int) -> DrawnPoseProbe:
	var waited := 0
	while waited < 30 * TICKS and not _waiting_at_start():
		await InputSim.ticks(get_tree(), 1)
		waited += 1
	assert_bool(_waiting_at_start()).is_true()
	# In the block's path, a little ahead of it, facing across it.
	_player.teleport(_mover.global_position + Vector3(0.0, -1.0, 1.15), PI / 2.0)
	await InputSim.ticks(get_tree(), 5)
	_player.die()
	assert_bool(_ragdoll.is_limp()).is_true()
	var probe := DrawnPoseProbe.attach(_player.model.skeleton(), _ragdoll.body(&"pelvis"))
	waited = 0
	while waited < 10 * TICKS and _mover.progress() < 0.05:
		await InputSim.ticks(get_tree(), 1)
		waited += 1
	probe.clear()
	await InputSim.ticks(get_tree(), ticks)
	return probe


func _waiting_at_start() -> bool:
	return _mover.progress() < 0.01 and _mover.ride_at(_mover.placed_tick).wait > 0.5


# The largest distance between where the skin put the pelvis and where its body is drawn.
static func _largest_gap(probe: DrawnPoseProbe) -> float:
	var largest := 0.0
	for index in probe.drawn.size():
		largest = maxf(largest, probe.drawn[index].distance_to(probe.expected[index]))
	return largest


static func _between_ticks(probe: DrawnPoseProbe) -> int:
	var count := 0
	for fraction in probe.fractions:
		if fraction > 0.1 and fraction < 0.9:
			count += 1
	return count


func test_a_ragdoll_pushed_by_a_moving_block_is_drawn_between_ticks() -> void:
	var probe := await _pushed_body(60)
	var travel := probe.expected[0].distance_to(probe.expected[probe.expected.size() - 1])
	var gap := _largest_gap(probe)
	print(
		(
			"pushed ragdoll: %d frames, %d between ticks, %.2f m pushed, skin %.4f m from its body"
			% [probe.drawn.size(), _between_ticks(probe), travel, gap]
		)
	)
	# The body moves (pushed) and most frames fall between two ticks: a skin at the last tick
	# would be drawn up to most of a tick's travel (6 cm here) from its body.
	assert_float(travel).is_greater(1.0)
	assert_int(_between_ticks(probe)).is_greater(probe.fractions.size() / 2)
	assert_float(gap).is_less(DRAWN_SLACK)


func test_with_draw_between_ticks_off_the_skin_stands_at_the_last_tick() -> void:
	# The control: the same push with the drawing off draws the skin where the last tick left it.
	_ragdoll.draw_between_ticks = false
	var probe := await _pushed_body(30)
	assert_float(_largest_gap(probe)).is_greater(0.02)


func test_the_drawing_comes_after_the_bones_and_rests_while_they_sleep() -> void:
	_ragdoll.settle_time = 1.0
	_player.teleport(_player.global_position)
	await InputSim.ticks(get_tree(), 2)
	_player.die()
	var skeleton := _player.model.skeleton()
	var drawing := skeleton.get_node(NodePath(RagdollDrawing.NODE_NAME)) as RagdollDrawing
	var simulator := _ragdoll.simulator()
	assert_object(drawing).is_not_null()
	assert_int(drawing.get_index()).is_equal(simulator.get_index() + 1)
	assert_int(drawing.bodies.size()).is_equal(16)
	await InputSim.ticks(get_tree(), 2)
	assert_bool(drawing.active).is_true()
	var waited := 0
	while waited < 20 * TICKS and not _ragdoll.is_settled():
		await InputSim.ticks(get_tree(), 1)
		waited += 1
	assert_bool(_ragdoll.is_settled()).is_true()
	await InputSim.ticks(get_tree(), 2)
	# Asleep, every body is drawn where its tick left it: nothing to do.
	assert_bool(drawing.active).is_false()


func test_draw_between_ticks_applies_live() -> void:
	_player.die()
	var drawing := (
		_player.model.skeleton().get_node(NodePath(RagdollDrawing.NODE_NAME)) as RagdollDrawing
	)
	await InputSim.ticks(get_tree(), 2)
	assert_bool(drawing.active).is_true()
	_ragdoll.draw_between_ticks = false
	await InputSim.ticks(get_tree(), 1)
	assert_bool(drawing.active).is_false()
	_ragdoll.draw_between_ticks = true
	await InputSim.ticks(get_tree(), 1)
	assert_bool(drawing.active).is_true()

# The AI puppets of a client made over several frames (gdstudio #1208): a full snapshot of 120
# rows (a join, or a crowd walking into the interest radius) makes no more than the replica's
# budget of puppets in one frame, the nearest to the viewer first, shows no more than its budget
# for the first time in one frame, and every puppet then exists and stands at the server's place
# within a set number of frames. A row that comes for a puppet
# not made yet is kept, so it appears where the character is when its turn comes.
extends GdUnitTestSuite

const CROWD := 120
const BUDGET := 6
## Frames for every puppet to be made and placed: the frames the budget needs, and the replica's
## drawing delay (`interp_delay`, 0.1 s: six ticks) with a few to spare.
const SETTLE_FRAMES := CROWD / BUDGET + 12
const SERVER_TICK := 600
const ORIGIN := Vector3(5.0, 0.0, -3.0)

var _replica: AiReplica
var _viewer: Node3D
var _made_this_frame := 0


func before_test() -> void:
	var stage := auto_free(Node3D.new()) as Node3D
	add_child(stage)
	_viewer = Node3D.new()
	stage.add_child(_viewer)
	_viewer.global_position = ORIGIN + Vector3(30.0, 0.0, 30.0)
	_replica = AiReplica.new()
	_replica.section_origin = ORIGIN
	if &"puppets_per_frame" in _replica:
		_replica.set(&"puppets_per_frame", BUDGET)
		_replica.set(&"puppet_budget_usec", 0)
		_replica.set(&"puppets_shown_per_frame", BUDGET)
		_replica.set(&"viewer", _viewer)
	stage.add_child(_replica)
	_made_this_frame = 0
	_replica.puppet_added.connect(func(_id: int, _puppet: Character) -> void: _made_this_frame += 1)


func after_test() -> void:
	_replica = null
	_viewer = null


# 120 rows on a 12 x 10 grid, 2 m apart, metres from the section's origin.
func _full_tick(server_tick: int, seq: int) -> SnapshotCodec.Tick:
	var tick := SnapshotCodec.Tick.new()
	tick.server_tick = server_tick
	tick.ai.mode = AiSnapshot.Mode.FULL
	tick.ai.seq = seq
	for index in CROWD:
		var row := AiRow.new()
		row.id = index
		row.position = Vector3((index % 12) * 2.0, 0.0, (index / 12) * 2.0)
		row.yaw = 0.1 * index
		row.state = Character.State.IDLE
		tick.ai.rows.append(row)
	return tick


func _place_of(id: int) -> Vector3:
	return ORIGIN + Vector3((id % 12) * 2.0, 0.0, (id / 12) * 2.0)


func test_a_full_snapshot_of_120_makes_no_more_than_the_budget_a_frame() -> void:
	_replica.on_welcome(SERVER_TICK)
	_replica.on_tick(_full_tick(SERVER_TICK, 0))
	var most := _made_this_frame
	var frames := 0
	while frames < SETTLE_FRAMES and _replica.count() < CROWD:
		_made_this_frame = 0
		await get_tree().physics_frame
		most = maxi(most, _made_this_frame)
		frames += 1
	print("ai replica: %d puppets in %d frames, at most %d a frame" % [CROWD, frames, most])
	assert_int(most).is_less_equal(BUDGET)
	assert_int(_replica.count()).is_equal(CROWD)
	# Every puppet then stands where the server had it, shown a budget a frame once its row is due.
	for _frame in SETTLE_FRAMES:
		await get_tree().physics_frame
	assert_int(_replica.most_shown).is_equal(BUDGET)
	for id in _replica.ids():
		var puppet := _replica.puppet_of(id)
		assert_bool(puppet.visible).override_failure_message("Ai%d not drawn" % id).is_true()
		assert_vector(puppet.global_position).is_equal_approx(_place_of(id), Vector3.ONE * 0.001)


func test_the_puppets_nearest_the_viewer_are_made_first() -> void:
	_replica.on_welcome(SERVER_TICK)
	_replica.on_tick(_full_tick(SERVER_TICK, 0))
	# `physics_frame` is said before the nodes' steps: the second resumes after one step.
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_int(_replica.most_made).is_equal(BUDGET)
	# The viewer stands past the grid's far corner (id 119, at 22 x 18 m): the budget's nearest.
	var by_distance: Array[int] = []
	for id in CROWD:
		by_distance.append(id)
	var at := _viewer.global_position
	by_distance.sort_custom(
		func(a: int, b: int) -> bool:
			return _place_of(a).distance_squared_to(at) < _place_of(b).distance_squared_to(at)
	)
	var nearest := by_distance.slice(0, BUDGET)
	nearest.sort()
	assert_array(_replica.ids()).is_equal(nearest)


func test_a_row_for_a_puppet_not_made_yet_places_it_where_the_character_is_now() -> void:
	_replica.on_welcome(SERVER_TICK)
	_replica.on_tick(_full_tick(SERVER_TICK, 0))
	# Before the far corner's turn, the server moves every character 3 m east in a new full block.
	var moved := _full_tick(SERVER_TICK + 2, 1)
	for row in moved.ai.rows:
		row.position.x += 3.0
	await get_tree().physics_frame
	_replica.on_tick(moved)
	assert_int(_replica.count()).is_less(CROWD)
	for _frame in SETTLE_FRAMES + 12:
		await get_tree().physics_frame
	assert_int(_replica.count()).is_equal(CROWD)
	for id in _replica.ids():
		var puppet := _replica.puppet_of(id)
		assert_vector(puppet.global_position).is_equal_approx(
			_place_of(id) + Vector3(3.0, 0.0, 0.0), Vector3.ONE * 0.001
		)


func test_a_character_that_leaves_before_its_turn_is_never_made() -> void:
	_replica.on_welcome(SERVER_TICK)
	_replica.on_tick(_full_tick(SERVER_TICK, 0))
	# A full block with only the first ten: the rest left this client's interest.
	var fewer := _full_tick(SERVER_TICK + 2, 1)
	fewer.ai.rows.resize(10)
	_replica.on_tick(fewer)
	for _frame in SETTLE_FRAMES:
		await get_tree().physics_frame
	var first: Array[int] = []
	for id in 10:
		first.append(id)
	assert_array(_replica.ids()).is_equal(first)

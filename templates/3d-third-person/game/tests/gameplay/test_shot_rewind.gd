# On the clock: one case times the history and a shot, in microseconds.
# The parts of the lag compensation for shots on the AI (gdstudio #1198), without a network: the
# history keeps each character's capsule by tick and holds a tick to the ones it kept, a command's
# 16-bit tick is made whole across the wrap, a ray meets a capsule where geometry says, a shot
# meets the character where it was at the shot's tick and is moved to where it is now, and the
# history and a shot cost a few microseconds per character with 120 of them.
extends GdUnitTestSuite

## Microseconds a character may cost the history a record (every second tick), and a shot's
## meet per character near it,
## on a busy machine (the measured numbers are printed and go on the AI page).
const RECORD_BUDGET_US := 4.0
const MEET_BUDGET_US := 6.0

var _world: Node3D


func before_test() -> void:
	_world = auto_free(Node3D.new())
	add_child(_world)


func test_the_history_keeps_each_tick_and_holds_one_it_did_not_keep() -> void:
	var guard := _guard(Vector3.ZERO)
	var history := AiHitHistory.new(4)
	var characters: Dictionary[int, AiCharacter] = {7: guard}
	for tick in range(10, 16):
		guard.global_position = Vector3(tick, 0.0, 0.0)
		history.record(tick, characters)
	assert_int(history.newest()).is_equal(15)
	assert_int(history.oldest()).is_equal(12)
	assert_vector(history.position_at(7, 13)).is_equal(Vector3(13, 0, 0))
	# Older than kept: the oldest kept; newer: the newest.
	assert_vector(history.position_at(7, 2)).is_equal(Vector3(12, 0, 0))
	assert_vector(history.position_at(7, 40)).is_equal(Vector3(15, 0, 0))
	assert_float(history.size_at(7, 14).x).is_equal_approx(guard.tuning.radius, 0.001)
	assert_float(history.size_at(7, 14).y).is_greater(1.0)
	assert_vector(history.position_at(8, 14)).is_equal(Vector3.INF)
	# Gone from the map's ids: forgotten.
	characters.erase(7)
	history.record(16, characters)
	assert_bool(history.has(7, 15)).is_false()


func test_a_history_recorded_every_second_tick_draws_the_line_between() -> void:
	var guard := _guard(Vector3.ZERO)
	var history := AiHitHistory.new(8, 2)
	var characters: Dictionary[int, AiCharacter] = {0: guard}
	for tick in range(10, 22, 2):
		guard.global_position = Vector3(tick * 0.1, 0.0, 0.0)
		history.record(tick, characters)
	var near := Vector3.ONE * 0.00001
	assert_int(history.oldest()).is_equal(13)
	assert_vector(history.position_at(0, 16)).is_equal_approx(Vector3(1.6, 0, 0), near)
	assert_vector(history.position_at(0, 17)).is_equal_approx(Vector3(1.7, 0, 0), near)
	assert_vector(history.position_at(0, 13)).is_equal_approx(Vector3(1.3, 0, 0), near)
	assert_vector(history.position_at(0, 25)).is_equal_approx(Vector3(2.0, 0, 0), near)


func test_a_character_that_came_late_is_held_to_its_first_tick() -> void:
	var guard := _guard(Vector3(1, 0, 0))
	var history := AiHitHistory.new(30)
	var characters: Dictionary[int, AiCharacter] = {3: guard}
	history.record(100, characters)
	guard.global_position = Vector3(2, 0, 0)
	history.record(101, characters)
	assert_bool(history.has(3, 99)).is_false()
	assert_vector(history.position_at(3, 90)).is_equal(Vector3(1, 0, 0))


func test_a_dead_character_has_no_volume() -> void:
	var guard := _guard(Vector3.ZERO)
	var history := AiHitHistory.new(8)
	var characters: Dictionary[int, AiCharacter] = {1: guard}
	history.record(1, characters)
	guard.die()
	history.record(2, characters)
	assert_float(history.size_at(1, 1).y).is_greater(0.0)
	assert_float(history.size_at(1, 2).y).is_equal(0.0)


func test_a_commands_tick_is_made_whole_across_the_wrap() -> void:
	assert_int(ShotRewind.whole_tick(1000 & 0xFFFF, 1024)).is_equal(1000)
	assert_int(ShotRewind.whole_tick(0xFFF0, 0x10010)).is_equal(0xFFF0)
	assert_int(ShotRewind.whole_tick(0x0005, 0x1FFFE)).is_equal(0x20005)
	assert_int(ShotRewind.whole_tick(70000 & 0xFFFF, 70030)).is_equal(70000)


func test_a_ray_meets_a_capsule_where_geometry_says() -> void:
	var low := Vector3(0, 0.3, 0)
	var high := Vector3(0, 1.5, 0)
	# Square on the side: radius 0.3 at 5 m.
	var side := ShotRewind.ray_capsule(Vector3(0, 1, 5), Vector3.FORWARD, low, high, 0.3)
	assert_float(side).is_equal_approx(4.7, 0.0001)
	# Down onto the top: the sphere at the top of the axis.
	var top := ShotRewind.ray_capsule(Vector3(0, 5, 0), Vector3.DOWN, low, high, 0.3)
	assert_float(top).is_equal_approx(3.2, 0.0001)
	# Beside it, and away from it.
	(
		assert_float(ShotRewind.ray_capsule(Vector3(1, 1, 5), Vector3.FORWARD, low, high, 0.3))
		. is_equal(-1.0)
	)
	assert_float(ShotRewind.ray_capsule(Vector3(0, 1, 5), Vector3.BACK, low, high, 0.3)).is_equal(
		-1.0
	)
	# From inside: at once.
	(
		assert_float(ShotRewind.ray_capsule(Vector3(0, 1, 0), Vector3.FORWARD, low, high, 0.3))
		. is_equal(0.0)
	)


func test_a_shot_meets_the_character_where_it_was_drawn_and_hits_where_it_is() -> void:
	var guard := _guard(Vector3.ZERO)
	var history := AiHitHistory.new(30)
	var characters: Dictionary[int, AiCharacter] = {0: guard}
	# It ran along +X, 5 cm a tick, from x = 0 at tick 100 to x = 1 at tick 120.
	for tick in range(100, 121):
		guard.global_position = Vector3((tick - 100) * 0.05, 0.0, 0.0)
		history.record(tick, characters)
	var rewind := ShotRewind.new()
	rewind.history = history
	rewind.view_tick = 104
	# A shot from 5 m south at where it was at tick 102 (x = 0.1): a hit, moved to where it is (x = 1).
	rewind.behind = func(_body: AiCharacter) -> int: return 2
	var shot := rewind.for_shot(Vector3(0.1, 1.2, 5.0), Vector3.FORWARD, 20.0)
	assert_int(shot.tick_of(guard)).is_equal(102)
	assert_array(shot.excluded()).has_size(1)
	var met := shot.meet(Vector3(0.1, 1.2, 5.0), Vector3(0.1, 1.2, -5.0))
	assert_bool(met.is_empty()).is_false()
	assert_object(met["collider"]).is_same(guard)
	assert_vector(met["position"] as Vector3).is_equal_approx(
		Vector3(1.0, 1.2, guard.tuning.radius), Vector3.ONE * 0.001
	)
	# The same shot where it is now (x = 1) passes behind it as drawn.
	var now := shot.meet(Vector3(1.0, 1.2, 5.0), Vector3(1.0, 1.2, -5.0))
	assert_bool(now.is_empty()).is_true()
	# A projectile 10 ticks on meets it 10 ticks on (x = 0.6 at tick 112).
	var later := shot.meet(Vector3(0.6, 1.2, 5.0), Vector3(0.6, 1.2, -5.0), 10)
	assert_bool(later.is_empty()).is_false()
	# A wall nearer than the character wins.
	var wall := {"position": Vector3(0.1, 1.2, 2.0), "normal": Vector3.BACK, "collider": null}
	var start := Vector3(0.1, 1.2, 5.0)
	assert_dict(shot.nearer(start, Vector3(0.1, 1.2, -5.0), wall)).is_equal(wall)
	# A view older than the history is held to the oldest tick kept, never further.
	rewind.view_tick = 3
	var old_shot := rewind.for_shot(start, Vector3.FORWARD, 20.0)
	assert_vector(history.position_at(0, old_shot.tick_of(guard))).is_equal(
		history.position_at(0, history.oldest())
	)


func test_with_120_characters_the_history_and_a_shot_cost_microseconds() -> void:
	var characters: Dictionary[int, AiCharacter] = {}
	for index in 120:
		characters[index] = _guard(Vector3((index % 12) * 1.5, 0.0, -(index / 12) * 1.5))
	# Recorded with the TICK's rows, every second step, as the server does.
	var history := AiHitHistory.new(36, 2)
	for tick in range(0, 20, 2):
		history.record(tick, characters)
	var spent := 0
	for tick in range(20, 260, 2):
		for id in characters:
			characters[id].global_position += Vector3(0.1, 0.0, 0.0)
		history.record(tick, characters)
		spent += history.last_record_us
	# Per character per record; a step pays half of it on average.
	var record_us := spent / 120.0 / 120.0
	var rewind := ShotRewind.new()
	rewind.history = history
	rewind.view_tick = 120
	# Down the middle of the crowd (12 m on from where it stood): a third of it near the path.
	var start := Vector3(20.0, 1.2, 4.0)
	var heading := Vector3(0.0, 0.0, -1.0)
	var began := Time.get_ticks_usec()
	var shot := rewind.for_shot(start, heading, 30.0)
	var pick_us := Time.get_ticks_usec() - began
	var near := shot.bodies().size()
	began = Time.get_ticks_usec()
	for age in 30:
		shot.meet(start + heading * age * 0.75, start + heading * (age + 1) * 0.75, age, 0.07)
	var meet_us := (Time.get_ticks_usec() - began) / 30.0
	prints(
		(
			"rewind cost: record %.2f us per character (%.0f us for 120, every second step),"
			% [record_us, record_us * 120.0]
		),
		"pick %d us," % pick_us,
		(
			"a projectile tick's meet %.0f us for %d near (%.2f us each)"
			% [meet_us, near, meet_us / near]
		)
	)
	assert_int(near).is_greater(30)
	assert_float(record_us).is_less(RECORD_BUDGET_US)
	assert_float(meet_us / near).is_less(MEET_BUDGET_US)


func _guard(spot: Vector3) -> AiCharacter:
	var guard := AiNetStage.walker(spot)
	_world.add_child(guard)
	guard.set_physics_process(false)
	guard.global_position = spot
	return guard

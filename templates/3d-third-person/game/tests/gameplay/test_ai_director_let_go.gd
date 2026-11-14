# The `AiDirector` lets characters go in the middle of its tick (kit #1406): a think or a step can
# end in a despawn (the spawner takes a body out of the tree for its pool), a free, or a death the
# spawner answers at once with a release, several in one tick. The loop never reads an entry past
# the end of its list, skips one let go before its turn, and steps every survivor that tick and
# every tick after. The AI soak broke its error gate on this (an out-of-bounds index into the
# director's entries at 96 s of seed 21).
extends GdUnitTestSuite

var _arena: AiArena
# Characters a test took out of the tree, freed after it.
var _taken_out: Array[AiCharacter] = []


func before_test() -> void:
	_arena = auto_free(AiArena.new())
	add_child(_arena)


func after_test() -> void:
	AudioDrain.stop_all(_arena)
	for character in _taken_out:
		if is_instance_valid(character):
			character.free()
	_taken_out.clear()


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


# Takes `character` out of the tree, as the spawner does for its pool.
func _take_out(character: AiCharacter) -> void:
	_arena.remove_child(character)
	_taken_out.append(character)


# Lets `others` go, the way `removal` does it, once, in the think of the first of `made` the
# director's loop visits on its tick, so every one let go is still ahead of it in that tick.
# Returns the tick it happened on (in [0], -1 until then).
func _let_go_in_a_think(made: Array[AiCharacter], others: Array, removal: Callable) -> Array:
	var happened := [-1]
	for character in made:
		character.thought.connect(
			func(_seconds: float) -> void:
				if happened[0] >= 0 or others.has(character):
					return
				# The loop starts at the entry `tick % size` (the characters registered in order).
				if posmod(made.find(character) - _arena.director.tick, made.size()) != 0:
					return
				happened[0] = _arena.director.tick
				# Written again only at the end of the tick: a loop that stops on an error leaves it.
				_arena.director.last_step_usec = -1
				for other: AiCharacter in others:
					removal.call(other)
		)
	return happened


# Walks the survivors so each is stepped every tick, lets the others go in one think the way
# `removal` does, and checks the director's tick ran to its end, the count is the survivors' and
# every tick after steps each survivor once.
func _check_let_go_mid_tick(removal: Callable, survivors_wanted := 2) -> void:
	# Seven, so the loop's start (one further each tick) and a 6-tick think meet at every entry.
	var made: Array[AiCharacter] = []
	for index in 7:
		made.append(_arena.add_character(Vector3(index * 1.5 - 4.0, 0.0, -3.0)))
	var director := _arena.add_director()
	await _ticks(12)
	var survivors := made.slice(0, survivors_wanted)
	var others := made.slice(survivors_wanted)
	for character in survivors:
		character.ai_controller().walk_direction = Vector3.FORWARD
		character.ai_controller().walk_strength = 0.5
	await _ticks(3)
	var happened := _let_go_in_a_think(made, others, removal)
	for _i in 60:
		await get_tree().physics_frame
		if happened[0] >= 0:
			break
	assert_int(happened[0]).override_failure_message("no survivor thought first").is_greater(0)
	# The tick of the removal ran to its end (its time is written last).
	assert_int(director.tick).is_equal(happened[0])
	assert_int(director.last_step_usec).is_not_negative()
	assert_int(director.count()).is_equal(survivors_wanted)
	var steps := director.body_steps
	await _ticks(20)
	assert_int(director.body_steps - steps).is_equal(20 * survivors_wanted)
	for character in survivors:
		assert_object(character.director).is_same(director)


func test_characters_taken_out_in_a_think_are_never_read_past_the_list() -> void:
	await _check_let_go_mid_tick(func(other: AiCharacter) -> void: _take_out(other))


# Past `max_corpses` the spawner sends a body to the pool from its `died` signal, inside the think
# or step of whoever shot it.
func test_characters_released_on_death_in_a_think_are_never_read_past_the_list() -> void:
	var release := func(other: AiCharacter) -> void:
		other.died.connect(func() -> void: _take_out(other), CONNECT_ONE_SHOT)
		other.die()
	await _check_let_go_mid_tick(release)


# Several in one tick down to the last survivor, in mixed ways: a free (the body gone at once,
# before its turn) and a despawn.
func test_all_but_one_let_go_in_one_think_in_mixed_ways() -> void:
	var count := [0]
	var mixed := func(other: AiCharacter) -> void:
		count[0] += 1
		if count[0] % 2 == 0:
			other.free()
		else:
			_take_out(other)
	await _check_let_go_mid_tick(mixed, 1)

# `AiSpawner` keeps its characters alive from a pool (kit #969): they are made once when the
# level loads and never again, a death is answered by a spawn after `respawn_delay`, a body lies
# until its ragdoll settles (or `corpse_seconds`) with at most `max_corpses` at once, `cap` and
# `enabled` stop it, `wake_range` waits for a player, a client of a remote server spawns nothing,
# and a character spawned again from the pool starts as a new one (its mind, its health, its
# weapon, its place in the director).
extends GdUnitTestSuite

const GRUNT := "res://gameplay/ai/characters/enemy_grunt.tscn"
const ALLY := "res://gameplay/ai/characters/ally.tscn"
const TICKS := 60

var _arena: BehaviourArena
var _director: AiDirector


func before_test() -> void:
	_arena = auto_free(BehaviourArena.new())
	add_child(_arena)
	_arena.build()
	await _arena.settle()
	_director = _arena.add_director()


# The parked characters are out of the tree, so the orphan count would name them before the
# arena (and with it each spawner, which frees them) goes.
func after_test() -> void:
	AudioDrain.stop_all(_arena)
	for spawner: AiSpawner in _arena.find_children("*", "AiSpawner", false, false):
		spawner.pool().clear()


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _marker(spot: Vector3, heading := 0.0) -> Marker3D:
	var marker := Marker3D.new()
	marker.position = spot
	marker.rotation.y = heading
	_arena.add_child(marker)
	return marker


# A spawner of `scene` set up with `changes` before it enters the tree.
func _spawner(scene := GRUNT, changes := {}) -> AiSpawner:
	var spawner := AiSpawner.new()
	spawner.scene = load(scene)
	spawner.count = 2
	spawner.respawn_delay = 1.0
	spawner.markers = [_marker(Vector3(-4, 0, 0)), _marker(Vector3(4, 0, 0), PI)]
	for key: String in changes:
		spawner.set(key, changes[key])
	_arena.add_child(spawner)
	return spawner


func test_the_spawner_defaults_are_pinned() -> void:
	var spawner: AiSpawner = auto_free(AiSpawner.new())
	var pins := {
		&"scene": null,
		&"count": 3,
		&"markers": [],
		&"respawn_delay": 10.0,
		&"cap": 0,
		&"enabled": true,
		&"wake_range": 0.0,
		&"player_group": &"player",
		&"patrol_route": &"",
		&"leader_group": &"",
		&"debug": false,
		&"max_corpses": 4,
		&"corpse_seconds": 20.0,
		&"settled_linger": 2.0,
		&"on_server": false,
	}
	assert_array(ExportPins.differences(spawner, pins)).is_empty()
	assert_array(ExportPins.wrong_values(spawner, pins)).is_empty()


func test_it_spawns_its_count_at_the_markers_facing_their_way() -> void:
	var spawner := _spawner()
	await _ticks(2)
	assert_int(spawner.alive.size()).is_equal(2)
	var at := [spawner.alive[0].global_position, spawner.alive[1].global_position]
	assert_vector(at[0]).is_equal_approx(Vector3(-4, 0, 0), Vector3.ONE * 0.05)
	assert_vector(at[1]).is_equal_approx(Vector3(4, 0, 0), Vector3.ONE * 0.05)
	# A marker's -Z is the way: the first looks along -Z (heading PI), the second along +Z.
	assert_float(absf(wrapf(spawner.alive[0].facing - PI, -PI, PI))).is_less(0.05)
	assert_float(absf(wrapf(spawner.alive[1].facing, -PI, PI))).is_less(0.05)
	assert_int(_director.count()).is_equal(2)


func test_the_pool_makes_every_character_when_the_level_loads_and_never_again() -> void:
	var spawner := _spawner(GRUNT, {"max_corpses": 1, "respawn_delay": 0.5, "corpse_seconds": 1.0})
	await _ticks(2)
	var made := spawner.pool().made
	assert_int(made).is_equal(3)
	for _round in 4:
		spawner.alive[0].die()
		await _ticks(TICKS * 2)
	assert_int(spawner.spawned_total).is_equal(6)
	assert_int(spawner.pool().made).is_equal(made)


func test_a_death_is_answered_by_a_spawn_after_the_delay() -> void:
	var spawner := _spawner(GRUNT, {"respawn_delay": 2.0})
	await _ticks(2)
	spawner.alive[0].die()
	await _ticks(2)
	assert_int(spawner.alive.size()).is_equal(1)
	assert_int(spawner.corpses.size()).is_equal(1)
	await _ticks(TICKS * 2 - 10)
	assert_int(spawner.alive.size()).is_equal(1)
	await _ticks(20)
	assert_int(spawner.alive.size()).is_equal(2)


func test_no_respawn_below_zero_and_none_past_the_cap() -> void:
	var never := _spawner(GRUNT, {"respawn_delay": -1.0})
	await _ticks(2)
	never.alive[0].die()
	await _ticks(TICKS * 2)
	assert_int(never.alive.size()).is_equal(1)
	var capped := _spawner(ALLY, {"cap": 3, "respawn_delay": 0.2, "count": 2})
	await _ticks(2)
	capped.alive[0].die()
	await _ticks(TICKS)
	capped.alive[0].die()
	await _ticks(TICKS)
	assert_int(capped.spawned_total).is_equal(3)
	assert_int(capped.alive.size()).is_equal(1)


func test_a_body_lies_until_it_settles_and_goes_back_to_the_pool() -> void:
	var spawner := _spawner(GRUNT, {"respawn_delay": -1.0, "corpse_seconds": 60.0})
	await _ticks(2)
	var body := spawner.alive[0]
	body.die()
	await _ticks(TICKS)
	assert_bool(spawner.corpses.has(body)).is_true()
	assert_bool(body.is_inside_tree()).is_true()
	# The ragdoll settles after its `settle_time`, then the body lies on `settled_linger`.
	var waited := 0
	while spawner.corpses.has(body) and waited < TICKS * 20:
		await _ticks(10)
		waited += 10
	assert_bool(spawner.corpses.has(body)).is_false()
	assert_bool(body.is_inside_tree()).is_false()
	assert_int(spawner.pool().parked()).is_greater_equal(1)
	assert_int(_director.count()).is_equal(1)


func test_at_most_max_corpses_lie_and_the_oldest_goes_first() -> void:
	var spawner := _spawner(GRUNT, {"count": 3, "max_corpses": 1, "respawn_delay": -1.0})
	spawner.markers.append(_marker(Vector3(0, 0, 4)))
	spawner.enabled = true
	await _ticks(2)
	var first := spawner.alive[0]
	var second := spawner.alive[1]
	first.die()
	await _ticks(5)
	second.die()
	await _ticks(5)
	assert_array(spawner.corpses).contains_exactly([second])
	assert_bool(first.is_inside_tree()).is_false()


func test_a_body_that_never_settles_goes_after_corpse_seconds() -> void:
	var spawner := _spawner(GRUNT, {"respawn_delay": -1.0, "corpse_seconds": 1.0})
	await _ticks(2)
	var body := spawner.alive[0]
	body.die()
	await _ticks(TICKS + 10)
	assert_bool(spawner.corpses.has(body)).is_false()


func test_a_character_spawned_again_starts_as_a_new_one() -> void:
	# No body left lying: the pool holds the one character, which comes back.
	var spawner := _spawner(
		GRUNT, {"count": 1, "respawn_delay": 0.2, "max_corpses": 0, "patrol_route": &"lane"}
	)
	var target := _arena.add_target("Intruder", Vector3(-4, 0, -6))
	await _ticks(TICKS * 2)
	var first := spawner.alive[0]
	var mind := first.brain as AiBrain
	assert_bool((first.senses as AiSenses).beliefs.knows(target)).is_true()
	first.weapon.set_ammo(1, 0)
	first.die()
	await _ticks(TICKS * 2)
	assert_int(spawner.alive.size()).is_equal(1)
	var again := spawner.alive[0]
	assert_object(again).is_same(first)
	assert_bool(again.is_dead()).is_false()
	assert_float(again.health).is_equal(again.max_health)
	assert_int(int(again.weapon.ammo)).is_equal(again.weapon.definition.magazine_size)
	assert_str(String(mind.patrol_route)).is_equal("lane")
	assert_object(again.director).is_same(_director)
	var thinks := again.think_count
	await _ticks(30)
	assert_int(again.think_count).is_greater(thinks)
	assert_str(String(mind.last_event)).is_not_equal("")


func test_an_ally_follows_the_first_of_its_leader_group() -> void:
	var leader := _arena.add_target("Leader", Vector3(0, 0, 8), &"player", &"leaders")
	var spawner := _spawner(ALLY, {"count": 1, "leader_group": &"leaders"})
	await _ticks(2)
	assert_object((spawner.alive[0].brain as AiBrain).leader).is_same(leader)


func test_off_it_spawns_nothing_more_and_on_again_it_fills_up() -> void:
	var spawner := _spawner(GRUNT, {"enabled": false})
	await _ticks(10)
	assert_int(spawner.alive.size()).is_equal(0)
	spawner.enabled = true
	await _ticks(2)
	assert_int(spawner.alive.size()).is_equal(2)


func test_it_waits_for_a_player_within_wake_range_and_makes_its_pool_on_the_way() -> void:
	# The arena's stand-in for the player's body starts far away.
	var player := _arena.viewer
	player.position = Vector3(0, 0, 60)
	var spawner := _spawner(GRUNT, {"wake_range": 10.0})
	await _ticks(40)
	assert_bool(spawner.awake).is_false()
	assert_int(spawner.pool().made).is_equal(0)
	# Within the margin: the characters are made, one a tick, before anyone spawns.
	player.position = Vector3(0, 0, 10.0 + AiSpawner.PREWARM_MARGIN - 2.0)
	await _ticks(40)
	assert_bool(spawner.awake).is_false()
	assert_int(spawner.pool().parked()).is_equal(spawner.count + spawner.max_corpses)
	var made := spawner.pool().made
	player.position = Vector3(0, 0, 6)
	await _ticks(40)
	assert_bool(spawner.awake).is_true()
	assert_int(spawner.alive.size()).is_equal(2)
	assert_int(spawner.pool().made).is_equal(made)


func test_freeing_the_spawner_frees_the_characters_it_parked() -> void:
	var spawner := _spawner(GRUNT, {"enabled": false})
	await _ticks(2)
	var parked: Array[WeakRef] = []
	for _i in spawner.pool().parked():
		var character := spawner.pool().take()
		parked.append(weakref(character))
		spawner.pool().park(character)
	assert_int(parked.size()).is_equal(spawner.count + spawner.max_corpses)
	spawner.free()
	for ref in parked:
		assert_object(ref.get_ref()).is_null()


func test_a_client_of_a_remote_server_spawns_nothing_and_a_server_only_when_asked() -> void:
	var tree := get_tree()
	assert_bool(AiSpawner.spawns_here(tree)).is_true()
	(
		assert_bool(
			AiSpawner.spawns_here(
				tree, true, NetArgs.new(PackedStringArray(["--connect", "ws://x"]))
			)
		)
		. is_false()
	)
	(
		assert_bool(
			AiSpawner.spawns_here(tree, false, NetArgs.new(PackedStringArray(["--server"])))
		)
		. is_false()
	)
	(
		assert_bool(AiSpawner.spawns_here(tree, true, NetArgs.new(PackedStringArray(["--server"]))))
		. is_true()
	)


func test_a_map_that_handed_its_ai_to_a_server_stops_spawning() -> void:
	var spawner := _spawner(GRUNT, {"respawn_delay": 0.5})
	await _ticks(2)
	assert_int(spawner.alive.size()).is_equal(2)
	AiAuthority.hand_over(_arena)
	await _ticks(TICKS)
	assert_int(get_tree().get_nodes_in_group(AiCharacter.GROUP).size()).is_equal(0)
	assert_int(spawner.spawned_total).is_equal(2)
	assert_bool(spawner.is_physics_processing()).is_false()
	assert_int(spawner.pool().parked()).is_equal(0)

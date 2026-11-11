# The AI section's population online (gdstudio #1234): a game server and a client, each with a map
# of its own (`OnlineRig`). The client's spawners spawn nothing (its map handed its AI to the
# server); the server's wake when a player's body on the server comes within `wake_range`, spawn the
# whole population (3 grunts, 2 shooters, 2 allies, 3 civilians), lead the allies with that body,
# and the client draws every one of them in its own look: enemies in the male mannequin, friendlies
# in the female. A death, a body taken back to the pool and a respawn reach the client too.
extends GdUnitTestSuite

## The section's origin in the world (`world.tscn` puts it there).
const SECTION := Vector3(-25.0, 0.0, -9.0)
const POPULATION := "World/AISection/Population"
## Each spawner of the section and whether its kind is an enemy (the male mannequin).
const ENEMIES := {&"Grunts": true, &"Shooters": true, &"Allies": false, &"Civilians": false}
const MALE := "res://assets/characters/mannequin/mannequin_male.glb"
const FEMALE := "res://assets/characters/mannequin/mannequin_female.glb"

var _rig: OnlineRig
var _ada: NetClient


func after_test() -> void:
	_rig = null
	_ada = null


func test_the_section_runs_on_the_server_and_ada_draws_its_whole_population() -> void:
	await _start()
	var on_server := _spawners(_rig.server)
	var on_client := _spawners(_ada.get_parent())
	assert_int(on_server.size()).is_equal(ENEMIES.size())
	for spawner in on_server:
		assert_bool(spawner.on_server).override_failure_message(spawner.name).is_true()
	await _rig.wait(2 * AiSpawner.WAKE_CHECK_TICKS)
	# Ada's body is at a spawn point, 43 m from the spawners: nobody yet, and her client's map runs
	# no spawner at all.
	for spawner in on_server:
		assert_bool(spawner.awake).override_failure_message(spawner.name).is_false()
		assert_int(spawner.pool().made).is_equal(0)
	_assert_client_spawns_nothing(on_client)
	# Her body walks into the section (12 m from the spawners): the server's wake.
	_put(_ada, _at(-5.0, -1.0), -PI / 2.0)
	var full := func() -> bool:
		return on_server.all(
			func(spawner: AiSpawner) -> bool: return spawner.alive.size() == spawner.count
		)
	assert_bool(await _rig.until(full, 120)).is_true()
	var population := _alive(on_server)
	assert_int(population.size()).is_equal(10)
	# The allies follow the server's body of her player, not her client's player.
	for ally in _spawner_named(on_server, &"Allies").alive:
		assert_object((ally.brain as AiBrain).leader).is_same(_rig.server_body(_ada))
	# Her client draws every one, enemies male and friendlies female.
	var drawn := func() -> bool: return _ada.ai_replica.count() == population.size()
	assert_bool(await _rig.until(drawn, 120)).is_true()
	for spawner in on_server:
		for character in spawner.alive:
			var puppet := _ada.ai_replica.puppet_of(_id_of(character))
			assert_object(puppet).override_failure_message(character.name).is_not_null()
			var look := MALE if ENEMIES[spawner.name] else FEMALE
			assert_str(puppet.model.rig().scene_file_path).is_equal(look)
	_assert_client_spawns_nothing(on_client)
	assert_array(_ada.get_parent().find_children("*", "AiCharacter", true, false)).is_empty()
	_clear(on_server + on_client)


func test_a_death_a_body_taken_back_and_a_respawn_reach_the_client() -> void:
	await _start()
	var on_server := _spawners(_rig.server)
	var grunts := _spawner_named(on_server, &"Grunts")
	grunts.respawn_delay = 0.5
	_put(_ada, _at(-5.0, -1.0), -PI / 2.0)
	var full := func() -> bool: return grunts.alive.size() == grunts.count
	assert_bool(await _rig.until(full, 120)).is_true()
	var grunt := grunts.alive[0]
	# Its wire id comes with the TICK after it spawned.
	var held := func() -> bool: return _id_of(grunt) >= 0 and _puppet(_id_of(grunt)) != null
	assert_bool(await _rig.until(held, 120)).is_true()
	var id := _id_of(grunt)
	grunt.die()
	var fallen := func() -> bool: return _puppet(id) != null and _puppet(id).is_dead()
	assert_bool(await _rig.until(fallen, 60)).is_true()
	# The body goes back to the pool: out of the server's tree, so gone from her screen.
	grunts.release(grunt)
	assert_bool(await _rig.until(func() -> bool: return _puppet(id) == null, 60)).is_true()
	# Half a second on another (or the same one) spawns at a marker, alive on her screen.
	assert_bool(await _rig.until(full, 60)).is_true()
	var again := grunts.alive[-1]
	var drawn := func() -> bool:
		var puppet := _puppet(_id_of(again))
		return puppet != null and puppet.visible and not puppet.is_dead()
	assert_bool(await _rig.until(drawn, 120)).is_true()
	assert_str(_puppet(_id_of(again)).model.rig().scene_file_path).is_equal(MALE)
	_clear(on_server + _spawners(_ada.get_parent()))


# --- Helpers ---


func _start() -> void:
	_rig = auto_free(OnlineRig.new())
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_ada = await _rig.join("Ada", 600)
	assert_object(_ada).is_not_null()
	# The section fights her: a test of what is spawned and drawn, not of who wins.
	Health.of(_rig.server_body(_ada)).invulnerable = true
	for spawner in _spawners(_rig.server):
		spawner.spawned.connect(
			func(character: AiCharacter) -> void:
				if character.brain != null:
					Health.of(character).invulnerable = true
		)


func _assert_client_spawns_nothing(spawners: Array[AiSpawner]) -> void:
	assert_int(spawners.size()).is_equal(ENEMIES.size())
	for spawner in spawners:
		assert_bool(spawner.is_physics_processing()).is_false()
		assert_int(spawner.spawned_total).is_equal(0)
		assert_int(spawner.pool().parked()).is_equal(0)


func _spawners(map_owner: Node) -> Array[AiSpawner]:
	var found: Array[AiSpawner] = []
	for node in map_owner.get_node(POPULATION).get_children():
		if node is AiSpawner:
			found.append(node)
	return found


static func _spawner_named(spawners: Array[AiSpawner], spawner_name: StringName) -> AiSpawner:
	for spawner in spawners:
		if spawner.name == spawner_name:
			return spawner
	return null


static func _alive(spawners: Array[AiSpawner]) -> Array[AiCharacter]:
	var found: Array[AiCharacter] = []
	for spawner in spawners:
		found.append_array(spawner.alive)
	return found


# The parked characters are out of the tree: freed in the case, before GdUnit counts orphans.
static func _clear(spawners: Array[AiSpawner]) -> void:
	for spawner in spawners:
		spawner.enabled = false
		spawner.pool().clear()


func _puppet(id: int) -> Character:
	return _ada.ai_replica.puppet_of(id)


static func _id_of(character: AiCharacter) -> int:
	return int(character.get_meta(NetHits.AI_META, -1))


static func _at(x: float, z: float) -> Vector3:
	return SECTION + Vector3(x, 0.3, z)


func _put(client: NetClient, spot: Vector3, facing: float) -> void:
	_rig.server_body(client).teleport(spot, facing)
	client.player.teleport(spot, facing)

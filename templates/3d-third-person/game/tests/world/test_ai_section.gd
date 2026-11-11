# The AI section's population (kit #969) met by the real player body in `main.tscn`: a guard
# notices the player in front at once, at the side only when its look round turns that way, and
# never behind until it hears the player walk (a crouch is quiet); a shot is heard by the shooter
# and by the ally, and the ally and the civilians answer the same shot differently; killing an
# ally turns the allies against the player. Each scenario turns on only the spawners it needs.
extends GdUnitTestSuite

## The section's origin in the world (`world.tscn` puts it there).
const SECTION := Vector3(-25.0, 0.0, -9.0)
const TICKS := 60

var _runner: GdUnitSceneRunner
var _scene: Node
var _player: Player
var _rig: PlayerCamera
var _spawners: Dictionary[StringName, AiSpawner] = {}


func before_test() -> void:
	_runner = scene_runner("res://main.tscn")
	_scene = _runner.scene()
	_player = _scene.get_node("PlayerRig/Player")
	_rig = _scene.get_node("PlayerRig/PlayerCamera")
	Health.of(_player).invulnerable = true
	_spawners.clear()
	for spawner: AiSpawner in _scene.get_node("World/AISection/Population").get_children():
		spawner.enabled = false
		_spawners[spawner.name] = spawner
	await InputSim.ticks(get_tree(), 5)


func after_test() -> void:
	InputSim.release_all()
	for action: StringName in [&"move_right", &"crouch", &"fire", &"aim"]:
		Input.action_release(action)


# A point of the section in the world.
func _at(x: float, z: float) -> Vector3:
	return SECTION + Vector3(x, 0.0, z)


# Turns on the spawner `spawner_name` with `count` characters (and `changes`), now.
func _only(spawner_name: StringName, count: int, changes := {}) -> Array[AiCharacter]:
	var spawner := _spawners[spawner_name]
	spawner.count = count
	for key: String in changes:
		spawner.set(key, changes[key])
	spawner.awake = true
	spawner.enabled = true
	return spawner.alive


# The grunt spawner's settings for a guard that holds the open middle (the guard lane's third
# stop, facing the doorway), with room all round it.
func _in_the_open(changes := {}) -> Dictionary:
	# Typed: `set()` refuses a plain array for an `Array[Node3D]` export.
	var stops: Array[Node3D] = [_scene.get_node("World/AISection/AiMarkers/GuardLane/Stop3")]
	var settings := {"patrol_route": &"hold", "markers": stops}
	settings.merge(changes, true)
	return settings


# Physics ticks until `character` notices the player (its senses), at most `cap`; -1 if never.
func _ticks_to_notice(character: AiCharacter, cap: int) -> int:
	var senses := character.senses as AiSenses
	for tick in cap:
		var belief := senses.beliefs.of(_player)
		if belief != null and belief.believed:
			return tick
		await get_tree().physics_frame
	return -1


func test_a_guard_notices_the_player_in_front_at_once_at_the_side_later_and_behind_never() -> void:
	# The guard holds the open middle (a route with no stops), facing the doorway (+X); each case
	# meets a fresh one (the same body, spawned again from the pool).
	var spawner := _spawners[&"Grunts"]
	var guard := _only(&"Grunts", 1, _in_the_open({"respawn_delay": -1.0}))[0]
	var post := guard.global_position
	var heading := guard.facing
	var ahead := Vector3.BACK.rotated(Vector3.UP, heading)
	var side := ahead.rotated(Vector3.UP, PI / 2.0)
	var times := {}
	for case: String in ["behind", "side", "front"]:
		var spot: Vector3 = {
			"behind": post - ahead * 9.0, "side": post + side * 9.0, "front": post + ahead * 9.0
		}[case]
		_player.teleport(spot, heading)
		await InputSim.ticks(get_tree(), 2)
		times[case] = await _ticks_to_notice(guard, TICKS * 9)
		guard.die()
		spawner.release(guard)
		guard = spawner.spawn_one()
		await InputSim.ticks(get_tree(), 10)
	# Behind, standing still: nothing to see or hear for a look round and more.
	assert_int(times["behind"]).is_equal(-1)
	# In front: within the time to notice at 9 m (the rate falls with distance) and a reaction.
	assert_int(times["front"]).is_between(0, TICKS * 2)
	# At the side: only once the look round (60 degrees each way) brings the cone onto it.
	assert_int(times["side"]).is_greater(times["front"])
	assert_int(times["side"]).is_between(0, TICKS * 9)


func test_a_guard_hears_the_player_walk_behind_it_but_not_crouch() -> void:
	var guard := _only(&"Grunts", 1, _in_the_open())[0]
	var heard: Array[Vector3] = []
	(guard.senses as AiSenses).heard.connect(
		func(kind: StringName, at: Vector3, _source: Node3D) -> void:
			if kind == AiNoise.FOOTSTEP:
				heard.append(at)
	)
	await InputSim.ticks(get_tree(), 30)
	var ahead := Vector3.BACK.rotated(Vector3.UP, guard.facing)
	_player.teleport(guard.global_position - ahead * 6.0, guard.facing)
	await InputSim.ticks(get_tree(), 5)
	Input.action_press(&"crouch")
	await InputSim.ticks(get_tree(), 20)
	Input.action_press(&"move_right")
	await InputSim.ticks(get_tree(), 80)
	Input.action_release(&"move_right")
	assert_array(heard).is_empty()
	Input.action_release(&"crouch")
	await InputSim.ticks(get_tree(), 30)
	_player.teleport(guard.global_position - ahead * 6.0, guard.facing)
	Input.action_press(&"move_right")
	await InputSim.ticks(get_tree(), 80)
	Input.action_release(&"move_right")
	assert_array(heard).is_not_empty()
	# It turns to what it heard and finds the player.
	assert_int(await _ticks_to_notice(guard, TICKS * 6)).is_greater_equal(0)


func test_one_shot_is_heard_by_the_shooter_and_the_ally_and_only_the_civilians_run() -> void:
	# The player stands at the shed's door, out of the shooter's sight (the shed is between them),
	# with the civilians inside, and fires into the open.
	_player.teleport(_at(-12.5, 6.5), PI / 2.0)
	var shooter := _only(&"Shooters", 1)[0]
	var ally := _only(&"Allies", 1, {"leader_group": &"player"})[0]
	var civilians := _only(&"Civilians", 2)
	await InputSim.ticks(get_tree(), TICKS * 4)
	var heard := {}
	for character: AiCharacter in [shooter, ally] + civilians:
		(character.senses as AiSenses).heard.connect(
			func(kind: StringName, _where: Vector3, source: Node3D) -> void:
				if kind == AiNoise.SHOT and source == _player:
					heard[character] = true
		)
	assert_bool((shooter.senses as AiSenses).beliefs.knows(_player)).is_false()
	# A shot leaves once the arm is up: aim, then pull.
	var rounds: int = _player.weapon.ammo
	Input.action_press(&"aim")
	await InputSim.ticks(get_tree(), 20)
	Input.action_press(&"fire")
	await InputSim.ticks(get_tree(), 3)
	Input.action_release(&"fire")
	Input.action_release(&"aim")
	assert_int(int(_player.weapon.ammo)).is_equal(rounds - 1)
	await InputSim.ticks(get_tree(), TICKS)
	assert_bool(heard.has(shooter)).override_failure_message("the shooter did not hear").is_true()
	assert_bool(heard.has(ally)).override_failure_message("the ally did not hear").is_true()
	for civilian in civilians:
		assert_array(["flee", "cower"]).contains([String(BehaviourArena.active_of(civilian))])
		assert_int(civilian.situation.current).is_equal(AiSituation.Situation.FLEEING)
	assert_str(String(BehaviourArena.active_of(ally))).is_not_equal("flee")
	assert_int(ally.situation.current).is_not_equal(AiSituation.Situation.FLEEING)


func test_killing_an_ally_turns_the_allies_against_the_player() -> void:
	_player.teleport(_at(-6.0, 0.0), -PI / 2.0)
	var allies := _only(&"Allies", 2, {"leader_group": &"player"})
	await InputSim.ticks(get_tree(), TICKS * 4)
	var victim := allies[0]
	var other := allies[1]
	var factions := AiFactions.find(_player)
	var me := AiFactionMember.of(_player)
	assert_int(factions.band_of_members(AiFactionMember.of(other), me)).is_not_equal(
		AiRelations.Band.HOSTILE
	)
	var pilot := PlayerBot.new()
	pilot.player = _player
	pilot.camera_rig = _rig
	pilot.turn_speed = 20.0
	_scene.add_child(pilot)
	pilot.set_physics_process(false)
	var shots := 0
	Input.action_press(&"aim")
	for tick in TICKS * 12:
		if victim.is_dead():
			break
		var left := pilot.face(victim.global_position + Vector3.UP * PlayerBot.CHEST_HEIGHT)
		var pressed := tick % 20 < 2 and absf(left) < 0.5
		if pressed and not Input.is_action_pressed(&"fire"):
			shots += 1
		if pressed:
			Input.action_press(&"fire")
		else:
			Input.action_release(&"fire")
		await get_tree().physics_frame
	Input.action_release(&"fire")
	Input.action_release(&"aim")
	(
		assert_bool(victim.is_dead())
		. override_failure_message("the ally is still alive after %d shots" % shots)
		. is_true()
	)
	assert_int(factions.band_of_members(AiFactionMember.of(other), me)).is_equal(
		AiRelations.Band.HOSTILE
	)
	# The other ally turns on the player within a few thinks.
	var mind := other.brain as AiBrain
	var turned := false
	for _tick in TICKS * 5:
		if mind.choose_target() == _player:
			turned = true
			break
		await get_tree().physics_frame
	assert_bool(turned).is_true()
	pilot.queue_free()

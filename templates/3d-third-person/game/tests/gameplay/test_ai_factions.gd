# The level's relationships between entities: only a perceived act moves an attitude, once a
# faction, and not for a witness hostile to the victim; the level recovers on the physics clock; a
# personal grudge beats the faction; a friend's shot is refused at the hit zones; a player who
# keeps shooting an ally turns the allies Hostile until they calm down; a kill counts on top of the
# blow; the band rings colour by band toward the player; the world plays the shipped table.
extends GdUnitTestSuite

const RELATIONS := "res://gameplay/ai/relations/ai_relations.tres"
const ALLY := "res://gameplay/ai/profiles/ally.tres"
const CIVILIAN := "res://gameplay/ai/profiles/civilian.tres"

var _arena: AiArena


func before_test() -> void:
	_arena = auto_free(AiArena.new())
	add_child(_arena)


func after_test() -> void:
	AudioDrain.stop_all(_arena)


func _factions() -> AiFactions:
	var factions := AiFactions.new()
	factions.name = "AiFactions"
	factions.relations = load(RELATIONS) as AiRelations
	_arena.add_child(factions)
	return factions


# The arena's stand-in for the player's body, in faction `player`.
func _player_member() -> Node3D:
	var member := AiFactionMember.new()
	member.faction = &"player"
	_arena.viewer.add_child(member)
	return _arena.viewer


func _zones_of(character: Character) -> HitZones:
	return character.find_children("*", "HitZones", true, false)[0] as HitZones


func test_the_world_plays_the_shipped_table() -> void:
	var world := (load("res://world/world.tscn") as PackedScene).instantiate()
	var factions := world.get_node("AiFactions") as AiFactions
	assert_str(factions.relations.resource_path).is_equal(RELATIONS)
	world.free()


func test_an_act_nobody_perceived_changes_nothing() -> void:
	var relations := (load(RELATIONS) as AiRelations).copy()
	assert_bool(relations.add_attitude(&"civilian", &"player", -30.0, 0)).is_false()
	assert_float(relations.attitude(&"civilian", &"player")).is_equal(20.0)
	var factions := _factions()
	var player := _player_member()
	var civilian := _arena.add_character(Vector3(0.0, 0.0, -3.0), load(CIVILIAN) as AiProfile)
	factions.witness_source = func(_actor: Node, _victim: Node) -> Array: return []
	assert_int(factions.report(&"attack", player, civilian)).is_equal(0)
	assert_float(factions.relations.attitude(&"civilian", &"player")).is_equal(20.0)


func test_a_witnessed_act_moves_the_witness_faction_once() -> void:
	var factions := _factions()
	var player := _player_member()
	var victim := _arena.add_character(Vector3(0.0, 0.0, -3.0), load(CIVILIAN) as AiProfile)
	var onlookers: Array = [victim]
	for x in [-2.0, 2.0]:
		onlookers.append(_arena.add_character(Vector3(x, 0.0, -3.0), load(CIVILIAN) as AiProfile))
	onlookers.append(_arena.add_character(Vector3(0.0, 0.0, -6.0), load(ALLY) as AiProfile))
	assert_int(factions.report(&"attack", player, victim, onlookers)).is_equal(2)
	assert_float(factions.relations.attitude(&"civilian", &"player")).is_equal(-10.0)
	assert_float(factions.relations.attitude(&"ally", &"player")).is_equal(50.0)
	assert_float(factions.relations.attitude(&"enemy", &"player")).is_equal(-100.0)


func test_a_witness_hostile_to_the_victim_does_not_mind() -> void:
	var factions := _factions()
	var player := _player_member()
	var grunt := _arena.add_character(Vector3(0.0, 0.0, -3.0))
	var ally := _arena.add_character(Vector3(2.0, 0.0, -3.0), load(ALLY) as AiProfile)
	assert_int(factions.report(&"kill", player, grunt, [ally])).is_equal(0)
	assert_float(factions.relations.attitude(&"ally", &"player")).is_equal(80.0)


func test_the_level_recovers_with_the_physics_clock() -> void:
	var factions := _factions()
	factions.relations.recovery_per_minute = 600.0
	factions.relations.set_attitude(&"civilian", &"player", -40.0)
	for _i in 30:
		await get_tree().physics_frame
	assert_float(factions.relations.attitude(&"civilian", &"player")).is_greater(-40.0)


func test_a_personal_grudge_beats_the_faction() -> void:
	var factions := _factions()
	var player := _player_member()
	var ally := _arena.add_character(Vector3(0.0, 0.0, -3.0), load(ALLY) as AiProfile)
	var other := _arena.add_character(Vector3(2.0, 0.0, -3.0), load(ALLY) as AiProfile)
	assert_bool(factions.is_hostile_between(ally, player)).is_false()
	AiFactionMember.of(ally).grudge(player, -90.0)
	assert_bool(factions.is_hostile_between(ally, player)).is_true()
	assert_float(factions.attitude_between(ally, player)).is_equal(-90.0)
	assert_bool(factions.is_hostile_between(other, player)).is_false()
	assert_float(factions.relations.attitude(&"ally", &"player")).is_equal(80.0)
	AiFactionMember.of(ally).forgive(player)
	assert_bool(factions.is_hostile_between(ally, player)).is_false()


func test_a_friend_shot_is_refused_and_a_foe_shot_lands() -> void:
	_factions()
	var player := _player_member()
	var grunt := _arena.add_character(Vector3(0.0, 0.0, -3.0))
	var other := _arena.add_character(Vector3(2.0, 0.0, -3.0))
	var ally := _arena.add_character(Vector3(-2.0, 0.0, -3.0), load(ALLY) as AiProfile)
	await get_tree().physics_frame
	assert_bool(AiFactions.can_hurt(grunt, other)).is_false()
	assert_bool(AiFactions.can_hurt(ally, player)).is_false()
	assert_bool(AiFactions.can_hurt(grunt, ally)).is_true()
	assert_bool(AiFactions.can_hurt(player, ally)).is_true()
	var health := Health.of(other)
	var full := health.value
	_zones_of(other).deliver(HitRecord.blow(10.0, grunt))
	assert_float(health.value).is_equal(full)
	_zones_of(other).deliver(HitRecord.blow(10.0, ally))
	assert_float(health.value).is_less(full)


func test_with_no_factions_everyone_may_hurt_everyone() -> void:
	var grunt := _arena.add_character(Vector3(0.0, 0.0, -3.0))
	var other := _arena.add_character(Vector3(2.0, 0.0, -3.0))
	assert_bool(AiFactions.can_hurt(grunt, other)).is_true()


func test_an_ally_the_player_keeps_shooting_turns_hostile_then_calms_down() -> void:
	var factions := _factions()
	var player := _player_member()
	var ally := _arena.add_character(Vector3(0.0, 0.0, -3.0), load(ALLY) as AiProfile)
	await get_tree().physics_frame
	var health := Health.of(ally)
	var shots := 0
	while not factions.is_hostile_between(ally, player) and shots < 10:
		health.value = health.max_value
		_zones_of(ally).deliver(HitRecord.blow(1.0, player))
		shots += 1
	# 80 to -70 in steps of 30: the fifth shot crosses -60.
	assert_int(shots).is_equal(5)
	assert_bool(AiFactions.can_hurt(ally, player)).is_true()
	factions.relations.recover(60.0 * 3.5)
	assert_bool(factions.is_hostile_between(ally, player)).is_false()
	assert_int(factions.band_between(ally, player)).is_equal(AiRelations.Band.UNFRIENDLY)
	factions.relations.recover(60.0 * 60.0)
	assert_int(factions.band_between(ally, player)).is_equal(AiRelations.Band.ALLIED)


func test_a_kill_counts_on_top_of_the_blow() -> void:
	var factions := _factions()
	var player := _player_member()
	var civilian := _arena.add_character(Vector3(0.0, 0.0, -3.0), load(CIVILIAN) as AiProfile)
	await get_tree().physics_frame
	_zones_of(civilian).deliver(HitRecord.blow(Health.of(civilian).max_value * 2.0, player))
	assert_bool(civilian.is_dead()).is_true()
	assert_float(factions.relations.attitude(&"civilian", &"player")).is_equal(20.0 - 30.0 - 60.0)


func test_the_band_rings_follow_the_band_toward_the_player() -> void:
	var factions := _factions()
	_player_member()
	var grunt := _arena.add_character(Vector3(0.0, 0.0, -3.0))
	var ally := _arena.add_character(Vector3(2.0, 0.0, -3.0), load(ALLY) as AiProfile)
	var ring := AiFactionMember.of(grunt).band_marker
	assert_bool(ring.visible).is_false()
	factions.show_bands = true
	assert_bool(ring.visible).is_true()
	var grunt_color := (ring.material_override as StandardMaterial3D).albedo_color
	var ally_ring := AiFactionMember.of(ally).band_marker
	var ally_color := (ally_ring.material_override as StandardMaterial3D).albedo_color
	assert_that(grunt_color).is_equal(factions.band_colors[AiRelations.Band.HOSTILE])
	assert_that(ally_color).is_equal(factions.band_colors[AiRelations.Band.ALLIED])
	factions.show_bands = false
	assert_bool(ring.visible).is_false()


func test_a_profile_faction_applies_live() -> void:
	var factions := _factions()
	var player := _player_member()
	var character := _arena.add_character(Vector3(0.0, 0.0, -3.0))
	assert_bool(factions.is_hostile_between(character, player)).is_true()
	character.profile.faction = &"ally"
	assert_bool(factions.is_hostile_between(character, player)).is_false()

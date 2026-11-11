# The reactions over the whole product of their inputs (Deadnight #231, #695: gaps between branches
# left bots standing for minutes): a dry gun never stalls a guard (magazine x reserve x range x play
# state, every cell asks for something within a second of the threat being believed), and no shipped
# kind stands idle with a threat in view for more than 5 s (kind x distance x health x ammo).
extends GdUnitTestSuite

## The most a guard may stand asking for nothing with a believed threat in view, in the dry-gun
## table, and in the idle table (the issue's 5 s).
const DRY_IDLE_LIMIT := 1.0
const IDLE_LIMIT := 5.0
const TICK := 1.0 / 60.0

var _arena: BehaviourArena


func before_test() -> void:
	_arena = auto_free(BehaviourArena.new())
	add_child(_arena)
	_arena.add_director()
	_arena.build()
	assert_bool(await _arena.settle()).override_failure_message("the map never answered").is_true()


func after_test() -> void:
	AudioDrain.stop_all(_arena)


# One cell: a `scene` character at the origin facing +Z with `share` of its health and its pistol
# at `magazine` and `reserve`, a threat of `faction` `distance` metres ahead, run for `ticks`.
# Returns [the seconds until the threat was believed (-1: never), the longest stretch it stood
# asking for nothing with the threat believed and in view, what it was doing then].
func _cell(
	scene: String,
	faction: StringName,
	distance: float,
	share: float,
	magazine: int,
	reserve: int,
	ticks: int
) -> Array:
	var character := _arena.add_kind(scene, Vector3(0, 0, -6), 0.0)
	var health := Health.of(character)
	health.value = health.max_value * share
	character.weapon.set_ammo(magazine, reserve)
	var threat := _arena.add_target("Threat", Vector3(0, 0, -6 + distance), faction)
	var senses := character.senses as AiSenses
	var believed_at := -1.0
	var idle := 0.0
	var longest := 0.0
	var doing := ""
	for tick in ticks:
		await get_tree().physics_frame
		var belief := senses.beliefs.of(threat)
		var in_view := belief != null and belief.believed and belief.seen_now
		if belief != null and belief.believed and believed_at < 0.0:
			believed_at = tick * TICK
		if in_view and not BehaviourArena.asks_something(character):
			idle += TICK
			if idle > longest:
				longest = idle
				doing = (
					"%s (%s)"
					% [
						BehaviourArena.runner_of(character).describe_text().replace("\n", " / "),
						BehaviourArena.brain_of(character).debug_text()
					]
				)
		else:
			idle = 0.0
	character.free()
	threat.free()
	AiSensePool.forget()
	await get_tree().physics_frame
	return [believed_at, longest, doing]


func test_a_dry_gun_never_stalls_a_guard() -> void:
	var failures: Array[String] = []
	var cells := 0
	for ammo: Vector2i in [Vector2i(12, 36), Vector2i(0, 12), Vector2i(0, 0)]:
		for distance: float in [1.2, 8.0, 20.0]:
			for share: float in [1.0, 0.45, 0.15]:
				var result: Array = await _cell(
					BehaviourArena.GUARD, &"player", distance, share, ammo.x, ammo.y, 300
				)
				cells += 1
				var label := (
					"mag %d reserve %d at %.1f m, health %.2f" % [ammo.x, ammo.y, distance, share]
				)
				if result[0] < 0.0:
					failures.append(label + ": the threat was never believed")
				elif result[1] > DRY_IDLE_LIMIT:
					failures.append("%s: idle %.2f s doing %s" % [label, result[1], result[2]])
	assert_int(cells).is_equal(27)
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()


func test_no_shipped_kind_stands_idle_with_a_threat_for_more_than_five_seconds() -> void:
	var kinds := [
		[BehaviourArena.GUARD, &"player"],
		[BehaviourArena.ALLY, &"enemy"],
		[BehaviourArena.CIVILIAN, &"enemy"],
	]
	var failures: Array[String] = []
	var cells := 0
	for kind: Array in kinds:
		for distance: float in [1.8, 10.0]:
			for share: float in [1.0, 0.45, 0.15]:
				for ammo: Vector2i in [Vector2i(12, 36), Vector2i(0, 0)]:
					var result: Array = await _cell(
						kind[0], kind[1], distance, share, ammo.x, ammo.y, 480
					)
					cells += 1
					var label := (
						"%s at %.1f m, health %.2f, mag %d"
						% [String(kind[0]).get_file(), distance, share, ammo.x]
					)
					if result[1] > IDLE_LIMIT:
						failures.append("%s: idle %.2f s doing %s" % [label, result[1], result[2]])
	assert_int(cells).is_equal(36)
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()

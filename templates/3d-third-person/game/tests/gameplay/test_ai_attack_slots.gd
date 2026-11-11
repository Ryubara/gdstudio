# Attack slots (kit #1203): the director hands out at most N engagement slots a target and a cap
# for the whole fight; a guard without one holds with its gun down and waits; a slot frees on a
# death, a loss of sight or the end of the engage task, and a waiting guard takes it. The counts
# are the director's inspector settings (`test_ai_exports.gd` pins them).
extends GdUnitTestSuite

## Slots a target in the scenario (the desktop's count set low, so 20 guards are well over it).
const SLOTS := 4
const GUARDS := 20
## The guards stand on an arc this far from the target, all on one side (a miss flies on into
## the empty half, not into a guard across the ring).
const RING := 10.0
const ARC := deg_to_rad(160.0)
## Ticks of one window (the fight is watched for 10 of them).
const WINDOW := 30

var _arena: BehaviourArena


func before_test() -> void:
	_arena = auto_free(BehaviourArena.new())
	add_child(_arena)
	_arena.add_director()


func after_test() -> void:
	AudioDrain.stop_all(_arena)
	AiNoise._runs_here = -1


# Ticks until `done` returns true; the ticks it took, or -1 after `limit`.
func _until(done: Callable, limit: int) -> int:
	for tick in limit:
		if done.call():
			return tick
		await get_tree().physics_frame
	return -1 if not done.call() else limit


func test_a_target_takes_at_most_its_slots_and_the_fight_its_cap() -> void:
	var slots := AiAttackSlots.new()
	slots.per_target = 2
	slots.total = 3
	var a: Node = auto_free(Node.new())
	var b: Node = auto_free(Node.new())
	var guards: Array[Node] = []
	for _i in 4:
		guards.append(auto_free(Node.new()))
	assert_bool(slots.claim(guards[0], a, 0)).is_true()
	assert_bool(slots.claim(guards[1], a, 0)).is_true()
	assert_bool(slots.claim(guards[2], a, 0)).override_failure_message("a's third").is_false()
	assert_bool(slots.claim(guards[2], b, 0)).is_true()
	assert_bool(slots.claim(guards[3], b, 0)).override_failure_message("over the cap").is_false()
	# Asking again keeps the slot; turning to another target gives the old one up first.
	assert_bool(slots.claim(guards[0], a, 5)).is_true()
	assert_int(slots.count()).is_equal(3)
	assert_bool(slots.claim(guards[1], b, 5)).is_true()
	assert_int(slots.count(a)).is_equal(1)
	assert_int(slots.count(b)).is_equal(2)
	slots.release(guards[2])
	assert_bool(slots.holds(guards[2])).is_false()
	assert_bool(slots.claim(guards[3], a, 5)).is_true()


func test_a_slot_whose_holder_is_gone_or_silent_frees_when_one_is_wanted() -> void:
	var slots := AiAttackSlots.new()
	slots.per_target = 1
	slots.total = 4
	slots.lease_ticks = 10
	var target: Node = auto_free(Node.new())
	var gone := Node.new()
	var waiting: Node = auto_free(Node.new())
	assert_bool(slots.claim(gone, target, 0)).is_true()
	gone.free()
	assert_bool(slots.claim(waiting, target, 1)).is_true()
	var silent: Node = auto_free(Node.new())
	var other: Node = auto_free(Node.new())
	assert_bool(slots.claim(silent, other, 1)).is_true()
	var next: Node = auto_free(Node.new())
	assert_bool(slots.claim(next, other, 11)).override_failure_message("lease not out").is_false()
	assert_bool(slots.claim(next, other, 12)).is_true()
	assert_bool(slots.holds(silent)).is_false()


func test_the_director_reads_its_counts_for_the_platform() -> void:
	var director := _arena.director
	director.desktop_attack_slots = 3
	director.desktop_fight_cap = 5
	# The signal comes before the tick's processing: the second one has seen a tick.
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_int(director.attack_slots_per_target()).is_equal(3)
	assert_int(director.slots.per_target).is_equal(3)
	assert_int(director.slots.total).is_equal(5)


func test_a_slot_holder_goes_before_a_nearer_guard_for_the_full_tier() -> void:
	var director := _arena.director
	director.desktop_full_cap = 1
	var near := _arena.add_character(Vector3(0, 0, 3))
	var far := _arena.add_character(Vector3(0, 0, 9))
	var target := _arena.add_target("Player", Vector3.ZERO)
	var settled := func() -> bool: return near.tier == AiDirector.Tier.FULL
	assert_int(await _until(settled, 40)).is_not_negative()
	assert_int(far.tier).is_equal(AiDirector.Tier.REDUCED)
	assert_bool(director.claim_attack_slot(far, target)).is_true()
	var swapped := func() -> bool: return far.tier == AiDirector.Tier.FULL
	(
		assert_int(await _until(swapped, 40))
		. override_failure_message("holder not Full")
		. is_not_negative()
	)
	assert_int(near.tier).is_equal(AiDirector.Tier.REDUCED)


func test_twenty_guards_fire_at_most_n_at_once_and_a_freed_slot_is_taken() -> void:
	_arena.build()
	assert_bool(await _arena.settle()).override_failure_message("the map never answered").is_true()
	var director := _arena.director
	# Set by name, so the suite runs (and fails) on a build without slots.
	director.set(&"desktop_attack_slots", SLOTS)
	director.set(&"desktop_fight_cap", SLOTS * 2)
	var target := _arena.add_target("Player", Vector3.ZERO)
	var guards: Array[AiCharacter] = []
	for index in GUARDS:
		var angle := -ARC / 2.0 + ARC * index / (GUARDS - 1)
		var spot := Vector3(sin(angle), 0.0, cos(angle)) * RING
		guards.append(_arena.add_kind(BehaviourArena.GUARD, spot, angle + PI))
	var engaged := func() -> bool:
		for guard in guards:
			if BehaviourArena.active_of(guard) != &"engage":
				return false
		return true
	(
		assert_int(await _until(engaged, 600))
		. override_failure_message("not all engaged")
		. is_not_negative()
	)
	# A steady fight: at no tick do more than SLOTS guards aim or pull the trigger (a guard that
	# gives its slot up lets go of both in the same think, before another can take it), and the
	# slots are in use: shots in most windows (a burst rests between).
	var fired: Dictionary = {}
	var most_aiming := 0
	var most_firing := 0
	var quiet_windows := 0
	for window in 10:
		var shots_in_window := 0
		for _tick in WINDOW:
			await get_tree().physics_frame
			var aiming := 0
			var firing := 0
			for guard in guards:
				if guard.ai_controller().aim:
					aiming += 1
				if guard.ai_controller().fire:
					firing += 1
					fired[guard] = true
			most_aiming = maxi(most_aiming, aiming)
			most_firing = maxi(most_firing, firing)
			shots_in_window += firing
		if shots_in_window == 0:
			quiet_windows += 1
	(
		assert_int(most_aiming)
		. override_failure_message("%d guards aimed at once" % most_aiming)
		. is_less_equal(SLOTS)
	)
	(
		assert_int(most_firing)
		. override_failure_message("%d guards fired at once" % most_firing)
		. is_less_equal(SLOTS)
	)
	assert_int(quiet_windows).override_failure_message("windows with no shot").is_less_equal(3)
	assert_int(fired.size()).override_failure_message("guards that fired").is_greater_equal(SLOTS)
	var held := 0
	for guard in guards:
		var attack := BehaviourArena.runner_of(guard).active as AiAttack
		if attack != null and attack.held:
			held += 1
			assert_bool(guard.ai_controller().aim).is_false()
	assert_int(held).is_greater_equal(GUARDS - SLOTS)
	assert_int(director.slots.count(target)).is_equal(SLOTS)
	# A holder dies: a waiting guard takes its slot and fires.
	var dead := _holder(guards)
	dead.die()
	var replaced := func() -> bool: return _new_firer(guards, fired, dead) != null
	(
		assert_int(await _until(replaced, 240))
		. override_failure_message("no one took it")
		. is_not_negative()
	)
	assert_bool(director.slots.holds(dead)).is_false()
	# A holder loses sight: it gives the slot up and another takes it.
	var blind := _holder(guards)
	(blind.senses as AiSenses).sight = false
	var freed := func() -> bool:
		return not director.slots.holds(blind) and director.slots.count(target) == SLOTS
	(
		assert_int(await _until(freed, 240))
		. override_failure_message("sight lost, slot kept")
		. is_not_negative()
	)
	# The engage task ends: its slot is free at once.
	var ended := _holder(guards)
	var runner := BehaviourArena.runner_of(ended)
	runner.force_cancel(runner.active)
	assert_bool(director.slots.holds(ended)).is_false()


# A living guard that holds a slot now.
func _holder(guards: Array[AiCharacter]) -> AiCharacter:
	for guard in guards:
		if not guard.is_dead() and _arena.director.slots.holds(guard):
			return guard
	return null


# A living guard firing now that had not fired before, other than `skip`.
func _new_firer(guards: Array[AiCharacter], fired: Dictionary, skip: AiCharacter) -> AiCharacter:
	for guard in guards:
		if guard != skip and not fired.has(guard) and guard.ai_controller().fire:
			return guard
	return null

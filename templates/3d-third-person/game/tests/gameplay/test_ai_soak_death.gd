# The AI soak's stuck count and a death (kit #1548, `AiSoakWatch`): a character shot dead a moment
# into a stuck episode ends that episode at its last watched tick, so the walking it did in that
# moment adds nothing to its stuck seconds, however long the run goes on after it; `finish()` ends
# only the episodes of characters watched on the last tick.
extends GdUnitTestSuite

const SOAK := "res://tools/soak/ai_soak.tscn"
const SEED := 1
## Seconds the soak runs before the test looks for a walking character (the population is up).
const WARM_SECONDS := 5.0
## Seconds the run goes on after the death: past the watch's 2 s grace, before any respawn.
const AFTER_SECONDS := 3.0
## Ticks the test may look for a character walking a moment into an episode.
const LOOK_TICKS := 1200


func test_a_death_a_moment_into_an_episode_adds_nothing_to_stuck() -> void:
	var soak := (load(SOAK) as PackedScene).instantiate() as AiSoak
	soak.quit_at_end = false
	soak.random_seed = SEED
	soak.seconds = 600.0
	add_child(soak)
	var watch := soak.get_node("Watch") as AiSoakWatch
	await _ticks(int(WARM_SECONDS * Engine.physics_ticks_per_second))
	var picked: AiCharacter = null
	var looked := 0
	while picked == null and looked < LOOK_TICKS:
		await get_tree().physics_frame
		looked += 1
		picked = _walking_into_an_episode(watch)
	(
		assert_object(picked)
		. override_failure_message("no character walked into an episode")
		. is_not_null()
	)
	if picked == null:
		_free(soak)
		return
	var kept: AiSoakWatch.Watch = watch._watches[picked.get_instance_id()]
	var stuck_before := kept.stuck
	var walked := kept.episode_walking
	picked.die()
	await _ticks(int(AFTER_SECONDS * Engine.physics_ticks_per_second))
	assert_bool(picked.is_dead()).override_failure_message("the body got up again").is_true()
	watch.finish()
	assert_float(walked).is_greater(0.0)
	(
		assert_float(kept.stuck)
		. override_failure_message(
			(
				"%s died %.2f s walking into an episode; stuck %.2f s, was %.2f s"
				% [picked.name, walked, kept.stuck, stuck_before]
			)
		)
		. is_equal(stuck_before)
	)
	_free(soak)


# A living character asking to walk whose episode began under a second ago, with walking in it.
func _walking_into_an_episode(watch: AiSoakWatch) -> AiCharacter:
	for watched: AiSoakWatch.Watch in watch._watches.values():
		var character := watched.character
		if not is_instance_valid(character) or character.is_dead():
			continue
		var navigator := character.navigator as AiNavigator
		var going := navigator != null and navigator.is_active() and not navigator.is_arrived()
		var age := watch.clock - watched.anchor_at
		if going and watched.episode_walking > 0.1 and age < 1.0:
			return character
	return null


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _free(soak: AiSoak) -> void:
	remove_child(soak)
	soak.free()

# An AI character is the template's character driven by an `AiController`: it walks where the
# movement channel says, takes a hit through its `Health`, dies into the ragdoll, is counted by
# the director and never taken for the player; the three shipped profiles load with their
# numbers, and the debug overlay is off until asked for.
extends GdUnitTestSuite

const PROFILES := {
	"grunt": "res://gameplay/ai/profiles/grunt.tres",
	"ally": "res://gameplay/ai/profiles/ally.tres",
	"civilian": "res://gameplay/ai/profiles/civilian.tres",
}

var _arena: AiArena


func before_test() -> void:
	_arena = auto_free(AiArena.new())
	add_child(_arena)


# Walking characters play footsteps; a voice still playing at exit is reported as a leak.
func after_test() -> void:
	AudioDrain.stop_all(_arena)


func _ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func test_it_is_the_template_character_with_its_parts() -> void:
	var character := _arena.add_character(Vector3(0.0, 0.0, -3.0))
	assert_object(character).is_instanceof(Character)
	assert_object(character.model).is_not_null()
	assert_object(character.ragdoll_body).is_not_null()
	assert_object(Health.of(character)).is_not_null()
	assert_object(character.ai_controller()).is_not_null()
	assert_bool(character.is_in_group(AiCharacter.GROUP)).is_true()
	assert_bool(character.is_in_group(Player.GROUP)).is_false()
	assert_object(character.senses).is_instanceof(AiSenses)
	for slot in [character.navigator, character.task_runner]:
		assert_object(slot).is_null()


func test_it_walks_where_the_movement_channel_points_and_faces_the_look_when_aiming() -> void:
	var character := _arena.add_character(Vector3(0.0, 0.0, -3.0))
	_arena.add_director()
	var controller := character.ai_controller()
	controller.walk_direction = Vector3.BACK
	await _ticks(40)
	assert_float(character.global_position.z).is_greater(-1.5)
	controller.walk_direction = Vector3.ZERO
	controller.look_direction = Vector3.LEFT
	controller.aim = true
	await _ticks(40)
	assert_bool(character.aiming).is_true()
	var forward := Vector3.BACK.rotated(Vector3.UP, character.facing)
	assert_float(forward.dot(Vector3.LEFT)).is_greater(0.95)


func test_a_fire_held_is_one_press() -> void:
	var controller := AiController.new()
	controller.fire = true
	assert_bool(controller.sample().fire_pressed).is_true()
	assert_bool(controller.sample().fire_pressed).is_false()
	assert_bool(controller.sample().fire).is_true()
	controller.release()
	assert_bool(controller.sample().fire).is_false()
	controller.free()


func test_a_hit_kills_and_ragdolls_it() -> void:
	var character := _arena.add_character(Vector3(0.0, 0.0, -3.0))
	var director := _arena.add_director()
	await _ticks(5)
	var health := Health.of(character)
	character.take_hit(HitRecord.blow(health.max_value * 0.4))
	assert_bool(character.is_dead()).is_false()
	assert_int(character.situation.current).is_equal(AiSituation.Situation.UNAWARE)
	character.take_hit(HitRecord.blow(health.max_value))
	assert_bool(character.is_dead()).is_true()
	assert_int(character.situation.current).is_equal(AiSituation.Situation.DEAD)
	assert_bool(character.died_by_clip).is_false()
	await _ticks(20)
	assert_bool(character.ragdoll_body.is_limp()).is_true()
	assert_int(director.count()).is_equal(1)
	character.revive()
	assert_int(character.situation.current).is_equal(AiSituation.Situation.UNAWARE)


func test_without_a_director_it_steps_itself_and_does_not_think() -> void:
	var character := _arena.add_character(Vector3(0.0, 0.0, -3.0))
	character.ai_controller().walk_direction = Vector3.RIGHT
	await _ticks(30)
	assert_float(character.global_position.x).is_greater(0.5)
	assert_int(character.think_count).is_equal(0)


func test_the_debug_overlay_is_off_until_asked_and_then_names_it() -> void:
	var character := _arena.add_character(Vector3(0.0, 0.0, -3.0))
	_arena.add_director()
	assert_bool(character.debug).is_false()
	assert_bool(character.debug_label.visible).is_false()
	character.debug = true
	assert_bool(character.debug_label.visible).is_true()
	assert_str(character.debug_label.text).contains("Grunt")
	assert_str(character.debug_label.text).contains("Unaware")
	assert_str(character.debug_label.text).contains("Full")
	character.take_hit(HitRecord.blow(1000.0))
	assert_str(character.debug_label.text).contains("Dead")


func test_the_shipped_profiles_load_with_their_numbers() -> void:
	var names := {}
	for kind: String in PROFILES:
		var profile := load(PROFILES[kind]) as AiProfile
		assert_object(profile).is_not_null()
		names[kind] = profile.display_name
		assert_float(profile.think_rate).is_equal(10.0)
		assert_float(profile.reaction_time).is_greater_equal(AiProfile.REACTION_FLOOR)
	assert_dict(names).is_equal({"grunt": "Grunt", "ally": "Ally", "civilian": "Civilian"})
	assert_float((load(PROFILES.civilian) as AiProfile).flee_below_health).is_equal(1.0)


func test_every_profile_number_has_a_range_and_a_default() -> void:
	var profile := AiProfile.new()
	for property in profile.get_property_list():
		if not (property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if property.type in [TYPE_FLOAT, TYPE_INT]:
			assert_int(property.hint).override_failure_message(property.name).is_equal(
				PROPERTY_HINT_RANGE
			)

# The inspector contract of the AI parts: every export of `AiProfile`, `AiDirector`,
# `AiAnimationThrottle` and `AiCharacter` with its default, so a new one fails here until it is
# looked at and pinned (the kit's `docs/engines/godot/third-person/ai.md#inspector` lists the
# same).
extends GdUnitTestSuite


func test_the_profile_defaults_are_pinned() -> void:
	var profile := AiProfile.new()
	var pins := {
		&"display_name": "AI",
		&"walk_speed": 1.6,
		&"run_speed": 4.5,
		&"turn_rate": 360.0,
		&"acceleration": 12.0,
		&"sight_range": 24.0,
		&"lose_sight_range": 32.0,
		&"half_angle": 55.0,
		&"near_radius": 2.0,
		&"hearing_range": 30.0,
		&"time_to_notice": 0.6,
		&"reaction_time": 0.35,
		&"memory_seconds": 6.0,
		&"suspicious_at": 0.3,
		&"awareness_hysteresis": 0.1,
		&"engage_range": 18.0,
		&"preferred_range": 10.0,
		&"attack_range": 1.6,
		&"fire_interval": 0.4,
		&"burst_size": 3,
		&"accuracy": 0.5,
		&"aim_speed": 360.0,
		&"retreat_margin": 3.0,
		&"courage": 0.5,
		&"flee_below_health": 0.3,
		&"panic_recovery_seconds": 8.0,
		&"aggression": 0.5,
		&"curiosity": 0.5,
		&"alert_hold_seconds": 10.0,
		&"situation_dwell": 1.0,
		&"faction": &"neutral",
		&"share_radius": 12.0,
		&"share_delay": 0.5,
		&"obeys_orders": 0.5,
		&"think_rate": 10.0,
		&"reduced_think_rate": 2.0,
		&"dormant_think_rate": 0.5,
		&"full_range": 25.0,
		&"reduced_range": 70.0,
		&"tier_margin": 4.0,
		&"max_rays_per_think": 2,
		&"repath_seconds": 0.25,
		&"under_attack": AiTask.UnderAttack.FINISH_THEN_REACT,
		&"task_hard_timeout": 30.0,
		&"failure_budget": 3,
		&"failure_window": 10.0,
		&"fallback_seconds": 5.0,
		&"commit_seconds": 0.5,
	}
	assert_array(ExportPins.differences(profile, pins)).is_empty()
	assert_array(ExportPins.wrong_values(profile, pins)).is_empty()


func test_the_director_defaults_are_pinned() -> void:
	var director: AiDirector = auto_free(AiDirector.new())
	var pins := {
		&"web_cap": 40,
		&"desktop_cap": 120,
		&"web_full_cap": 12,
		&"desktop_full_cap": 60,
		&"player_group": &"player",
		&"rays_per_tick": 8,
		&"paths_per_tick": 4,
		&"thinks_per_tick": 12,
		&"reduced_step_ticks": 4,
		&"dormant_step_ticks": 6,
		&"rest_step_ticks": 3,
		&"animation_throttle": null,
	}
	assert_array(ExportPins.differences(director, pins)).is_empty()
	assert_array(ExportPins.wrong_values(director, pins)).is_empty()


func test_the_animation_throttle_defaults_are_pinned() -> void:
	var throttle: AiAnimationThrottle = auto_free(AiAnimationThrottle.new())
	var pins := {
		&"enabled": true,
		&"near_distance": 15.0,
		&"far_distance": 25.0,
		&"footstep_range": 15.0,
		&"reduced_period": 3,
		&"far_period": 6,
		&"freeze_unseen": true,
		&"max_catch_up": 0.25,
		&"hit_hold": 1.0,
		&"recheck_frames": 4,
		&"throttle_skeleton": true,
		&"camera": null,
	}
	assert_array(ExportPins.differences(throttle, pins)).is_empty()
	assert_array(ExportPins.wrong_values(throttle, pins)).is_empty()


func test_the_character_adds_only_its_ai_exports() -> void:
	var character: AiCharacter = auto_free(
		(load("res://gameplay/ai/ai_character.tscn") as PackedScene).instantiate()
	)
	var own: Array[StringName] = []
	var base: Array[StringName] = ExportPins.names(
		auto_free(
			(load("res://gameplay/character/character_dressed.tscn") as PackedScene).instantiate()
		)
	)
	for export_name in ExportPins.names(character):
		if not base.has(export_name):
			own.append(export_name)
	assert_array(own).is_equal(
		[&"profile", &"debug", &"debug_label", &"senses", &"navigator", &"task_runner"]
	)
	assert_bool(character.debug).is_false()
	assert_str((character.profile as AiProfile).display_name).is_equal("Grunt")


func test_the_task_defaults_are_pinned() -> void:
	var pins := {
		&"id": &"",
		&"layer": AiTask.Layer.ROUTINE,
		&"channels": AiTask.Channel.MOVE,
		&"interruptible": AiTask.Interruptible.YES,
		&"when_interrupted": AiTask.WhenInterrupted.SUSPEND_RESUME,
		&"resume_valid_for": 0.0,
		&"under_attack": AiTask.UnderAttack.PROFILE,
		&"abort_damage": 20.0,
		&"abort_window": 1.0,
		&"persistent": false,
		&"reactive": true,
		&"replace_policy": AiTask.ReplacePolicy.MERGE,
		&"timeout": 0.0,
		&"hard_timeout": -1.0,
		&"ends_on_condition": false,
		&"expires_after": 0.0,
		&"on_fail": AiTask.OnFail.SKIP,
		&"retry_count": 1,
		&"retry_delay": 0.5,
		&"fallback": null,
		&"authority": 0,
		&"need": &"",
	}
	var task := AiTask.new()
	assert_array(ExportPins.differences(task, pins)).is_empty()
	assert_array(ExportPins.wrong_values(task, pins)).is_empty()
	var composite_pins := pins.duplicate()
	composite_pins[&"children"] = []
	assert_array(ExportPins.differences(AiTaskSequence.new(), composite_pins)).is_empty()
	assert_array(ExportPins.differences(AiTaskSelector.new(), composite_pins)).is_empty()
	var parallel_pins := composite_pins.duplicate()
	parallel_pins[&"finish_on_first"] = false
	assert_array(ExportPins.differences(AiTaskParallel.new(), parallel_pins)).is_empty()
	var repeat_pins := composite_pins.duplicate()
	repeat_pins[&"count"] = 0
	assert_array(ExportPins.differences(AiTaskRepeat.new(), repeat_pins)).is_empty()


func test_the_tasks_node_and_the_needs_defaults_are_pinned() -> void:
	var tasks: AiTasks = auto_free(AiTasks.new())
	var pins := {
		&"default_task": null,
		&"routine": null,
		&"attack_task": null,
		&"needs": null,
		&"label": null,
	}
	assert_array(ExportPins.differences(tasks, pins)).is_empty()
	assert_array(ExportPins.wrong_values(tasks, pins)).is_empty()
	var row_pins := {&"need": &"", &"order": &"*", &"gives_way_at": 0.5}
	assert_array(ExportPins.differences(AiNeedRow.new(), row_pins)).is_empty()
	assert_array(ExportPins.wrong_values(AiNeedRow.new(), row_pins)).is_empty()
	assert_array(ExportPins.differences(AiNeeds.new(), {&"rows": []})).is_empty()

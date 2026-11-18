# The AI's run does not depend on how many objects were made before it (kit #1547): no AI part
# takes a phase, a seed or an order from an instance id. The soak's seed 11 for 120 s gives the
# same `command_hash` plain and after one extra object (`tests/fixtures/soak_after_objects.gd`),
# each in a fresh process (an instance id is a process-wide counter). With the noise maker's
# phase from its instance id the two hashes differed (2810472258 and 35031318); at 60 s they
# still matched, so the run is the full 120 s.
#
# The fixture puts the soak in the tree before the engine's first frame, as the plain run's
# command line does (kit #1591): it used `change_scene_to_file`, a frame later, and on one commit
# (a977e1358) that alone moved the hash on Windows, with no object made (`--objects 0` gave the
# same "after it" hash): the first ragdoll stepped a last bit apart four ticks in. A failure runs
# `--objects 0` too and names which of the two moved the run.
extends GdUnitTestSuite

const SOAK := "res://tools/soak/ai_soak.tscn"
const AFTER_OBJECTS := "res://tests/fixtures/soak_after_objects.gd"
## The seed and length that showed the instance-id phase.
const SEED := 11
const SECONDS := 120


func test_an_extra_object_leaves_the_run_unchanged() -> void:
	var plain := _soak_process(PackedStringArray([SOAK]), [])
	var extra_run := _soak_process(PackedStringArray(["-s", AFTER_OBJECTS]), ["--objects", "1"])
	assert_bool(plain.has("command_hash")).override_failure_message(str(plain)).is_true()
	assert_bool(extra_run.has("command_hash")).override_failure_message(str(extra_run)).is_true()
	var message := ""
	if int(extra_run.command_hash) != int(plain.command_hash):
		var none := _soak_process(PackedStringArray(["-s", AFTER_OBJECTS]), ["--objects", "0"])
		message = (
			"one more object changed the AI's run: %d plain, %d after it, %s with no object (%s)"
			% [
				int(plain.command_hash),
				int(extra_run.command_hash),
				str(int(none.get("command_hash", -1))),
				(
					"the fixture's start moved it"
					if int(none.get("command_hash", -1)) != int(plain.command_hash)
					else "an instance id moved it"
				),
			]
		)
	assert_int(int(extra_run.command_hash)).override_failure_message(message).is_equal(
		int(plain.command_hash)
	)
	assert_int(int(extra_run.error_count)).is_zero()


# The soak's `AI_SOAK` result from a headless Godot of its own, started with `start` (the soak
# scene, or a main loop script that starts it) and the soak's options plus `extra` after `--`.
func _soak_process(start: PackedStringArray, extra: Array) -> Dictionary:
	var output: Array = []
	var args := PackedStringArray(
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60"]
	)
	args.append_array(start)
	args.append_array(PackedStringArray(["--", "--seconds", str(SECONDS), "--seed", str(SEED)]))
	args.append_array(PackedStringArray(extra))
	OS.execute(OS.get_executable_path(), args, output, true)
	for line in "\n".join(PackedStringArray(output)).split("\n"):
		if line.begins_with("AI_SOAK {"):
			return JSON.parse_string(line.trim_prefix("AI_SOAK "))
	return {"output": "\n".join(PackedStringArray(output)).right(2000)}

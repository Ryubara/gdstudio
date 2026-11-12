# The AI soak (kit #971, `tools/soak/ai_soak.tscn`): its pull-request seed runs green; every gate
# of `AiSoakWatch` breaks on the fault it is there for (`AiSoakFaults`, one fault a hostile, all
# in one run), and names that fault's target; the same seed gives the same command stream and
# another seed a different one. The nightly job (`.github/workflows/ai-soak.yml`) runs 50 seeds.
extends GdUnitTestSuite

const SOAK := "res://tools/soak/ai_soak.tscn"
## The seed the pull-request run holds green.
const GREEN_SEED := 1
## Ticks past its seconds a run may take (a run that never ends fails, not hangs).
const SPARE_TICKS := 600


# Runs the soak with `settings` (properties of `AiSoak`) and `faults`, and returns its result.
func _soak(settings: Dictionary, faults := 0) -> Dictionary:
	var soak := (load(SOAK) as PackedScene).instantiate() as AiSoak
	soak.quit_at_end = false
	for key: String in settings:
		soak.set(key, settings[key])
	soak.get_node("Faults").faults = faults
	add_child(soak)
	var limit := int(soak.seconds * Engine.physics_ticks_per_second) + SPARE_TICKS
	var ticks := 0
	while soak.result.is_empty() and ticks < limit:
		await get_tree().physics_frame
		ticks += 1
	var result := soak.result.duplicate(true)
	result["failures"] = soak.get_node("Watch").failures.duplicate(true)
	result["targets"] = (soak.get_node("Faults") as AiSoakFaults).target_names()
	remove_child(soak)
	soak.free()
	await get_tree().process_frame
	return result


func test_the_soak_is_green_for_its_seed() -> void:
	var result := await _soak({"seconds": 120.0, "random_seed": GREEN_SEED})
	assert_bool(result.is_empty()).override_failure_message("the soak never ended").is_false()
	var why := PackedStringArray()
	for sample: Dictionary in result.failures:
		why.append(JSON.stringify(sample))
	assert_dict(result.gates).override_failure_message("\n".join(why)).is_empty()
	assert_int(result.error_count).is_zero()
	assert_int(result.characters).is_greater_equal(16)
	assert_int(result.player_shots).is_greater(0)


func test_each_gate_breaks_on_its_fault() -> void:
	var all := 0
	for fault: int in AiSoakFaults.GATE_OF:
		all |= fault
	var result := await _soak(
		{
			"seconds": 60.0,
			"random_seed": GREEN_SEED,
			"population_scale": 2,
			"round_seconds": 20.0,
			"rescue_seconds": 10.0,
		},
		all
	)
	assert_bool(result.is_empty()).override_failure_message("the soak never ended").is_false()
	assert_bool(result.passed).is_false()
	var named := {}
	for sample: Dictionary in result.failures:
		var gate := String(sample.gate)
		if not named.has(gate):
			named[gate] = []
		named[gate].append(String(sample.get("character", "")))
		if gate == "round":
			named[gate].append(String(sample.why))
	for fault: int in AiSoakFaults.GATE_OF:
		var gate := String(AiSoakFaults.GATE_OF[fault])
		(
			assert_bool(named.has(gate))
			. override_failure_message(
				"the %s gate did not break: %s" % [gate, JSON.stringify(result.gates)]
			)
			. is_true()
		)
		var target := String(result.targets.get(gate, ""))
		if fault == AiSoakFaults.Fault.ERROR or fault == AiSoakFaults.Fault.SLOW_THINK:
			continue
		(
			assert_str(target)
			. override_failure_message("the %s fault took no target" % gate)
			. is_not_empty()
		)
		var names := " ".join(PackedStringArray(named.get(gate, [])))
		(
			assert_str(names)
			. override_failure_message(
				"the %s gate named %s, not the target %s" % [gate, names, target]
			)
			. contains(target)
		)


func test_the_same_seed_repeats_its_commands() -> void:
	# Each run in a process of its own: the AI keeps counters across a process (the navigators'
	# phases and seeds), so a replay is a fresh start with the same seed, as the nightly's are.
	var first := _soak_process(3)
	var again := _soak_process(3)
	var other := _soak_process(4)
	assert_bool(first.has("command_hash")).override_failure_message(str(first)).is_true()
	assert_int(int(again.command_hash)).is_equal(int(first.command_hash))
	assert_int(int(other.command_hash)).is_not_equal(int(first.command_hash))


# The soak's `AI_SOAK` result from a headless Godot of its own: 20 s at the fixed step, `seed`.
func _soak_process(seed_value: int) -> Dictionary:
	var output: Array = []
	var args := PackedStringArray(
		[
			"--headless",
			"--path",
			ProjectSettings.globalize_path("res://"),
			"--fixed-fps",
			"60",
			SOAK,
			"--",
			"--seconds",
			"20",
			"--seed",
			str(seed_value),
		]
	)
	OS.execute(OS.get_executable_path(), args, output, true)
	for line in "\n".join(PackedStringArray(output)).split("\n"):
		if line.begins_with("AI_SOAK {"):
			return JSON.parse_string(line.trim_prefix("AI_SOAK "))
	return {"output": "\n".join(PackedStringArray(output)).right(2000)}

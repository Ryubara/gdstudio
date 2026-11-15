# The AI soak's per-episode probe (kit #1543, `AiSoakProbe`): the soak's teeth case for the stuck
# gate (a hostile held where it stands while its navigator is sent on) run with the probe makes a
# block for the held hostile, its rows tick by tick with the body still and its navigator asked to
# walk; without the probe nothing is recorded; with it a run's commands are the same as without
# it; the option's values and the ring's length.
extends GdUnitTestSuite

const SOAK := "res://tools/soak/ai_soak.tscn"
const SEED := 1
## Seconds of the teeth run: the held episode passes the 10 s gate and ends with the run.
const RUN_SECONDS := 20.0
## Ticks past its seconds a run may take (a run that never ends fails, not hangs).
const SPARE_TICKS := 600


# Runs the soak with `settings` and `faults` (`probe` on or off); returns its result, the watch's
# failures and the probe's blocks.
func _soak(settings: Dictionary, faults: int, probe: bool) -> Dictionary:
	var soak := (load(SOAK) as PackedScene).instantiate() as AiSoak
	soak.quit_at_end = false
	for key: String in settings:
		soak.set(key, settings[key])
	(soak.get_node("Watch") as AiSoakWatch).probe_episodes = probe
	soak.get_node("Faults").faults = faults
	add_child(soak)
	var limit := int(soak.seconds * Engine.physics_ticks_per_second) + SPARE_TICKS
	var ticks := 0
	while soak.result.is_empty() and ticks < limit:
		await get_tree().physics_frame
		ticks += 1
	var watch := soak.get_node("Watch") as AiSoakWatch
	var result := soak.result.duplicate(true)
	result["failures"] = watch.failures.duplicate(true)
	result["targets"] = (soak.get_node("Faults") as AiSoakFaults).target_names()
	result["blocks"] = watch.probe_blocks.duplicate(true)
	remove_child(soak)
	soak.free()
	await get_tree().process_frame
	return result


func test_the_held_hostile_s_episode_prints_its_ticks() -> void:
	var result := await _soak(
		{"seconds": RUN_SECONDS, "random_seed": SEED}, AiSoakFaults.Fault.STUCK, true
	)
	assert_bool(result.has("command_hash")).override_failure_message("never ended").is_true()
	var target := String(result.targets.get("stuck_episode", ""))
	assert_str(target).override_failure_message("the stuck fault took no target").is_not_empty()
	assert_int(int(result.probe_episodes)).is_equal(result.blocks.size())
	var held: Dictionary = {}
	for block: Dictionary in result.blocks:
		if block.character == target and float(block.seconds) > held.get("seconds", 0.0):
			held = block
	(
		assert_bool(held.is_empty())
		. override_failure_message("no block for %s: %s" % [target, str(result.blocks)])
		. is_false()
	)
	var columns: Array = held.columns
	var rows: Array = held.rows
	# The episode passed the gate's 10 s; the block keeps the ring's last 10 s of it, a row a tick
	# up to its last (the held hostile may be shot dead: its death closes the episode).
	assert_float(float(held.seconds)).is_greater(10.0)
	assert_int(rows.size()).is_equal(600)
	var last: Array = rows[-1]
	var t := columns.find("t")
	assert_float(float(held.until)).is_equal(float(last[t]))
	assert_float(float(last[t]) - float(rows[0][t])).is_equal_approx(599.0 / 60.0, 0.05)
	assert_float(float(last[t])).is_less_equal(float(held.from) + float(held.seconds) + 0.02)
	var going := 0
	var first: Array = rows[0]
	for row: Array in rows:
		if bool(row[columns.find("going")]):
			going += 1
		var moved := Vector2(row[1] - first[1], row[2] - first[2]).length()
		assert_float(moved).override_failure_message("the held body moved").is_less(0.5)
	# Asked to walk nearly every tick: the fault sends its navigator on when it gives up.
	assert_int(going).is_greater(rows.size() * 9 / 10)
	assert_int(columns.size()).is_equal(AiSoakProbe.COLUMNS.size())


func test_without_the_probe_nothing_is_recorded() -> void:
	var result := await _soak(
		{"seconds": RUN_SECONDS, "random_seed": SEED}, AiSoakFaults.Fault.STUCK, false
	)
	assert_bool(result.has("command_hash")).override_failure_message("never ended").is_true()
	assert_bool(result.has("probe_episodes")).is_false()
	assert_array(result.blocks).is_empty()
	assert_bool(result.gates.has("stuck_episode")).is_true()


func test_the_option_s_values() -> void:
	for off: String in ["0", "off", "false"]:
		assert_bool(AiSoakProbe.option_on(off)).is_false()
	for every: String in ["", "1", "all"]:
		assert_bool(AiSoakProbe.option_on(every)).is_true()
		assert_array(Array(AiSoakProbe.option_kinds(every))).is_empty()
	assert_bool(AiSoakProbe.option_on("Civilian, Grunt")).is_true()
	assert_array(Array(AiSoakProbe.option_kinds("Civilian, Grunt"))).contains_exactly(
		["Civilian", "Grunt"]
	)


func test_the_ring_keeps_its_last_ticks() -> void:
	var ring: Array = []
	for tick in 250:
		ring = AiSoakProbe.push(ring, [tick / 60.0], 100)
	assert_int(ring.size()).is_between(100, 200)
	assert_float(float(ring[-1][0])).is_equal_approx(249.0 / 60.0, 0.001)


# The probe makes no object, so a run with it is the run without it: a stuck episode found in a
# plain run is the one the probe prints. Seed 11 for 120 s, each run in a fresh process: one more
# object made before the AI changed this run's commands (a noise maker's phase is its instance id).
func test_the_probe_leaves_the_run_as_it_was() -> void:
	var plain := _soak_process(PackedStringArray())
	var probed := _soak_process(PackedStringArray(["--probe"]))
	assert_bool(plain.has("command_hash")).override_failure_message(str(plain)).is_true()
	assert_bool(probed.has("probe_episodes")).override_failure_message(str(probed)).is_true()
	assert_bool(plain.has("probe_episodes")).is_false()
	assert_int(int(probed.command_hash)).is_equal(int(plain.command_hash))


# The soak's `AI_SOAK` result from a headless Godot of its own: seed 11 for 120 s, with `extra`.
func _soak_process(extra: PackedStringArray) -> Dictionary:
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
			"120",
			"--seed",
			"11",
		]
	)
	args.append_array(extra)
	OS.execute(OS.get_executable_path(), args, output, true)
	var text := "\n".join(PackedStringArray(output))
	for line in text.split("\n"):
		if line.begins_with("AI_SOAK {"):
			return JSON.parse_string(line.trim_prefix("AI_SOAK "))
	return {"output": text.right(2000)}

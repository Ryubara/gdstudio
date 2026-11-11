# The router as a table (Deadnight's "every cell asks for something"): every event x band x
# situation of each shipped `AiBehaviourSet` asks for something in every play state or has a written
# waiver (or a situation's block); every stock task has a row; the router picks the first row that
# matches and passes a failed chance down; a block and a closed layer hold; and the brain has no
# branch for any behaviour (it names no stock task).
extends GdUnitTestSuite

const SETS: Array[String] = [
	"res://gameplay/ai/behaviour/sets/hostile_guard.tres",
	"res://gameplay/ai/behaviour/sets/friendly_ally.tres",
	"res://gameplay/ai/behaviour/sets/civilian.tres",
]
const STOCK := "res://gameplay/ai/tasks/stock/"
## Stock scripts that are not tasks of their own (the base and the aim model).
const NOT_TASKS: Array[String] = ["ai_stock_task.gd", "ai_aim.gd"]
const BRAIN := "res://gameplay/ai/behaviour/ai_brain.gd"


func _load_set(path: String) -> AiBehaviourSet:
	return load(path) as AiBehaviourSet


# Every uncovered cell of `set_of`, as "event x band x situation".
func _holes(set_of: AiBehaviourSet) -> PackedStringArray:
	var holes := PackedStringArray()
	for event in AiBehaviourSet.EVENTS:
		for band in AiBehaviourSet.BANDS:
			for situation in AiBehaviourSet.ROUTED_SITUATIONS:
				if set_of.coverage(event, band, situation).is_empty():
					holes.append(
						(
							"%s x %s x %s"
							% [event, AiRelations.BAND_NAMES[band], AiSituation.NAMES[situation]]
						)
					)
	return holes


func test_every_cell_of_every_shipped_set_asks_for_something_or_is_waived() -> void:
	for path in SETS:
		var holes := _holes(_load_set(path))
		(
			assert_array(holes)
			. override_failure_message(
				"%s has cells with no answer:\n%s" % [path, "\n".join(holes)]
			)
			. is_empty()
		)


func test_the_coverage_test_finds_a_row_taken_out() -> void:
	var guard := _load_set(SETS[0]).duplicate(true) as AiBehaviourSet
	var kept: Array[AiReactionRow] = []
	for row in guard.rows:
		if row.event != AiBehaviourSet.LOST_TRAIL:
			kept.append(row)
	guard.rows = kept
	var holes := _holes(guard)
	assert_bool(holes.size() > 0).is_true()
	assert_str(holes[0]).starts_with("lost_trail")


func test_a_waiver_needs_a_reason() -> void:
	var waiver := AiReactionWaiver.new()
	waiver.event = AiBehaviourSet.HIT
	waiver.bands = 31
	waiver.situations = 31
	assert_bool(waiver.covers(AiBehaviourSet.HIT, 0, 0)).is_false()
	waiver.reason = "because"
	assert_bool(waiver.covers(AiBehaviourSet.HIT, 0, 0)).is_true()


func test_every_stock_task_has_a_row_in_a_shipped_set() -> void:
	var used := {}
	for path in SETS:
		for task in _load_set(path).tasks():
			used[(task.get_script() as Script).resource_path.get_file()] = true
	var missing := _stock_without_row(used)
	(
		assert_array(missing)
		. override_failure_message("stock tasks with no row: %s" % ", ".join(missing))
		. is_empty()
	)
	# The check fails on a stock task no set uses.
	used.erase("ai_say.gd")
	assert_array(_stock_without_row(used)).contains(["ai_say.gd"])


func test_every_row_and_waiver_says_why() -> void:
	for path in SETS:
		var set_of := _load_set(path)
		for row in set_of.rows:
			assert_str(row.note.strip_edges()).override_failure_message(path).is_not_empty()
		for waiver in set_of.waivers:
			assert_str(waiver.reason.strip_edges()).override_failure_message(path).is_not_empty()


func test_the_router_picks_the_first_row_that_matches_the_cell() -> void:
	var guard := _load_set(SETS[0])
	var profile := AiProfile.new()
	var never := func() -> float: return 0.99
	var row := guard.pick(
		AiBehaviourSet.NOTICED, 0, 0, AiPlayState.State.AGGRESSIVE, 1.0, profile, never
	)
	assert_object(row.task).is_instanceof(AiAttack)
	row = guard.pick(AiBehaviourSet.NOTICED, 0, 0, AiPlayState.State.CAREFUL, 1.0, profile, never)
	assert_object(row.task).is_instanceof(AiTakeCover)
	row = guard.pick(
		AiBehaviourSet.NOTICED, 1, 0, AiPlayState.State.AGGRESSIVE, 1.0, profile, never
	)
	assert_object(row.task).is_instanceof(AiLookAt)


func test_a_failed_chance_passes_the_event_to_the_row_below() -> void:
	var guard := _load_set(SETS[0])
	var profile := AiProfile.new()
	profile.curiosity = 0.5
	var low := func() -> float: return 0.1
	var high := func() -> float: return 0.9
	var curious := guard.pick(AiBehaviourSet.HEARD, 0, 0, 0, 0.5, profile, low)
	assert_object(curious.task).is_instanceof(AiInvestigate)
	var incurious := guard.pick(AiBehaviourSet.HEARD, 0, 0, 0, 0.5, profile, high)
	assert_object(incurious.task).is_instanceof(AiLookAt)


func test_courage_picks_flight_or_cowering_for_a_civilian() -> void:
	var civilian := _load_set(SETS[2])
	var profile := AiProfile.new()
	var roll := func() -> float: return 0.5
	profile.courage = 0.1
	var row := civilian.pick(AiBehaviourSet.NOTICED, 0, 0, 0, 1.0, profile, roll)
	assert_str(String(row.task.id)).is_equal("flee")
	profile.courage = 0.0
	row = civilian.pick(AiBehaviourSet.NOTICED, 0, 0, 0, 1.0, profile, roll)
	assert_object(row.task).is_instanceof(AiCower)
	profile.courage = 1.0
	row = civilian.pick(AiBehaviourSet.NOTICED, 0, 0, AiPlayState.State.SAFE, 1.0, profile, roll)
	assert_object(row.task).is_instanceof(AiCower)


func test_an_engaged_guard_blocks_footsteps_and_glimpses() -> void:
	var guard := _load_set(SETS[0])
	var engaged := AiSituation.Situation.ENGAGED
	assert_bool(guard.blocks(engaged, AiBehaviourSet.HEARD)).is_true()
	assert_bool(guard.blocks(engaged, AiBehaviourSet.SUSPICIOUS)).is_true()
	assert_bool(guard.blocks(engaged, AiBehaviourSet.HIT)).is_false()
	assert_bool(guard.blocks(AiSituation.Situation.UNAWARE, AiBehaviourSet.HEARD)).is_false()


func test_a_closed_layer_keeps_a_row_task_out() -> void:
	var rule := AiSituationRule.new()
	rule.situation = AiSituation.Situation.ENGAGED
	rule.open_layers = 1 | 2
	var set_of := AiBehaviourSet.new()
	set_of.situation_rules = [rule]
	assert_bool(set_of.layer_open(AiSituation.Situation.ENGAGED, AiTask.Layer.RESPONSE)).is_true()
	assert_bool(set_of.layer_open(AiSituation.Situation.ENGAGED, AiTask.Layer.ROUTINE)).is_false()
	assert_bool(set_of.layer_open(AiSituation.Situation.ALERT, AiTask.Layer.ROUTINE)).is_true()


func test_the_brain_has_no_branch_for_a_behaviour() -> void:
	var text := FileAccess.get_file_as_string(BRAIN)
	var named: Array[String] = []
	for file in DirAccess.get_files_at(STOCK):
		if not file.ends_with(".gd") or NOT_TASKS.has(file):
			continue
		var script := load(STOCK + file) as Script
		var class_label := script.get_global_name()
		if text.contains(String(class_label)):
			named.append(class_label)
	assert_array(named).is_empty()


func test_each_stock_task_declares_its_channels_and_contract() -> void:
	var expected := {
		"AiWait": [0, AiTask.Layer.ROUTINE],
		"AiGoTo": [AiTask.Channel.MOVE, AiTask.Layer.ROUTINE],
		"AiFollow": [AiTask.Channel.MOVE, AiTask.Layer.ROUTINE],
		"AiPatrol": [AiTask.Channel.MOVE, AiTask.Layer.ROUTINE],
		"AiWander": [AiTask.Channel.MOVE, AiTask.Layer.ROUTINE],
		"AiLookAt": [AiTask.Channel.LOOK, AiTask.Layer.RESPONSE],
		"AiLookAround": [AiTask.Channel.LOOK, AiTask.Layer.RESPONSE],
		"AiInvestigate": [AiTask.Channel.MOVE | AiTask.Channel.LOOK, AiTask.Layer.RESPONSE],
		"AiSearch": [AiTask.Channel.MOVE | AiTask.Channel.LOOK, AiTask.Layer.RESPONSE],
		"AiChase": [AiTask.Channel.MOVE | AiTask.Channel.LOOK, AiTask.Layer.RESPONSE],
		"AiAttack": [7, AiTask.Layer.RESPONSE],
		"AiTakeCover": [7, AiTask.Layer.RESPONSE],
		"AiFlee": [AiTask.Channel.MOVE, AiTask.Layer.RESPONSE],
		"AiCower": [AiTask.Channel.MOVE | AiTask.Channel.LOOK, AiTask.Layer.RESPONSE],
		"AiGuard": [AiTask.Channel.MOVE | AiTask.Channel.LOOK, AiTask.Layer.DEFAULT],
		"AiUseObject": [AiTask.Channel.MOVE | AiTask.Channel.ACTION, AiTask.Layer.ORDER],
		"AiTraverseLink": [AiTask.Channel.MOVE, AiTask.Layer.REACTION],
		"AiSay": [AiTask.Channel.SPEAK, AiTask.Layer.RESPONSE],
	}
	var seen := 0
	for file in DirAccess.get_files_at(STOCK):
		if not file.ends_with(".gd") or NOT_TASKS.has(file):
			continue
		var script := load(STOCK + file) as GDScript
		var task := script.new() as AiStockTask
		var label := String(script.get_global_name())
		assert_bool(expected.has(label)).override_failure_message(label + " not pinned").is_true()
		assert_int(task.channels).override_failure_message(label).is_equal(expected[label][0])
		assert_int(task.layer).override_failure_message(label).is_equal(expected[label][1])
		assert_str(String(task.id)).override_failure_message(label).is_not_empty()
		assert_array(task.authoring_problems()).override_failure_message(label).is_empty()
		seen += 1
	assert_int(seen).is_equal(expected.size())


func _stock_without_row(used: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	for file in DirAccess.get_files_at(STOCK):
		if file.ends_with(".gd") and not NOT_TASKS.has(file) and not used.has(file):
			missing.append(file)
	return missing

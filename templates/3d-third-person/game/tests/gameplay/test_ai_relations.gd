# The relationships table: it is asymmetric, bands change with hysteresis (a wobble on a line
# changes the band once), the lines are editable, current values drift back to their base, a row
# edited live moves the base, and a client rebuilds the table from the bytes a server sends. The
# shipped table has the four factions and the events.
extends GdUnitTestSuite

const RELATIONS := "res://gameplay/ai/relations/ai_relations.tres"


func _table() -> AiRelations:
	return (load(RELATIONS) as AiRelations).copy()


func test_the_shipped_table_has_the_four_factions_and_events() -> void:
	var relations := _table()
	for id in [&"player", &"enemy", &"ally", &"civilian"]:
		assert_int(relations.index_of(id)).is_greater_equal(0)
	for id in [&"attack", &"kill", &"help", &"trespass"]:
		assert_object(relations.event(id)).is_not_null()
	assert_bool(relations.is_hostile(&"enemy", &"player")).is_true()
	assert_bool(relations.is_hostile(&"enemy", &"ally")).is_true()
	assert_int(relations.band(&"ally", &"player")).is_equal(AiRelations.Band.ALLIED)
	assert_int(relations.band(&"civilian", &"civilian")).is_equal(AiRelations.Band.ALLIED)
	assert_int(relations.band(&"enemy", &"civilian")).is_equal(AiRelations.Band.UNFRIENDLY)
	assert_bool(relations.faction(&"player").hurts_friends).is_true()
	assert_bool(relations.faction(&"ally").hurts_friends).is_false()


func test_the_table_is_asymmetric() -> void:
	var relations := _table()
	assert_float(relations.attitude(&"civilian", &"enemy")).is_equal(-50.0)
	assert_float(relations.attitude(&"enemy", &"civilian")).is_equal(-30.0)
	relations.set_attitude(&"ally", &"civilian", -100.0)
	assert_bool(relations.is_hostile(&"ally", &"civilian")).is_true()
	assert_bool(relations.is_hostile(&"civilian", &"ally")).is_false()
	assert_float(relations.attitude(&"civilian", &"ally")).is_equal(30.0)


func test_a_faction_not_in_the_table_is_at_the_default() -> void:
	var relations := _table()
	assert_int(relations.index_of(&"neutral")).is_equal(-1)
	assert_float(relations.attitude(&"neutral", &"enemy")).is_equal(0.0)
	assert_int(relations.band(&"enemy", &"neutral")).is_equal(AiRelations.Band.NEUTRAL)


func test_bands_enter_at_the_line_and_leave_past_the_hysteresis() -> void:
	var relations := _table()
	var changes: Array = []
	relations.band_changed.connect(func(a, b, from, to): changes.append([a, b, from, to]))
	relations.set_attitude(&"civilian", &"player", -59.0)
	assert_int(relations.band(&"civilian", &"player")).is_equal(AiRelations.Band.UNFRIENDLY)
	relations.set_attitude(&"civilian", &"player", -60.0)
	assert_int(relations.band(&"civilian", &"player")).is_equal(AiRelations.Band.HOSTILE)
	var wobble: Array[float] = [-58.0, -61.0, -45.0, -62.0, -41.0, -59.0]
	for value in wobble:
		relations.set_attitude(&"civilian", &"player", value)
		assert_int(relations.band(&"civilian", &"player")).is_equal(AiRelations.Band.HOSTILE)
	relations.set_attitude(&"civilian", &"player", -39.0)
	assert_int(relations.band(&"civilian", &"player")).is_equal(AiRelations.Band.UNFRIENDLY)
	(
		assert_array(changes)
		. is_equal(
			[
				[&"civilian", &"player", AiRelations.Band.FRIENDLY, AiRelations.Band.UNFRIENDLY],
				[&"civilian", &"player", AiRelations.Band.UNFRIENDLY, AiRelations.Band.HOSTILE],
				[&"civilian", &"player", AiRelations.Band.HOSTILE, AiRelations.Band.UNFRIENDLY],
			]
		)
	)


func test_the_lines_and_the_hysteresis_are_editable() -> void:
	var relations := _table()
	relations.hostile_at = -80
	relations.hysteresis = 5
	relations.set_attitude(&"civilian", &"player", -70.0)
	assert_int(relations.band(&"civilian", &"player")).is_equal(AiRelations.Band.UNFRIENDLY)
	relations.set_attitude(&"civilian", &"player", -80.0)
	assert_int(relations.band(&"civilian", &"player")).is_equal(AiRelations.Band.HOSTILE)
	relations.set_attitude(&"civilian", &"player", -76.0)
	assert_int(relations.band(&"civilian", &"player")).is_equal(AiRelations.Band.HOSTILE)
	relations.set_attitude(&"civilian", &"player", -74.0)
	assert_int(relations.band(&"civilian", &"player")).is_equal(AiRelations.Band.UNFRIENDLY)


func test_a_jump_across_neutral_takes_the_new_band_at_once() -> void:
	var relations := _table()
	relations.set_attitude(&"civilian", &"player", -90.0)
	relations.set_attitude(&"civilian", &"player", 30.0)
	assert_int(relations.band(&"civilian", &"player")).is_equal(AiRelations.Band.FRIENDLY)
	relations.set_attitude(&"civilian", &"player", 90.0)
	relations.set_attitude(&"civilian", &"player", 45.0)
	assert_int(relations.band(&"civilian", &"player")).is_equal(AiRelations.Band.ALLIED)
	relations.set_attitude(&"civilian", &"player", 39.0)
	assert_int(relations.band(&"civilian", &"player")).is_equal(AiRelations.Band.FRIENDLY)


func test_current_values_drift_back_to_their_base() -> void:
	var relations := _table()
	relations.recovery_per_minute = 30.0
	relations.add_attitude(&"civilian", &"player", -60.0)
	assert_float(relations.attitude(&"civilian", &"player")).is_equal(-40.0)
	relations.recover(60.0)
	assert_float(relations.attitude(&"civilian", &"player")).is_equal(-10.0)
	relations.recover(600.0)
	assert_float(relations.attitude(&"civilian", &"player")).is_equal(20.0)
	assert_float(relations.base_attitude(&"civilian", &"player")).is_equal(20.0)
	relations.set_attitude(&"enemy", &"player", -80.0)
	relations.recover(20.0)
	assert_float(relations.attitude(&"enemy", &"player")).is_equal(-90.0)


func test_an_edit_to_a_row_moves_the_base_live() -> void:
	var relations := _table()
	relations.add_attitude(&"ally", &"civilian", -10.0)
	var row := relations.faction(&"ally").attitudes.duplicate()
	row[&"civilian"] = -80
	relations.faction(&"ally").attitudes = row
	assert_float(relations.base_attitude(&"ally", &"civilian")).is_equal(-80.0)
	assert_float(relations.attitude(&"ally", &"civilian")).is_equal(-90.0)
	assert_bool(relations.is_hostile(&"ally", &"civilian")).is_true()


func test_a_client_rebuilds_the_table_from_the_bytes() -> void:
	var server := _table()
	var client := _table()
	server.set_attitude(&"ally", &"player", -70.0)
	server.set_attitude(&"civilian", &"enemy", -100.0)
	client.apply(server.encode_all())
	assert_float(client.attitude(&"ally", &"player")).is_equal(-70.0)
	assert_bool(client.is_hostile(&"civilian", &"enemy")).is_true()
	var sent: Array[PackedByteArray] = []
	# The lambda holds the server: disconnect it, or the pair keeps each other alive past the test.
	var send := func(i: int, j: int) -> void: sent.append(server.encode_change(i, j))
	server.attitude_changed.connect(send)
	server.add_attitude(&"ally", &"player", 25.0)
	server.attitude_changed.disconnect(send)
	assert_int(sent.size()).is_equal(1)
	assert_int(sent[0].size()).is_equal(3)
	client.apply(sent[0])
	assert_float(client.attitude(&"ally", &"player")).is_equal(-45.0)
	assert_int(server.encode_all().size()).is_equal(1 + 16)


# The inspector contract of every part (the kit's `third-person/ai-relations.md#relations` lists
# the same): a new export fails here until its default is pinned.
func test_the_defaults_are_pinned() -> void:
	var no_factions: Array[AiFaction] = []
	var no_events: Array[AiRelationEvent] = []
	var no_attitudes: Dictionary[StringName, int] = {}
	var factions: AiFactions = auto_free(AiFactions.new())
	var member: AiFactionMember = auto_free(AiFactionMember.new())
	var parts := [
		[
			AiRelations.new(),
			{
				&"factions": no_factions,
				&"events": no_events,
				&"default_attitude": 0,
				&"hostile_at": -60,
				&"unfriendly_at": -20,
				&"friendly_at": 20,
				&"allied_at": 60,
				&"hysteresis": 20,
				&"recovery_per_minute": 10.0,
			}
		],
		[
			AiFaction.new(),
			{
				&"id": &"faction",
				&"color": Color(0.8, 0.8, 0.8),
				&"hurts_friends": false,
				&"attitudes": no_attitudes,
			}
		],
		[AiRelationEvent.new(), {&"id": &"attack", &"delta": -30, &"witness": 0}],
		[
			factions,
			{
				&"relations": null,
				&"show_bands": false,
				&"band_refresh_seconds": 0.25,
				&"band_colors": factions.band_colors,
				&"player_group": &"player",
			}
		],
		[member, {&"faction": &"", &"reports_events": true, &"band_marker": null}],
	]
	for part in parts:
		assert_array(ExportPins.differences(part[0], part[1])).is_empty()
		assert_array(ExportPins.wrong_values(part[0], part[1])).is_empty()
	assert_int(factions.band_colors.size()).is_equal(AiRelations.BAND_NAMES.size())

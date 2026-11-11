# The situation machine of an AI character: rising is at once, calming down or turning sideways
# waits for the minimum dwell (the latest request wins), awareness crosses its lines with
# hysteresis, death is at once and only getting up leaves it.
extends GdUnitTestSuite

const S := AiSituation.Situation

var _changes: Array = []


func _machine() -> AiSituation:
	_changes.clear()
	var machine := AiSituation.new()
	machine.dwell = 1.0
	machine.suspicious_at = 0.3
	machine.hysteresis = 0.1
	machine.changed.connect(func(now: int, _was: int) -> void: _changes.append(now))
	return machine


func test_rising_is_at_once() -> void:
	var machine := _machine()
	machine.request(S.ALERT)
	assert_int(machine.current).is_equal(S.ALERT)
	machine.request(S.ENGAGED)
	assert_int(machine.current).is_equal(S.ENGAGED)
	assert_array(_changes).is_equal([S.ALERT, S.ENGAGED])


func test_calming_down_waits_for_the_dwell_and_the_latest_request_wins() -> void:
	var machine := _machine()
	machine.request(S.ENGAGED)
	machine.advance(0.4)
	machine.request(S.ALERT)
	assert_int(machine.current).is_equal(S.ENGAGED)
	assert_bool(machine.has_pending()).is_true()
	machine.advance(0.3)
	machine.request(S.SUSPICIOUS)
	machine.advance(0.29)
	assert_int(machine.current).is_equal(S.ENGAGED)
	machine.advance(0.02)
	assert_int(machine.current).is_equal(S.SUSPICIOUS)
	assert_array(_changes).is_equal([S.ENGAGED, S.SUSPICIOUS])


func test_turning_sideways_waits_for_the_dwell() -> void:
	var machine := _machine()
	machine.request(S.ENGAGED)
	machine.request(S.FLEEING)
	assert_int(machine.current).is_equal(S.ENGAGED)
	machine.advance(1.0)
	assert_int(machine.current).is_equal(S.FLEEING)


func test_a_wobble_inside_the_dwell_changes_it_once() -> void:
	var machine := _machine()
	machine.request(S.ALERT)
	for _i in 9:
		machine.advance(0.1)
		machine.request(S.SUSPICIOUS)
		machine.request(S.ALERT)
	assert_array(_changes).is_equal([S.ALERT])
	assert_bool(machine.has_pending()).is_false()


func test_awareness_crosses_its_lines_with_hysteresis() -> void:
	var machine := _machine()
	machine.feed_awareness(0.29)
	assert_int(machine.current).is_equal(S.UNAWARE)
	machine.feed_awareness(0.3)
	assert_int(machine.current).is_equal(S.SUSPICIOUS)
	machine.advance(2.0)
	machine.feed_awareness(0.25)
	assert_int(machine.current).is_equal(S.SUSPICIOUS)
	machine.feed_awareness(0.19)
	assert_int(machine.current).is_equal(S.UNAWARE)
	machine.feed_awareness(1.0)
	assert_int(machine.current).is_equal(S.ALERT)
	machine.advance(2.0)
	machine.feed_awareness(0.95)
	assert_int(machine.current).is_equal(S.ALERT)
	machine.feed_awareness(0.85)
	assert_int(machine.current).is_equal(S.SUSPICIOUS)


func test_awareness_leaves_an_engaged_character_alone() -> void:
	var machine := _machine()
	machine.request(S.ENGAGED)
	machine.advance(5.0)
	machine.feed_awareness(0.0)
	assert_int(machine.current).is_equal(S.ENGAGED)


func test_death_is_at_once_and_only_getting_up_leaves_it() -> void:
	var machine := _machine()
	machine.request(S.ENGAGED)
	machine.request(S.ALERT)
	machine.die()
	assert_int(machine.current).is_equal(S.DEAD)
	machine.advance(5.0)
	assert_int(machine.current).is_equal(S.DEAD)
	machine.request(S.ENGAGED)
	assert_int(machine.current).is_equal(S.DEAD)
	machine.revive()
	assert_int(machine.current).is_equal(S.UNAWARE)


func test_the_profile_sets_the_numbers() -> void:
	var machine := _machine()
	var profile := AiProfile.new()
	profile.situation_dwell = 2.5
	profile.suspicious_at = 0.4
	profile.awareness_hysteresis = 0.05
	machine.configure(profile)
	assert_float(machine.dwell).is_equal(2.5)
	assert_float(machine.suspicious_at).is_equal(0.4)
	assert_float(machine.hysteresis).is_equal(0.05)

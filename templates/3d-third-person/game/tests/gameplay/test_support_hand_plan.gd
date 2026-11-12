# The left hand's plan (kit #1051): `SupportHandPlan` alone, stepped by hand through the aim and a
# reload. The hand has one way on and off the weapon (fingers open where it holds, then the line
# out, then the clip's arm), so wherever the plan is: the hand has left its place only with its
# fingers opened, and the clip's arm has it only at the way's far end. The reload's phases follow
# the shares, and nothing but the two switches the plan hides jumps between two shares.
extends GdUnitTestSuite

## The step the reload is walked in: a tenth of a frame of the 1.6 s reload at 60 a second.
const STEP := 0.001
## The most an output may change over one `STEP`: the fastest part (the fingers opening, 0.02 of
## the clip) moves about a tenth of itself in a step, and a jump is the whole of it.
const SMOOTH := 0.2


func test_the_fingers_open_before_the_hand_leaves_and_the_arm_lets_go_last() -> void:
	var plan := SupportHandPlan.new()
	for weight: float in [1.0, 0.6, 0.3]:
		for aim: float in [1.0, 0.0]:
			for step in roundi(1.0 / STEP) + 1:
				plan.update(aim, weight, step * STEP)
				_assert_on_the_way(
					plan, "aim %.0f weight %.1f share %.3f" % [aim, weight, step * STEP]
				)


func test_aiming_brings_the_hand_in_along_the_same_way() -> void:
	var plan := SupportHandPlan.new()
	plan.update(0.0, 0.0, 0.0)
	assert_float(plan.arm).is_equal(0.0)
	for step in 101:
		plan.update(step / 100.0, 0.0, 0.0)
		_assert_on_the_way(plan, "aim %.2f" % (step / 100.0))
		assert_int(plan.phase).is_equal(SupportHandPlan.Phase.HELD)
	plan.update(SupportHandPlan.WAY_FROM, 0.0, 0.0)
	assert_float(plan.arm).is_equal(1.0)
	assert_float(plan.off).is_equal(1.0)
	assert_float(plan.opened).is_equal(1.0)
	plan.update(1.0, 0.0, 0.0)
	assert_float(plan.arm).is_equal(1.0)
	assert_float(plan.off).is_equal(0.0)
	assert_float(plan.opened).is_equal(0.0)


func test_a_reload_goes_through_its_phases_in_order() -> void:
	var plan := SupportHandPlan.new()
	var seen: Array[int] = []
	for step in 101:
		plan.update(1.0, 1.0, step / 100.0)
		if seen.is_empty() or seen[-1] != plan.phase:
			seen.append(plan.phase)
	(
		assert_array(seen)
		. is_equal(
			[
				SupportHandPlan.Phase.HELD,
				SupportHandPlan.Phase.LET_GO,
				SupportHandPlan.Phase.AWAY,
				SupportHandPlan.Phase.REACH,
				SupportHandPlan.Phase.INSERT,
				SupportHandPlan.Phase.SEATED,
				SupportHandPlan.Phase.RETURN,
				SupportHandPlan.Phase.HELD,
			]
		)
	)


func test_each_phase_has_the_hand_where_it_says() -> void:
	var plan := SupportHandPlan.new()
	# Held: on the weapon, closed.
	plan.update(1.0, 1.0, 0.0)
	assert_array([plan.arm, plan.off, plan.opened, plan.at_magazine]).is_equal([1.0, 0.0, 0.0, 0.0])
	# Away: the clip's own arm.
	plan.update(1.0, 1.0, lerpf(plan.leave.y, plan.reach.x, 0.5))
	assert_float(plan.arm).is_equal(0.0)
	# The reach starts a magazine's length down the line, the insert ends at the magazine.
	plan.update(1.0, 1.0, plan.reach.y)
	assert_array([plan.arm, plan.at_magazine, plan.down]).is_equal([1.0, 1.0, 1.0])
	assert_float(plan.magazine_fingers).is_equal(1.0)
	plan.update(1.0, 1.0, lerpf(plan.insert.y, plan.back.x, 0.5))
	assert_array([plan.arm, plan.at_magazine, plan.down]).is_equal([1.0, 1.0, 0.0])
	assert_float(plan.opened).is_equal(0.0)
	# Down the way in is not the way back down: that part of `down` is 0 until the return, and
	# all of it once the hand has come down off the seated magazine (kit #1052).
	plan.update(1.0, 1.0, plan.reach.y)
	assert_float(plan.down_back).is_equal(0.0)
	var down_done := lerpf(plan.back.x, plan.back.y, SupportHandPlan.BACK_DOWN.y)
	plan.update(1.0, 1.0, down_done)
	assert_float(plan.down_back).is_equal_approx(SupportHandPlan.BACK_DOWN_SHARE, 0.0001)
	assert_float(plan.down).is_equal_approx(plan.down_back, 0.0001)
	# Half-way back the hand is off the magazine, at the way's far end, opened.
	var across_done := lerpf(plan.back.x, plan.back.y, SupportHandPlan.BACK_ACROSS.y)
	plan.update(1.0, 1.0, across_done)
	assert_array([plan.arm, plan.at_magazine, plan.off, plan.opened]).is_equal([1.0, 0.0, 1.0, 1.0])
	assert_float(plan.magazine_fingers).is_equal(0.0)
	# And held again at the return's end.
	plan.update(1.0, 1.0, plan.back.y)
	assert_array([plan.arm, plan.off, plan.opened, plan.at_magazine]).is_equal([1.0, 0.0, 0.0, 0.0])


func test_nothing_jumps_between_two_shares_of_a_reload() -> void:
	var plan := SupportHandPlan.new()
	var last := {}
	for step in roundi(1.0 / STEP) + 1:
		plan.update(1.0, 1.0, step * STEP)
		var now := {
			"arm": plan.arm,
			"off": plan.off,
			"down": plan.down * plan.at_magazine * plan.arm,
			# The fingers: the magazine pose's weight switches where the opened pose hides it,
			# and the opened pose's while the clip's arm has the hand.
			"opened": plan.opened * plan.arm,
			"closed on the magazine": plan.magazine_fingers * (1.0 - plan.opened) * plan.arm,
			# The place: the marker switches while the clip's arm has the hand.
			"at the magazine": plan.at_magazine * plan.arm,
			# The fingers on the new magazine (kit #1052): the hold takes them from the clip
			# (`fingers`), opened, and closes them on it.
			"holding the magazine": plan.carry * (1.0 - plan.carry_open) * plan.fingers,
			"opened for the magazine": plan.carry * plan.carry_open * plan.fingers,
		}
		for key: String in last:
			var change := absf(now[key] - last[key])
			(
				assert_float(change)
				. override_failure_message(
					"%s jumps by %.2f at share %.3f" % [key, change, step * STEP]
				)
				. is_less(SMOOTH)
			)
		last = now


# The magazines (kit #1052): the pistol's own is in the grip until the old one drops and again
# once the new one is in; the new one is in the hand from the belt to the end of the way in, with
# the fingers closed on it from the belt until the grip comes down over them; never both, and a
# reload cut short (no weight) leaves the pistol whole.
func test_the_magazines_follow_the_reload() -> void:
	var plan := SupportHandPlan.new()
	for step in roundi(1.0 / STEP) + 1:
		var share := step * STEP
		plan.update(0.0, 1.0, share)
		var tag := "share %.3f" % share
		(
			assert_bool(plan.magazine_in_gun and plan.magazine_in_hand)
			. override_failure_message("%s: a magazine in the grip and one in the hand" % tag)
			. is_false()
		)
		assert_bool(plan.magazine_in_gun).override_failure_message(tag).is_equal(
			share < plan.drop or share >= plan.insert.y
		)
		assert_bool(plan.magazine_in_hand).override_failure_message(tag).is_equal(
			share >= plan.take and share < plan.insert.y
		)
		if share >= plan.take + SupportHandPlan.TAKE_CLOSE and share <= plan.insert.x:
			(
				assert_float(plan.carry * (1.0 - plan.carry_open))
				. override_failure_message(
					"%s: the fingers let the magazine go before the way in" % tag
				)
				. is_equal(1.0)
			)
		if not plan.magazine_in_hand:
			(
				assert_float(plan.carry * (1.0 - plan.carry_open))
				. override_failure_message("%s: the fingers hold no magazine" % tag)
				. is_equal(0.0)
			)
		plan.update(0.0, 0.0, share)
		(
			assert_bool(plan.magazine_in_gun and not plan.magazine_in_hand)
			. override_failure_message(
				"%s: a reload cut short leaves the pistol without its magazine" % tag
			)
			. is_true()
		)
		assert_float(plan.carry).is_equal(0.0)
		assert_float(plan.fingers).is_equal(0.0)


# The one way: the hand is off its place only with the fingers opened, and the hold's arm gives
# it to the clip only at the way's far end (the magazine's places are the hold's own).
func _assert_on_the_way(plan: SupportHandPlan, tag: String) -> void:
	if plan.at_magazine > 0.0:
		return
	if plan.off > 0.0:
		(
			assert_float(plan.opened)
			. override_failure_message("%s: the hand leaves with its fingers closed" % tag)
			. is_equal(1.0)
		)
	if plan.arm < 1.0:
		(
			assert_float(plan.off)
			. override_failure_message("%s: the clip's arm takes the hand from near the gun" % tag)
			. is_equal(1.0)
		)

# A death just after the animation throttle hands a character back to every-frame updates leaves
# as any other death does (gdstudio #1388). While a far AI is throttled its ragdoll stops sampling
# the animated pose; a hit hands the tree back, and the sampler kept the pose from before the
# throttle took over, seconds old: a death in the next tick read that stale pair as one tick of
# motion and gave its bones the wrong speed.
extends GdUnitTestSuite

## The far AI's run, m/s, and how far it stands from the camera (the Reduced tier, and past the
## throttle's `far_distance`: it animates every few frames).
const RUN := 4.0
const FAR := 35.0
## A body knocked down: its fastest bone (as `test_death_push.gd`), on top of the run.
const FASTEST := 9.0
## Ticks the AI runs before the hit: past the throttle's first frames and into the run.
const HIT_TICK := 40


# Answers the arena with a director, its throttle and a camera watching from 3 m behind the viewer.
func _arena() -> AiArena:
	var arena := auto_free(AiArena.new()) as AiArena
	add_child(arena)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.6, 21.0)
	arena.add_child(camera)
	arena.viewer.position = Vector3(0.0, 0.0, 18.0)
	var director := AiDirector.new()
	director.name = "AiDirector"
	var throttle := AiAnimationThrottle.new()
	throttle.camera = camera
	director.add_child(throttle)
	director.animation_throttle = throttle
	arena.director = director
	arena.add_child(director)
	return arena


# A far AI runs at the camera while throttled; a small hit hands its tree back, and `delay` ticks
# later (0: in the same tick as the hit) a big one kills it. Answers the ragdoll's mean speed and
# its fastest bone in the tick after the death, or empty when the setup did not hold.
func _kill_after_hand_back(arena: AiArena, x: float, delay: int) -> Array:
	var throttle := arena.director.animation_throttle
	var grunt := arena.add_character(Vector3(x, 0.0, 18.0 - FAR))
	grunt.ragdoll_body.max_active = 32
	var controller := grunt.controller as AiController
	var throttled := false
	for tick in HIT_TICK + delay + 1:
		if not grunt.is_dead():
			controller.walk_direction = Vector3.BACK
			controller.walk_strength = 1.0
		var chest := grunt.global_position + Vector3.UP * 1.3
		if tick == HIT_TICK:
			throttled = throttle.period_of(grunt) > 1
			grunt.take_hit(HitRecord.shot(10.0, &"chest", &"spine_03", chest, Vector3.FORWARD, 0.0))
		if tick == HIT_TICK + delay:
			assert_int(throttle.period_of(grunt)).is_equal(1)
			assert_float(grunt.velocity.length()).is_equal_approx(RUN, 0.2)
			grunt.take_hit(
				HitRecord.shot(500.0, &"chest", &"spine_03", chest, Vector3.FORWARD, 0.0)
			)
		await get_tree().physics_frame
	if not throttled or not grunt.ragdoll_body.is_limp():
		return []
	var mass := 0.0
	var momentum := Vector3.ZERO
	var fastest := 0.0
	for entry: Dictionary in CharacterRagdoll.BODIES:
		var bone := grunt.ragdoll_body.body(entry.bone)
		mass += bone.mass
		momentum += bone.linear_velocity * bone.mass
		fastest = maxf(fastest, bone.linear_velocity.length())
	return [(momentum / mass).length(), fastest]


# Killed in the tick of the hand-back and in each of the two after it, the body leaves at its run's
# speed and no bone flies.
func test_a_death_just_after_the_hand_back_leaves_at_the_run_speed() -> void:
	var arena := _arena()
	for delay in 3:
		var seen := await _kill_after_hand_back(arena, 4.0 * delay - 4.0, delay)
		var what := "killed %d ticks after the hand-back" % delay
		(
			assert_array(seen)
			. override_failure_message("%s: not throttled or not limp" % what)
			. is_not_empty()
		)
		if seen.is_empty():
			continue
		assert_float(seen[0]).override_failure_message("%s: %.2f m/s" % [what, seen[0]]).is_between(
			RUN * 0.8, RUN * 1.2
		)
		(
			assert_float(seen[1])
			. override_failure_message("%s: a bone at %.2f m/s" % [what, seen[1]])
			. is_less(FASTEST + RUN)
		)

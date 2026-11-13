# A kill knocks a body down; it never launches it (gdstudio #1343). In the maintainer's playtest a
# rifle kill flung an enemy, which landed with a leg up. Two causes, each with a case here:
# - a far AI (the director's Reduced tier, stepped every fourth tick with the missed time) that a
#   hit had made animate every frame left at the speed its pose moved over the last tick in the
#   world: on a step tick four ticks of its run as one, 16 m/s for a 4 m/s run. Far targets are
#   the rifle's;
# - the push of a kill, and of a hit on the lying body, was a share of the shot's strength
#   whatever the part weighed: a kill on a forearm threw it at 22 to 26 m/s, on a shin at 8 to
#   12, and a rifle sprays limbs and keeps firing into the falling body.
# Each weapon of the template kills a standing target with one shot on each part, and with the
# trigger held; the fastest bone and the hips (their swing past the cone joint's limit) are watched.
extends GdUnitTestSuite

const WEAPON := "res://gameplay/weapon/weapon.tscn"
const WEAPONS: Array[String] = [
	"res://gameplay/weapon/pistol.tres", "res://gameplay/weapon/rifle.tres"
]
const ZONES: Array[StringName] = [
	&"head", &"chest", &"pelvis", &"arm_r", &"forearm_l", &"thigh_l", &"shin_r"
]
const HIPS: Array[StringName] = [&"thigh_l", &"thigh_r"]
const WATCH_TICKS := 60
## A body knocked down: its fastest bone over the first second (a head falling from standing
## height reaches 6 m/s, a pistol kill on the chest read 5.2).
const FASTEST := 9.0
## A hip's swing past its cone's limit, degrees: a joint is a soft stop (test_ragdoll_cones.gd
## allows 25 past a person's range); the deaths here read 0 to 5.
const HIP_SLACK := 10.0
## The far AI's run, m/s, and how far it stands from the player (the Reduced tier: 25 to 70 m).
const RUN := 4.0
const FAR := 35.0

var _arena: PlayArena
var _weapon: Weapon
var _muzzle: Marker3D


func before_test() -> void:
	_arena = auto_free(ImpactShots.world(self))
	_weapon = load(WEAPON).instantiate() as Weapon
	_weapon.self_ticking = false
	_arena.add_child(_weapon)
	_muzzle = Marker3D.new()
	_arena.add_child(_muzzle)
	_weapon.muzzle = _muzzle


func after_test() -> void:
	AudioDrain.stop_all(_arena)


# The swing of `entry`'s cone joint from its centre, in degrees (as `RagdollStage.cone_angles`).
func _swing(ragdoll: CharacterRagdoll, entry: Dictionary) -> float:
	var skeleton := ragdoll.model.skeleton()
	var parent: StringName = ragdoll._parent_body(skeleton, entry.bone)
	var rest := ragdoll.rest_body(parent).basis.inverse() * ragdoll.rest_body(entry.bone).basis
	var now := ragdoll.body(parent).global_basis.inverse() * ragdoll.body(entry.bone).global_basis
	var centre := Basis.from_euler(entry.centre * (PI / 180.0))
	var q := Quaternion((centre.inverse() * rest.inverse() * now).orthonormalized())
	if q.w < 0.0:
		q = -q
	var twist := Quaternion(q.x, 0.0, 0.0, q.w)
	twist = twist.normalized() if twist.length() > 0.0001 else Quaternion.IDENTITY
	return rad_to_deg((q * twist.inverse()).get_angle())


# A standing target at `spot`, its pose held still, which always gets its ragdoll (the cap would
# give the fifth its death clip).
func _target(spot: Vector3) -> Character:
	var target := HitRange.target(_arena, spot)
	target.ragdoll_body.max_active = 32
	await InputSim.ticks(get_tree(), 6)
	HitRange.freeze(target)
	await InputSim.ticks(get_tree(), 2)
	return target


func _arm(path: String, spread: bool) -> void:
	_weapon.definition = (load(path) as WeaponDef).duplicate()
	if not spread:
		_weapon.definition.spread = 0.0
	_weapon.make_ready()


# Watches `ragdoll` for one tick: the fastest bone so far and the hips' worst swing past the limit
# go into `seen` ([speed, bone, degrees]).
func _watch(ragdoll: CharacterRagdoll, seen: Array) -> void:
	for entry: Dictionary in CharacterRagdoll.BODIES:
		var speed := ragdoll.body(entry.bone).linear_velocity.length()
		if speed > seen[0]:
			seen[0] = speed
			seen[1] = entry.bone
		if entry.bone in HIPS:
			seen[2] = maxf(seen[2], _swing(ragdoll, entry) - entry.swing)


# Kills a target at `spot` with one shot of `path` on `zone`, then watches it for a second;
# answers [fastest speed, its bone, hips past the limit] or empty when the shot did not kill.
func _one_shot(path: String, zone: StringName, spot: Vector3) -> Array:
	var target: Character = await _target(spot)
	var line := HitRange.line_to(target, HitRange.zones_of(target).zone(zone))
	if line.is_empty():
		return []
	Health.of(target).value = 1.0
	_arm(path, false)
	_muzzle.global_position = line[0]
	_weapon.pull(line[0], line[1])
	for _tick in 30:
		if target.is_dead():
			break
		await get_tree().physics_frame
	if not target.is_dead():
		return []
	var seen := [0.0, &"", 0.0]
	for _tick in WATCH_TICKS:
		await get_tree().physics_frame
		_watch(target.ragdoll_body, seen)
	return seen


func _each_part(path: String) -> void:
	var x := -18.0
	for zone in ZONES:
		var seen := await _one_shot(path, zone, Vector3(x, 0.0, -4.0))
		x += 6.0
		var what := "%s on the %s" % [path.get_file(), zone]
		assert_array(seen).override_failure_message("%s did not kill" % what).is_not_empty()
		if seen.is_empty():
			continue
		(
			assert_float(seen[0])
			. override_failure_message("%s: %s at %.1f m/s" % [what, seen[1], seen[0]])
			. is_less(FASTEST)
		)
		(
			assert_float(seen[2])
			. override_failure_message("%s: a hip %.1f degrees past its limit" % [what, seen[2]])
			. is_less(HIP_SLACK)
		)


func test_a_pistol_kill_on_any_part_knocks_the_body_down() -> void:
	await _each_part(WEAPONS[0])


func test_a_rifle_kill_on_any_part_knocks_the_body_down() -> void:
	await _each_part(WEAPONS[1])


# The trigger held on a target at full health from 8 m in front, its spread on: the rounds before
# the kill, the kill and a second more into the falling body.
func test_a_held_trigger_into_a_falling_body_never_flings_it() -> void:
	for index in WEAPONS.size():
		var spot := Vector3(-12.0 + 12.0 * index, 0.0, -10.0)
		var target: Character = await _target(spot)
		_arm(WEAPONS[index], true)
		var from := spot + Vector3(0.0, 1.3, 8.0)
		_muzzle.global_position = from
		var seen := [0.0, &"", 0.0]
		var killed_at := -1
		for tick in 150:
			_weapon.tick(1.0 / 60.0)
			var aim := spot + Vector3.UP * 1.3
			if target.is_dead():
				aim = target.ragdoll_body.body(&"spine_03").global_position
			if killed_at < 0 or tick - killed_at < 60:
				_weapon.pull(from, (aim - from).normalized())
			await get_tree().physics_frame
			if target.is_dead():
				killed_at = tick if killed_at < 0 else killed_at
				_watch(target.ragdoll_body, seen)
		var what := WEAPONS[index].get_file()
		assert_int(killed_at).override_failure_message("%s did not kill" % what).is_greater(-1)
		(
			assert_float(seen[0])
			. override_failure_message("%s held: %s at %.1f m/s" % [what, seen[1], seen[0]])
			. is_less(FASTEST)
		)
		assert_float(seen[2]).is_less(HIP_SLACK)


# A far AI running toward the player, hit (so it animates every frame for a while), then killed on
# each tick of the director's step cycle: the body leaves at its run's speed every time.
func test_a_far_running_ai_killed_on_any_tick_leaves_at_its_speed() -> void:
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
	for phase in director.reduced_step_ticks * 2:
		var grunt := arena.add_character(Vector3(4.0 * phase - 14.0, 0.0, 18.0 - FAR))
		grunt.ragdoll_body.max_active = 32
		var controller := grunt.controller as AiController
		for tick in 71 + phase:
			if not grunt.is_dead():
				controller.walk_direction = Vector3.BACK
				controller.walk_strength = 1.0
			var chest := grunt.global_position + Vector3.UP * 1.3
			if tick == 40:
				grunt.take_hit(
					HitRecord.shot(10.0, &"chest", &"spine_03", chest, Vector3.FORWARD, 0.0)
				)
			elif tick == 70 + phase:
				assert_int(grunt.tier).is_equal(AiDirector.Tier.REDUCED)
				assert_float(grunt.velocity.length()).is_equal_approx(RUN, 0.2)
				grunt.take_hit(
					HitRecord.shot(500.0, &"chest", &"spine_03", chest, Vector3.FORWARD, 0.0)
				)
			await get_tree().physics_frame
		assert_bool(grunt.is_dead()).is_true()
		assert_bool(grunt.ragdoll_body.is_limp()).is_true()
		var mass := 0.0
		var momentum := Vector3.ZERO
		var fastest := 0.0
		for entry: Dictionary in CharacterRagdoll.BODIES:
			var bone := grunt.ragdoll_body.body(entry.bone)
			mass += bone.mass
			momentum += bone.linear_velocity * bone.mass
			fastest = maxf(fastest, bone.linear_velocity.length())
		var speed := (momentum / mass).length()
		(
			assert_float(speed)
			. override_failure_message("killed on tick %d of the step: %.1f m/s" % [phase, speed])
			. is_between(RUN * 0.6, RUN * 1.4)
		)
		assert_float(fastest).is_less(FASTEST + RUN)

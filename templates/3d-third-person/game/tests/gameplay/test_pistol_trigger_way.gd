# The pistol's trigger finger on its way between the frame and the trigger with both hands on the
# gun (kit #1272): it has room all the way, on both mannequins, and the measure reads a finger
# that crosses a part of the gun as a crossing. The way at twentieths against the whole of both
# hands is `test_pistol_hold.gd`'s. Measured on the skinned mesh after the hold's modifiers ran
# (`HoldStage`, `HandContact`).
extends GdUnitTestSuite

const MODELS: Array[String] = ["female", "male"]
## The trigger finger's parts.
const TRIGGER_FINGER: Array[String] = ["index_base", "index_mid", "index_tip"]
## The equal parts of the trigger finger's way at which its room is measured, and how deep it may
## go into the gun or the left hand at any of them, in metres (kit #1272): the way has room, it
## does not rub the trigger guard at the limit (the way of kit #1273 went 1.9 mm into the guard's
## front strut on the male body, between the twentieths).
const TRIGGER_ROOM_STEPS := 100
const TRIGGER_ROOM := 0.001
## A line across the trigger guard's front strut, in the pistol's own space (metres): 40 mm up
## the gun, from ahead of the strut to behind it. The strut is a bar 8 mm thick.
const STRUT_FROM := Vector3(-0.100, 0.040, 0.0)
const STRUT_TO := Vector3(-0.080, 0.040, 0.0)

var _holder: Node3D


func before_test() -> void:
	_holder = auto_free(Node3D.new())
	add_child(_holder)


# The trigger finger has room on its way (kit #1272): at every hundredth, with both hands on the
# aimed pistol, no part of it is more than `TRIGGER_ROOM` into the gun (read through its
# thickness) or the left hand, on both mannequins. The way goes off the frame to the finger's own
# side, bends its last two bones there and drops them into the guard (`WeaponHold.trigger_way`).
func test_the_trigger_finger_has_room_on_its_way_to_the_trigger() -> void:
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		var deepest := Vector2(-INF, -INF)
		var at := Vector2.ZERO
		for step in TRIGGER_ROOM_STEPS + 1:
			var on_trigger := float(step) / TRIGGER_ROOM_STEPS
			stage.pose(CharacterClips.PISTOL_AIM, 0.16, 1.0)
			stage.hold.set(&"reload_weight", 1.0 - on_trigger)
			stage.hold.call(&"refresh")
			await stage.settle()
			var left := stage.contact.hand_skin("l")
			var parts := stage.contact.measure_through("r", TRIGGER_FINGER, left)
			for part: String in parts:
				var depth := -(parts[part] as Vector2)
				if depth.x > deepest.x:
					deepest.x = depth.x
					at.x = on_trigger
				if depth.y > deepest.y:
					deepest.y = depth.y
					at.y = on_trigger
		(
			assert_float(deepest.x)
			. override_failure_message(
				"%s: %.2f mm into the gun at %.2f of the way" % [model, deepest.x * 1e3, at.x]
			)
			. is_less_equal(TRIGGER_ROOM)
		)
		(
			assert_float(deepest.y)
			. override_failure_message(
				"%s: %.2f mm into the left hand at %.2f of the way" % [model, deepest.y * 1e3, at.y]
			)
			. is_less_equal(TRIGGER_ROOM)
		)
		stage.free()


# Depth into the gun is read against a part's thickness (kit #1272): across the trigger guard's
# front strut the nearest face reads at most half the bar (4 mm), and the measure through it reads
# the whole bar in its middle; near a face the two agree.
func test_a_point_through_the_trigger_guard_reads_the_guards_thickness() -> void:
	var stage := HoldStage.make(_holder, "female")
	await stage.settle()
	var deepest := 0.0
	var through := 0.0
	var shallow := 0.0
	var shallow_through := 0.0
	for step in 201:
		var point := stage.pistol.global_transform * STRUT_FROM.lerp(STRUT_TO, step / 200.0)
		var depth := -stage.contact.weapon_distance(point)
		var read := -stage.contact.weapon_through(point)
		if depth > deepest:
			deepest = depth
			through = read
		if depth > 0.0 and depth < 0.001 and shallow == 0.0:
			shallow = depth
			shallow_through = read
	assert_float(deepest).is_between(0.003, 0.0045)
	assert_float(through).is_greater(1.8 * deepest)
	assert_float(shallow).is_greater(0.0)
	assert_float(shallow_through).is_equal_approx(shallow, 1e-6)
	stage.free()

# Every finger of both hands on the rifle in the game itself (kit #1036): the player's own scene,
# its animation tree and the hold's modifiers as they run, driven by simulated keys and mouse,
# on both mannequins. In every state the rifle is carried in (standing, walking, sprinting,
# aiming, firing, crouched, crouched and aiming, walking crouched) no part of either hand is more
# than 2 mm inside the rifle and no part that holds it more than 5 mm off it (`HandContact`, the
# skinned mesh worked out from the bone poses after the modifiers ran). `test_rifle_hold.gd`
# poses the clips by hand on a stage; this suite measures what the player plays, blends and all.
# And the trigger finger's way between the receiver and the trigger, as the rifle comes up and
# goes down, keeps the finger within the hold's own 2 mm of the rifle at every hundredth of the
# raise (kit #1283; the straight way between the two poses went 20 to 24 mm into the magazine
# well and the trigger guard; `HandPoseWay`, `tools/hold/plan_trigger_way.py`).
extends GdUnitTestSuite

const RIFLE := "res://gameplay/weapon/rifle.tres"
const MALE := CharacterBodies.MALE
## The updates each state is held for before it is measured, and the updates between the samples.
const SETTLE := 30
const SAMPLE_GAP := 7
const SAMPLES := 3
## The steps of the rifle's way up at which the trigger finger is measured.
const RAISE_STEPS := 100
const INDEX: Array[String] = ["index_base", "index_mid", "index_tip"]

var _arena: PlayArena
var _player: Player
var _skeleton: Skeleton3D
var _contact: HandContact
var _hold: TwoHandHold
var _tag := ""
var _sampling := false
var _fails: Array[String] = []
var _measured := 0


func before_test() -> void:
	InputSim.release_all()
	_fails.clear()
	_measured = 0


func after_test() -> void:
	InputSim.release_all()
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


func test_every_finger_holds_the_rifle_in_every_state_on_the_female() -> void:
	await _walk_the_states("")


func test_every_finger_holds_the_rifle_in_every_state_on_the_male() -> void:
	await _walk_the_states(MALE)


# With `RIFLE_WAY_SWEEP` set to a file, each step's deepest part is written there (a run's
# `print()` reaches no log).
func test_the_trigger_finger_goes_round_the_guard_as_the_rifle_comes_up() -> void:
	var holder: Node3D = auto_free(Node3D.new())
	add_child(holder)
	var sweep := PackedStringArray()
	for model: String in HoldStage.MODELS:
		var stage := RifleStage.make_rifle(holder, model)
		var deepest := 0.0
		var deepest_at := 0.0
		for step in RAISE_STEPS + 1:
			var aim := float(step) / RAISE_STEPS
			stage.pose_rifle(CharacterClips.IDLE, 0.0, aim)
			await stage.settle()
			var parts := stage.contact.measure("r")
			var here := -INF
			for part in INDEX:
				here = maxf(here, -float(parts[part].distance))
				if -float(parts[part].distance) > deepest:
					deepest = -float(parts[part].distance)
					deepest_at = aim
			sweep.append("%s %.2f %.2f" % [model, aim, here * 1e3])
		(
			assert_float(deepest)
			. override_failure_message(
				(
					"%s: the index finger went %.1f mm into the rifle at %.2f of the way up"
					% [model, deepest * 1e3, deepest_at]
				)
			)
			. is_less_equal(HandContact.MAX_DEPTH)
		)
		stage.free()
	var report := OS.get_environment("RIFLE_WAY_SWEEP")
	if not report.is_empty():
		var file := FileAccess.open(report, FileAccess.WRITE)
		file.store_string("body aim deepest_mm\n" + "\n".join(sweep) + "\n")
		file.close()


# A player in an arena with the rifle out at the low ready, the mannequin `variant` (empty: the
# scene's own), then each state in turn, measured `SAMPLES` times once it has settled.
func _walk_the_states(variant: String) -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	if not variant.is_empty():
		_player.model.variant = load(variant) as PackedScene
	var view := Camera3D.new()
	view.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(view)
	view.make_current()
	await InputSim.ticks(get_tree(), 10)
	_player.loadout.give(load(RIFLE) as WeaponDef, 300)
	await InputSim.ticks(get_tree(), 60)
	var hold := _player.model.get_node("RifleHeld") as TwoHandHold
	_hold = hold
	assert_bool(hold.is_visible_in_tree()).is_true()
	_skeleton = _player.model.skeleton()
	_contact = HandContact.new(_skeleton)
	_contact.set_weapon(hold.find_child("Near", true, false) as Node3D)
	_skeleton.skeleton_updated.connect(_on_skeleton_updated)
	var states: Array[Array] = [
		["low ready", func() -> void: pass],
		["walking", func() -> void: InputSim.key(KEY_W, true)],
		["sprinting", func() -> void: InputSim.key(KEY_SHIFT, true)],
		["aiming", func() -> void: _only_aim()],
		["firing", func() -> void: InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)],
		["crouched", func() -> void: await _crouch()],
		["crouched, aiming", func() -> void: InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)],
		["crouched, walking", func() -> void: _crouched_walk()],
	]
	for state: Array in states:
		await (state[1] as Callable).call()
		await InputSim.ticks(get_tree(), SETTLE)
		for sample in SAMPLES:
			_tag = "%s %s #%d:" % ["female" if variant.is_empty() else "male", state[0], sample]
			_sampling = true
			await InputSim.ticks(get_tree(), SAMPLE_GAP)
	_skeleton.skeleton_updated.disconnect(_on_skeleton_updated)
	assert_int(_measured).is_equal(states.size() * SAMPLES)
	assert_bool(hold.is_visible_in_tree()).is_true()
	assert_array(_fails).override_failure_message("\n".join(_fails)).is_empty()


func _only_aim() -> void:
	InputSim.release_all()
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)


func _crouch() -> void:
	InputSim.release_all()
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_C, false)


func _crouched_walk() -> void:
	InputSim.release_all()
	InputSim.key(KEY_W, true)


# Measures both hands once a sample is asked for, in the update the modifiers made, where the
# bone poses and the rifle's place belong to the same frame.
func _on_skeleton_updated() -> void:
	if not _sampling:
		return
	_sampling = false
	_measured += 1
	_contact.snapshot()
	var right := _contact.measure("r")
	var raised := _hold.raised_amount()
	if raised > 0.0 and raised < 1.0:
		# The finger on its way to the trigger or back: in by no more than the hold's 2 mm, and
		# no contact asked.
		for part in INDEX:
			if -float(right[part].distance) > HandContact.MAX_DEPTH:
				_fails.append(
					(
						"%s r %s passing %.1f mm inside"
						% [_tag, part, -float(right[part].distance) * 1e3]
					)
				)
			right.erase(part)
	_fails.append_array(HandContact.failures(_tag + " r", right, RifleStage.RIFLE_RIGHT_CONTACTS))
	_fails.append_array(
		HandContact.failures(_tag + " l", _contact.measure("l"), RifleStage.RIFLE_LEFT_CONTACTS)
	)

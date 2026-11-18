# A slide's exit into the run blends from the drawn slide (gdstudio #1577): from a sprint the
# player slides and lets go of crouch after a few ticks (the body barely down) and later (laid back
# in the slide loop), running on or letting go of every key, with the pistol and the rifle on both
# bodies; through the exit and its hand-off no trunk joint moves further in one drawn update than
# it does in the crouch's own hand-off from a jog (#1570's bound), measured the same way in the
# same run. Read in `skeleton_updated` on every update, in the model's space, keys pressed as a
# player does; `GDS_SLIDE_TRACE` prints every update.
#
# Before the fix the exit clip always played from lying at its own pace: a slide let go after six
# ticks dropped the trunk to the floor and lifted it again, 0.15 m a tick (the bound is 0.09);
# from lying it rose 0.9 m in about a quarter of a second, at the bound; and the rifle gave the
# trunk back to its idle as the capsule stood (0.12 s), 0.13 to 0.23 m a tick.
extends GdUnitTestSuite

const RIFLE := "res://gameplay/weapon/rifle.tres"
## The trunk's joints read.
const TRUNK: Array[StringName] = [
	&"pelvis", &"spine_01", &"spine_02", &"spine_03", &"neck_01", &"Head"
]
## Ticks crouch is held from a sprint before it is let go: the body barely down, half way, laid
## back in the slide loop.
const HOLDS: Array[int] = [6, 12, 24, 48]
## Ticks read after crouch is let go (the stretched exit lasts 51 and hands over to the run).
const AFTER := 70
## The sprint before crouch is pressed.
const SPRINT := 45
## Updates after the body leaves the exit that still count: the hand-off to the run or its stop
## (whose own clip goes on after it).
const HAND_OFF := 8

var _arena: PlayArena
var _player: Player
var _skeleton: Skeleton3D
var _reading := false
# Measuring the crouch's own hand-off: every update counts.
var _crouching := false
var _last := PackedVector3Array()
var _most := 0.0
var _most_at := ""
var _trace := PackedStringArray()
# Updates read since the body left the exit (-1 while it has not).
var _after_exit := -1


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 25.0))
	await InputSim.ticks(get_tree(), 10)
	_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	await InputSim.ticks(get_tree(), 30)


func after_test() -> void:
	InputSim.release_all()
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


func test_the_slide_exit_blends_on_the_female_body() -> void:
	await _check_body("female", ["Pistol", "Rifle"])


func test_the_slide_exit_blends_on_the_male_body() -> void:
	_player.model.variant = load(CharacterBodies.MALE) as PackedScene
	await InputSim.ticks(get_tree(), 30)
	await _check_body("male", ["Pistol", "Rifle"])


func _check_body(body: String, weapons: Array) -> void:
	_skeleton = _player.model.skeleton()
	_skeleton.skeleton_updated.connect(_read)
	var problems: Array[String] = []
	# The bound is the crouch's hand-off with the pistol, the player's weapon, as #1570's matrix
	# reads it (the rifle's crouch moves the trunk less, 0.067 m a tick: it holds the upper body).
	await _hold("Pistol")
	var bound := await _crouch_bound()
	print("SLIDE EXIT %s: the crouch's hand-off %.3f m a tick" % [body, bound])
	for weapon: String in weapons:
		await _hold(weapon)
		for hold in HOLDS:
			for run_on: bool in [true, false]:
				var moved := await _slide(hold, run_on)
				var tag := (
					"%s %s, crouch %d ticks, %s"
					% [body, weapon, hold, "running on" if run_on else "keys let go"]
				)
				print("SLIDE EXIT %s: trunk %.3f m a tick (%s)" % [tag, moved, _most_at])
				if OS.get_environment("GDS_SLIDE_TRACE") != "":
					print("SLIDETRACE %s %s" % [tag, " ".join(_trace)])
				if moved > bound:
					problems.append(
						(
							"%s: %s moved %.3f m in a tick, over the crouch's %.3f"
							% [tag, _most_at, moved, bound]
						)
					)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


# Brings `weapon_name` out and waits for the switch to end.
func _hold(weapon_name: String) -> void:
	var slots := _player.loadout.slots
	for slot in slots.size():
		if slots[slot] != null and slots[slot].display_name == weapon_name:
			_player.loadout.select(slot)
	await InputSim.ticks(get_tree(), 60)
	assert_str(_player.weapon.definition.display_name).is_equal(weapon_name)


# The trunk's largest move a tick as the body crouches from a jog and stands again.
func _crouch_bound() -> float:
	await _start()
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 80)
	_begin()
	_crouching = true
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 40)
	InputSim.key(KEY_C, false)
	await InputSim.ticks(get_tree(), 50)
	_reading = false
	_crouching = false
	InputSim.release_all()
	return _most


# One slide from a sprint, crouch let go after `hold` ticks, running on (or every key let go);
# the trunk's largest move a tick from the let-go on.
func _slide(hold: int, run_on: bool) -> float:
	await _start()
	InputSim.key(KEY_W, true)
	InputSim.key(KEY_SHIFT, true)
	await InputSim.ticks(get_tree(), SPRINT)
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), hold)
	_begin()
	InputSim.key(KEY_C, false)
	if not run_on:
		InputSim.key(KEY_W, false)
		InputSim.key(KEY_SHIFT, false)
	await InputSim.ticks(get_tree(), AFTER)
	_reading = false
	InputSim.release_all()
	return _most


func _start() -> void:
	InputSim.release_all()
	await InputSim.ticks(get_tree(), 30)
	_player.teleport(Vector3(0.0, 0.0, 25.0), PI)
	await InputSim.ticks(get_tree(), 40)


func _begin() -> void:
	_last = PackedVector3Array()
	_most = 0.0
	_most_at = ""
	_trace.clear()
	_after_exit = -1
	_reading = true


# One update of the skeleton, after its modifiers: the trunk joints' largest move since the last.
func _read() -> void:
	if not _reading:
		return
	var places := PackedVector3Array()
	for joint in TRUNK:
		places.append(_skeleton.get_bone_global_pose(_skeleton.find_bone(joint)).origin)
	var animation := _player.get_node("Animation") as CharacterAnimation
	var state := animation.body_state()
	var most := 0.0
	if _last.size() == places.size():
		for index in places.size():
			var moved := places[index].distance_to(_last[index])
			most = maxf(most, moved)
			if moved > _most and _counts(state):
				_most = moved
				_most_at = "%s in %s" % [TRUNK[index], state]
	_last = places
	_trace.append("%.3f:%s" % [most, String(state).left(6)])


# Whether an update in `state` counts: the exit, the crouch (the bound), and the first
# `HAND_OFF` updates after the body leaves the exit, which hand over to the run or its stop.
func _counts(state: StringName) -> bool:
	if state == CharacterAnimation.SLIDE_EXIT or state == CharacterAnimation.CROUCH:
		_after_exit = 0
		return true
	if _after_exit >= 0:
		_after_exit += 1
		return _after_exit <= HAND_OFF
	return _crouching

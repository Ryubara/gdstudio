# The carried pistol holds one carry through a run (gdstudio #1577): walking, jogging and sprinting
# with turns of 90 and 180 degrees, a stop and a start, and an aim pressed and let go on the way, on
# both bodies. The gun hand (`hand_r`, in the chest's space: `spine_03`'s) never moves more than
# `HAND_STEP` or turns more than `HAND_TURN` in one drawn update while carried, and no more than
# `AIM_STEP` and `AIM_TURN` while the aim comes up and goes down (the aim's own blend, over the
# character's `aim_pose_time`); over each steady stretch of a gait (from `SETTLE` ticks after a key
# change) it stays in a band: its places within `BAND_PLACE` of each other and its turns within
# `BAND_TURN`. The rifle is held in both hands by its own hold and is read for the record. Keys
# pressed as a player does, read in `skeleton_updated`; `GDS_CARRY_TRACE` prints every update.
#
# Before the fix the arm followed the locomotion clips: a jog's stride turned the pistol 76 degrees
# (down by the thigh, then level forward), a sprint's 120 (up by the head), and the gait blend's dip
# on a turn and a reversal's look moved the hand 0.22 m and turned it 44 degrees in one update.
extends GdUnitTestSuite

const RIFLE := "res://gameplay/weapon/rifle.tres"
## The most the gun hand may move (metres) and turn (degrees) in one drawn update, carried and
## while the aim comes up or goes down.
const HAND_STEP := 0.08
const HAND_TURN := 12.0
const AIM_STEP := 0.2
const AIM_TURN := 24.0
## Updates after the aim is let go that still count as the aim going down.
const AIM_DOWN := 15
## How far apart the gun hand's places and turns may be over a steady stretch of a gait.
const BAND_PLACE := 0.3
const BAND_TURN := 55.0
## Ticks after a key change before the stretch counts as steady.
const SETTLE := 30
## The run: keys held and ticks; `aim` holds the right mouse button too.
const RUN: Array = [
	["W", 90],
	["D", 70],
	["S", 70],
	["", 50],
	["A", 70],
	["A aim", 50],
	["A", 60],
	["WA", 60],
	["SD", 70],
	["", 50],
]
const KEYS := {"W": KEY_W, "A": KEY_A, "S": KEY_S, "D": KEY_D}
const GAITS := {"walk": KEY_X, "jog": KEY_NONE, "sprint": KEY_SHIFT}

var _arena: PlayArena
var _player: Player
var _skeleton: Skeleton3D
var _reading := false
var _samples: Array[Transform3D] = []
# Whether each sample was read while the aim came up or went down.
var _aiming: Array[bool] = []
var _aim_left := 0
var _labels := PackedStringArray(["", ""])


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_arena.add_block(Vector2.ZERO, Vector3(400.0, 1.0, 400.0), 0.0)
	_player = _arena.add_player(Vector3.ZERO)
	await InputSim.ticks(get_tree(), 10)
	_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	await InputSim.ticks(get_tree(), 30)


func after_test() -> void:
	InputSim.release_all()
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


func test_the_pistol_holds_its_carry_on_the_female_body() -> void:
	await _check_body("female", ["Pistol", "Rifle"])


func test_the_pistol_holds_its_carry_on_the_male_body() -> void:
	_player.model.variant = load(CharacterBodies.MALE) as PackedScene
	await InputSim.ticks(get_tree(), 30)
	await _check_body("male", ["Pistol", "Rifle"])


func _check_body(body: String, weapons: Array) -> void:
	_skeleton = _player.model.skeleton()
	_skeleton.skeleton_updated.connect(_read)
	var problems: Array[String] = []
	for weapon: String in weapons:
		await _hold(weapon)
		for gait: String in GAITS:
			var steady := await _run(gait)
			var tag := "%s %s %s" % [body, weapon, gait]
			var carried := _largest_step(false)
			var aimed := _largest_step(true)
			var band := Vector2.ZERO
			for stretch: Array[Transform3D] in steady:
				var spread := _spread(stretch)
				band = Vector2(maxf(band.x, spread.x), maxf(band.y, spread.y))
			var line := (
				"%s: carried a tick %.3f m %.1f deg (%s), aim %.3f m %.1f deg, band %.2f m %.1f deg"
				% [tag, carried.x, carried.y, _labels[0], aimed.x, aimed.y, band.x, band.y]
			)
			print("PISTOL CARRY ", line)
			if OS.get_environment("GDS_CARRY_TRACE") != "":
				_trace(tag)
			if weapon != "Pistol":
				continue
			var over := carried.x > HAND_STEP or carried.y > HAND_TURN
			over = over or aimed.x > AIM_STEP or aimed.y > AIM_TURN
			over = over or band.x > BAND_PLACE or band.y > BAND_TURN
			if over:
				problems.append(line)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


# Brings `weapon_name` out and waits for the switch to end.
func _hold(weapon_name: String) -> void:
	var slots := _player.loadout.slots
	for slot in slots.size():
		if slots[slot] != null and slots[slot].display_name == weapon_name:
			_player.loadout.select(slot)
	await InputSim.ticks(get_tree(), 60)
	assert_str(_player.weapon.definition.display_name).is_equal(weapon_name)


# The run at `gait`, read on every update; returns the steady stretches of the moving steps.
func _run(gait: String) -> Array:
	InputSim.release_all()
	await InputSim.ticks(get_tree(), 30)
	_player.teleport(Vector3.ZERO, PI)
	await InputSim.ticks(get_tree(), 40)
	var held: Key = GAITS[gait]
	if held != KEY_NONE:
		InputSim.key(held, true)
	_samples.clear()
	_aiming.clear()
	_labels = PackedStringArray(["", ""])
	_reading = true
	var steady: Array = []
	for step: Array in RUN:
		var keys: String = step[0]
		var aims := keys.ends_with(" aim")
		for key: String in KEYS:
			InputSim.key(KEYS[key], keys.get_slice(" ", 0).contains(key))
		InputSim.mouse_button(MOUSE_BUTTON_RIGHT, aims)
		if aims:
			_aim_left = int(step[1]) + AIM_DOWN
		var from := _samples.size()
		await InputSim.ticks(get_tree(), int(step[1]))
		if keys != "" and not aims:
			var stretch: Array[Transform3D] = []
			stretch.assign(_samples.slice(maxi(from + SETTLE, _first_carried(from))))
			steady.append(stretch)
	_reading = false
	InputSim.release_all()
	return steady


# The first sample from `from` on that is not the aim going down.
func _first_carried(from: int) -> int:
	var at := from
	while at < _aiming.size() and _aiming[at]:
		at += 1
	return at


# The largest move (x, metres) and turn (y, degrees) of the hand between two updates, carried or
# (`aiming`) while the aim comes up or goes down; notes the update in `_labels`.
func _largest_step(aiming: bool) -> Vector2:
	var most := Vector2.ZERO
	for index in range(1, _samples.size()):
		if _aiming[index] != aiming:
			continue
		var a := _samples[index - 1]
		var b := _samples[index]
		var moved := a.origin.distance_to(b.origin)
		var turn := rad_to_deg(
			a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion())
		)
		if moved > most.x or turn > most.y:
			_labels[1 if aiming else 0] = "update %d" % index
		most = Vector2(maxf(most.x, moved), maxf(most.y, turn))
	return most


# How far apart (x, metres) and turned from each other (y, degrees) the samples are, at most.
static func _spread(samples: Array[Transform3D]) -> Vector2:
	var most := Vector2.ZERO
	for i in range(0, samples.size(), 2):
		for j in range(i + 2, samples.size(), 2):
			most.x = maxf(most.x, samples[i].origin.distance_to(samples[j].origin))
			var qi := samples[i].basis.get_rotation_quaternion()
			var qj := samples[j].basis.get_rotation_quaternion()
			most.y = maxf(most.y, rad_to_deg(qi.angle_to(qj)))
	return most


func _trace(tag: String) -> void:
	var parts: PackedStringArray = []
	for index in range(1, _samples.size()):
		var a := _samples[index - 1]
		var b := _samples[index]
		var turn := rad_to_deg(
			a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion())
		)
		var aim := "a" if _aiming[index] else ""
		parts.append("%d%s:%.3f:%.1f" % [index, aim, a.origin.distance_to(b.origin), turn])
	print("CARRYTRACE %s %s" % [tag, " ".join(parts)])


# One update of the skeleton, after its modifiers: the gun hand in the chest's space.
func _read() -> void:
	if not _reading:
		return
	var chest := _skeleton.get_bone_global_pose(_skeleton.find_bone(&"spine_03"))
	var hand := _skeleton.get_bone_global_pose(_skeleton.find_bone(&"hand_r"))
	_samples.append(chest.affine_inverse() * hand)
	_aiming.append(_aim_left > 0)
	_aim_left = maxi(_aim_left - 1, 0)

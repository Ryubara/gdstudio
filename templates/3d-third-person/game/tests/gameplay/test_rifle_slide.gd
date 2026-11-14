# A slide with the rifle is the slide with the pistol (kit #1413): from the same sprint and the
# same keys it starts on the same tick, lasts as long and goes as far, and the body slides the
# same way, the trunk where the slide's clip has it and the left hand on the hand guard, whatever
# place in the stride the slide starts from and wherever the stick steers it. Before the fix the
# rifle's standing idle held the trunk over the slide's laid-back hips and the chest's turn rolled
# it onto its side: 83 degrees back against the pistol's 64, 24 to the side, the left hand 59 mm
# off. The player is driven with simulated keys and read on every update of its skeleton.
extends GdUnitTestSuite

const RIFLE := "res://gameplay/weapon/rifle.tres"
## The sprints the slides start from, in ticks: different places in the sprint's stride.
const SPRINTS: Array[int] = [24, 29, 34, 39]
## The key held through each slide besides crouch: none, steering left and steering right.
const STEERS: Array[Key] = [KEY_NONE, KEY_A, KEY_D]
## The ticks a slide is read for after crouch is pressed (it lasts about 58).
const READ_TICKS := 90
## How far a slide with the rifle may start, last (ticks) and go (metres) from the pistol's.
const TICKS := 0
const DISTANCE := 0.01
## How far the trunk (the line from the pelvis to the neck) may lean back, and to the side, with
## the rifle from the pistol's on the same tick of the same slide, in degrees. The chest's turn
## that brings the left shoulder to the hand guard moves the neck 7 to 11 degrees to the side all
## through the slide, as in the sprint, and the first ticks still blend the sprints apart by 7.
const LEAN := 9.0
const SIDE := 13.0
## How far the left hand may be from its place on the hand guard, in metres.
const HAND_GAP := 0.02

var _arena: PlayArena
var _player: Player
var _skeleton: Skeleton3D
var _reading := false
var _side := 0.0
var _lean := 0.0
var _gap := 0.0


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 25.0))
	await InputSim.ticks(get_tree(), 10)
	_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	await InputSim.ticks(get_tree(), 60)
	_skeleton = _player.model.skeleton()
	_skeleton.skeleton_updated.connect(_read)


func after_test() -> void:
	InputSim.release_all()
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


func test_a_rifle_slide_is_the_pistol_slide() -> void:
	var problems: Array[String] = []
	for sprint in SPRINTS:
		for steer in STEERS:
			await _hold("Pistol")
			var pistol := await _slide(sprint, steer)
			await _hold("Rifle")
			var rifle := await _slide(sprint, steer)
			var tag := "sprint %d steer %s" % [sprint, OS.get_keycode_string(steer)]
			problems.append_array(_compare(tag, pistol, rifle))
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


# Brings `weapon_name` out of the loadout and waits for the switch to end.
func _hold(weapon_name: String) -> void:
	var slots := _player.loadout.slots
	for slot in slots.size():
		if slots[slot] != null and slots[slot].display_name == weapon_name:
			_player.loadout.select(slot)
	await InputSim.ticks(get_tree(), 60)
	assert_str(_player.weapon.definition.display_name).is_equal(weapon_name)


# One slide from a standstill at the arena's start: a sprint of `sprint` ticks, then crouch held
# with `steer`. Its first tick, length in ticks and distance, and on each of its ticks the trunk's
# lean back and to the side and the left hand's gap.
func _slide(sprint: int, steer: Key) -> Dictionary:
	_player.teleport(Vector3(0.0, 0.0, 25.0), PI)
	await InputSim.ticks(get_tree(), 40)
	InputSim.key(KEY_W, true)
	InputSim.key(KEY_SHIFT, true)
	await InputSim.ticks(get_tree(), sprint)
	InputSim.key(KEY_C, true)
	if steer != KEY_NONE:
		InputSim.key(steer, true)
	var found := {"start": -1, "ticks": 0, "distance": 0.0, "leans": [], "sides": [], "gaps": []}
	var from := _player.global_position
	_reading = true
	for tick in READ_TICKS:
		await InputSim.ticks(get_tree(), 1)
		await get_tree().process_frame
		if not _player.sliding:
			continue
		if found.start < 0:
			found.start = tick
			from = _player.global_position
		found.ticks += 1
		var moved := _player.global_position - from
		found.distance = Vector2(moved.x, moved.z).length()
		found.leans.append(_lean)
		found.sides.append(_side)
		found.gaps.append(_gap)
	_reading = false
	InputSim.release_all()
	await InputSim.ticks(get_tree(), 40)
	if _player.crouching:
		InputSim.key(KEY_C, true)
		await InputSim.ticks(get_tree(), 2)
		InputSim.key(KEY_C, false)
		await InputSim.ticks(get_tree(), 40)
	return found


func _compare(tag: String, pistol: Dictionary, rifle: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	if pistol.start < 0 or rifle.start < 0:
		problems.append("%s: no slide (pistol %d, rifle %d)" % [tag, pistol.start, rifle.start])
		return problems
	if absi(rifle.start - pistol.start) > TICKS or absi(rifle.ticks - pistol.ticks) > TICKS:
		problems.append(
			(
				"%s: the rifle's slide starts at %d for %d ticks, the pistol's at %d for %d"
				% [tag, rifle.start, rifle.ticks, pistol.start, pistol.ticks]
			)
		)
	if absf(rifle.distance - pistol.distance) > DISTANCE:
		problems.append(
			(
				"%s: the rifle's slide %.2f m, the pistol's %.2f m"
				% [tag, rifle.distance, pistol.distance]
			)
		)
	var lean := _most_apart(pistol.leans, rifle.leans)
	if lean.x > LEAN:
		problems.append(
			(
				"%s: the trunk leans back %.1f degrees from the pistol's at tick %d"
				% [tag, lean.x, lean.y]
			)
		)
	var side := _most_apart(pistol.sides, rifle.sides)
	if side.x > SIDE:
		problems.append(
			(
				"%s: the trunk leans %.1f degrees to the side from the pistol's at tick %d"
				% [tag, side.x, side.y]
			)
		)
	var gap: float = rifle.gaps.max()
	if gap > HAND_GAP:
		problems.append("%s: the left hand %.0f mm off the hand guard" % [tag, gap * 1e3])
	print(
		(
			"SLIDE %-24s start %d/%d ticks %d/%d %.2f/%.2f m, back %.1f, side %.1f, hand %.1f mm"
			% [
				tag,
				pistol.start,
				rifle.start,
				pistol.ticks,
				rifle.ticks,
				pistol.distance,
				rifle.distance,
				lean.x,
				side.x,
				gap * 1e3
			]
		)
	)
	return problems


# The most two readings of the same ticks differ, and on which tick.
func _most_apart(first: Array, second: Array) -> Vector2:
	var most := Vector2.ZERO
	for index in mini(first.size(), second.size()):
		var apart := absf(float(first[index]) - float(second[index]))
		if apart > most.x:
			most = Vector2(apart, index)
	return most


# One update of the skeleton, after its modifiers: the trunk's lean back and to the side (the
# line from the pelvis to the neck, in degrees in the model's space: the side one as the angle
# out of the body's middle plane, which holds for a trunk lying back) and the left hand's distance
# from its place on the rifle (none with the pistol).
func _read() -> void:
	if not _reading:
		return
	var trunk := (_place(&"neck_01") - _place(&"pelvis")).normalized()
	_lean = rad_to_deg(atan2(-trunk.z, trunk.y))
	_side = rad_to_deg(asin(clampf(trunk.x, -1.0, 1.0)))
	var hold := _player.model.get_node_or_null("RifleHeld") as TwoHandHold
	if hold == null or not hold.visible:
		_gap = 0.0
		return
	var target := hold.find_child("LeftHandTarget", true, false) as Node3D
	var hand := (
		_skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(&"hand_l"))
	)
	_gap = hand.origin.distance_to(target.global_position)


func _place(bone: StringName) -> Vector3:
	return _skeleton.get_bone_global_pose(_skeleton.find_bone(bone)).origin

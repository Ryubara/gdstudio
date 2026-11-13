# Sprinting with the rifle carries it clear of the body (kit #1340): on the updates of the
# skeleton through whole strides of the sprint, on both bodies, fresh from the pickup, after a
# burst, after a switch to the pistol and back, and running back, across and on the diagonals, no
# point of the rifle is inside the body (the torso, the legs, the upper arms and the head; the
# forearms and hands hold it) and both hands are on their places on the rifle. The player is
# driven with simulated keys.
extends GdUnitTestSuite

const RIFLE := "res://gameplay/weapon/rifle.tres"
## The strides of the sprint read, after `SETTLE` ticks for the blends to end.
const STRIDES := 3
const SETTLE := 40
## The ticks after letting go of the fire button until the rifle is down again.
const AFTER_SHOT := 60
## How deep a point of the rifle may be in the body, in metres: the hold's own stock test's 10 mm.
const BODY_DEPTH := 0.01
## How far a hand may be from its place on the rifle, in metres.
const HAND_GAP := 0.005
## The rifle is measured against the skin on every this many updates (the hands on all of them).
const SKIN_EVERY := 5
## The ways run in `test_the_sprint_carries_the_rifle_clear_in_every_direction`: the keys held.
const DIRECTIONS: Array[Array] = [[KEY_S], [KEY_A], [KEY_D], [KEY_W, KEY_D], [KEY_S, KEY_A]]
const DIRECTION_NAMES: Array[String] = ["back", "left", "right", "ahead right", "back left"]

var _arena: PlayArena
var _player: Player
var _animation: CharacterAnimation
var _skeleton: Skeleton3D
var _hold: TwoHandHold
var _contact: HandContact
var _clearance: BodyClearance
var _updates: Array[Dictionary] = []
var _read_count := 0


func before_test() -> void:
	InputSim.release_all()


func after_test() -> void:
	InputSim.release_all()
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


func test_the_sprint_carries_the_rifle_clear_of_the_body(
	body: String, _test_parameters := [["female"], ["male"]]
) -> void:
	await _player_sprinting(body)
	_assert_clear(await _sprint("%s fresh" % body))
	await _burst()
	InputSim.key(KEY_SHIFT, true)
	await InputSim.ticks(get_tree(), AFTER_SHOT)
	_assert_clear(await _sprint("%s after a burst" % body))
	await _tap(KEY_1)
	await InputSim.ticks(get_tree(), 60)
	assert_str(_player.weapon.definition.display_name).is_equal("Pistol")
	await _tap(KEY_2)
	await InputSim.ticks(get_tree(), 60)
	assert_str(_player.weapon.definition.display_name).is_equal("Rifle")
	_assert_clear(await _sprint("%s after a switch" % body))


# The playtest's sprints were across and towards the camera too: the body turns to the way it runs
# and the rifle stays at the low ready, so the front thigh comes up under the muzzle at another
# angle. One stride each way, straight from the last.
func test_the_sprint_carries_the_rifle_clear_in_every_direction(
	body: String, _test_parameters := [["female"], ["male"]]
) -> void:
	await _player_sprinting(body)
	InputSim.key(KEY_W, false)
	for way: Array in DIRECTIONS:
		for key: Key in [KEY_W, KEY_A, KEY_S, KEY_D]:
			InputSim.key(key, way.has(key))
		_assert_clear(await _sprint("%s %s" % [body, DIRECTION_NAMES[DIRECTIONS.find(way)]], 1))


# A player of `body` in an arena with the rifle out, sprinting forward.
func _player_sprinting(body: String) -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	# Each direction is read in steady sprint strides, not through a reversal's clip (#1442).
	_player.controller.turn_clips = false
	if body == "male":
		var slot := _player.model
		var old := slot.rig()
		slot.remove_child(old)
		old.free()
		slot.add_child((load(CharacterBodies.MALE) as PackedScene).instantiate())
	var view := Camera3D.new()
	view.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(view)
	view.make_current()
	await InputSim.ticks(get_tree(), 10)
	_skeleton = _player.model.skeleton()
	_animation = _player.find_children("*", "CharacterAnimation", true, false)[0]
	_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	await InputSim.ticks(get_tree(), 60)
	assert_str(_player.weapon.definition.display_name).is_equal("Rifle")
	_hold = _player.model.get_node("RifleHeld") as TwoHandHold
	var near := _hold.get_node(^"Pivot/Rifle/Near") as Node3D
	_contact = HandContact.new(_skeleton)
	_contact.set_weapon(near)
	_clearance = BodyClearance.new(_skeleton, _contact, near, BodyClearance.HOLDING)
	InputSim.key(KEY_W, true)
	InputSim.key(KEY_SHIFT, true)


func _tap(key: Key) -> void:
	InputSim.key(key, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(key, false)


func _burst() -> void:
	var rounds: int = _player.weapon.ammo
	InputSim.key(KEY_SHIFT, false)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 20)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	assert_int(_player.weapon.ammo).override_failure_message("no shot was fired").is_less(rounds)


# Every update of `strides` strides of the sprint: the deepest point of the rifle in the body and
# each hand's distance from its place.
func _sprint(tag: String, strides := STRIDES) -> Array[Dictionary]:
	_player.position.x = 0.0
	_player.position.z = 0.0
	await InputSim.ticks(get_tree(), SETTLE)
	assert_bool(_player.is_sprinting()).override_failure_message(tag + ": not sprinting").is_true()
	var stride := _animation.animation_player.get_animation(_animation.sprint_clip).length
	_updates.clear()
	_skeleton.skeleton_updated.connect(_contact.snapshot)
	_skeleton.skeleton_updated.connect(_read)
	await InputSim.ticks(get_tree(), roundi(stride * strides * Engine.physics_ticks_per_second))
	_skeleton.skeleton_updated.disconnect(_read)
	_skeleton.skeleton_updated.disconnect(_contact.snapshot)
	var deepest := {"depth": 0.0}
	for update in _updates:
		if update.depth > deepest.depth:
			deepest = update
	print(
		(
			("SPRINT %-24s updates %3d deepest %5.1f mm in %s, hands off %.1f / %.1f mm")
			% [
				tag,
				_updates.size(),
				deepest.depth * 1e3,
				deepest.get("bone", ""),
				_most("right") * 1e3,
				_most("left") * 1e3
			]
		)
	)
	for update in _updates:
		update.tag = tag
	return _updates.duplicate()


func _most(key: String) -> float:
	var most := 0.0
	for update in _updates:
		most = maxf(most, update[key])
	return most


func _read() -> void:
	# The hands on every update; the skin, which costs about 50 milliseconds a pose, on every
	# `SKIN_EVERY`th, a step that shares no factor with the sprint's 36 updates a stride, so the
	# three strides read land on 22 different phases.
	var found := {"depth": 0.0, "bone": &"", "point": Vector3.ZERO}
	if _read_count % SKIN_EVERY == 0:
		found = _clearance.deepest(_hold.get_node(^"Pivot/Rifle/Near") as Node3D)
	_read_count += 1
	(
		_updates
		. append(
			{
				"depth": found.depth,
				"bone": found.bone,
				"point": found.point,
				"right": _gap("RightHandTarget", &"hand_r"),
				"left": _gap("LeftHandTarget", &"hand_l"),
			}
		)
	)


func _gap(marker: String, bone_name: StringName) -> float:
	var target := _hold.find_child(marker, true, false) as Node3D
	var pose := (
		_skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(bone_name))
	)
	return pose.origin.distance_to(target.global_position)


func _assert_clear(updates: Array[Dictionary]) -> void:
	assert_int(updates.size()).is_greater(10)
	for index in updates.size():
		var update := updates[index]
		(
			assert_float(update.depth)
			. override_failure_message(
				(
					"%s, update %d: the rifle is %.1f mm in the %s"
					% [update.tag, index, update.depth * 1e3, update.bone]
				)
			)
			. is_less(BODY_DEPTH)
		)
		for side: String in ["right", "left"]:
			(
				assert_float(update[side])
				. override_failure_message(
					(
						"%s, update %d: the %s hand is %.1f mm off its place"
						% [update.tag, index, side, update[side] * 1e3]
					)
				)
				. is_less(HAND_GAP)
			)

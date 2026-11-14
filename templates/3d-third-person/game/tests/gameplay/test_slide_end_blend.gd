# A slide's end into the crouch, and its start, blend on every drawn update (kit #1439): with the
# hands empty, the pistol and the rifle, on both bodies, no joint of the body (and not the rifle)
# moves more in one update than the momentum blend lets it, and the rifle's hands stay on it.
# Before the fix the momentum blend began on the update the state machine named the new state,
# while the tree still showed the old state's pose, so it measured nothing and the crouch came in
# whole on the next update: the chest moved 0.62 m and the right hand 0.70 m in one frame, and
# the start of the slide 0.48 to 0.68 m. The player is driven with simulated keys and read on
# every update of its skeleton, after its modifiers.
extends GdUnitTestSuite

const RIFLE := "res://gameplay/weapon/rifle.tres"
## The joints read, in the model's space.
const JOINTS: Array[StringName] = [&"Head", &"spine_03", &"hand_l", &"hand_r", &"calf_l", &"calf_r"]
## The weapons slid with, by their display names (`Fists` is the empty hands).
const WEAPONS: Array[String] = ["Fists", "Pistol", "Rifle"]
## The most a joint (or the rifle's pivot) may move in one update at 60 a second, in metres: the
## blend's own moves reach 0.16 m (the trunk rising out of the slide), the jump was 0.62 to 0.70.
const STEP := 0.3
## How far the rifle's left hand may be from its place on the hand guard, in metres, from the
## slide's end on (the slide itself is `test_rifle_slide.gd`'s, kit #1413). The crouch's jump left
## it 47 to 71 mm off for one update.
const HAND_GAP := 0.02
## The states whose hands are read: the slide's end and the crouch after it.
const HAND_STATES: Array[StringName] = [CharacterAnimation.SLIDE_EXIT, CharacterAnimation.CROUCH]
## The sprint before crouch is pressed, and the updates read from then (the slide lasts about 58
## ticks and ends crouched, crouch held).
const SPRINT := 30
const READ_TICKS := 110

var _arena: PlayArena
var _player: Player
var _skeleton: Skeleton3D
var _reading := false
var _last := {}
var _most := 0.0
var _where := ""
var _gap := 0.0
var _states: Array[StringName] = []


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 25.0))
	await InputSim.ticks(get_tree(), 10)
	_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	await InputSim.ticks(get_tree(), 60)


func after_test() -> void:
	InputSim.release_all()
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


func test_the_slide_blends_in_and_out_on_the_female_body() -> void:
	await _check_body("female")


func test_the_slide_blends_in_and_out_on_the_male_body() -> void:
	_player.model.variant = load(CharacterBodies.MALE) as PackedScene
	await InputSim.ticks(get_tree(), 30)
	await _check_body("male")


func _check_body(body: String) -> void:
	_skeleton = _player.model.skeleton()
	_skeleton.skeleton_updated.connect(_read)
	var problems: Array[String] = []
	for weapon in WEAPONS:
		await _hold(weapon)
		await _slide()
		var tag := "%s %s" % [body, weapon]
		print(
			(
				"SLIDE END %-14s most %.3f m (%s), rifle hand %.1f mm"
				% [tag, _most, _where, _gap * 1e3]
			)
		)
		if not _states.has(CharacterAnimation.SLIDE) or not _states.has(CharacterAnimation.CROUCH):
			problems.append("%s: no slide into the crouch (%s)" % [tag, _states])
		if _most > STEP:
			problems.append("%s: %s moved %.2f m in one update" % [tag, _where, _most])
		if _gap > HAND_GAP:
			problems.append("%s: the left hand %.0f mm off the hand guard" % [tag, _gap * 1e3])
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


# Brings `weapon_name` out (the empty hands for `Fists`) and waits for the switch to end.
func _hold(weapon_name: String) -> void:
	if weapon_name == "Fists":
		_player.loadout.select(WeaponLoadout.UNARMED)
	var slots := _player.loadout.slots
	for slot in slots.size():
		if slots[slot] != null and slots[slot].display_name == weapon_name:
			_player.loadout.select(slot)
	await InputSim.ticks(get_tree(), 60)
	assert_str(_player.weapon.definition.display_name).is_equal(weapon_name)


# One slide from a standstill, crouch held to its end, read on every update.
func _slide() -> void:
	_player.teleport(Vector3(0.0, 0.0, 25.0), PI)
	await InputSim.ticks(get_tree(), 40)
	InputSim.key(KEY_W, true)
	InputSim.key(KEY_SHIFT, true)
	await InputSim.ticks(get_tree(), SPRINT)
	_last.clear()
	_most = 0.0
	_where = ""
	_gap = 0.0
	_states.clear()
	_reading = true
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), READ_TICKS)
	_reading = false
	InputSim.release_all()
	await InputSim.ticks(get_tree(), 40)
	if _player.crouching:
		InputSim.key(KEY_C, true)
		await InputSim.ticks(get_tree(), 2)
		InputSim.key(KEY_C, false)
		await InputSim.ticks(get_tree(), 40)


# One update of the skeleton, after its modifiers: each joint's (and the rifle's pivot's) move
# since the last update in the model's space, and the rifle's left hand's distance from its place.
func _read() -> void:
	if not _reading:
		return
	var animation := _player.get_node("Animation") as CharacterAnimation
	var state := animation.body_state()
	if not _states.has(state):
		_states.append(state)
	var places := {}
	for joint in JOINTS:
		places[joint] = _skeleton.get_bone_global_pose(_skeleton.find_bone(joint)).origin
	var hold := _player.model.get_node_or_null("RifleHeld") as TwoHandHold
	if hold != null and hold.visible:
		var pivot := hold.find_child("Pivot", true, false) as Node3D
		var to_model := _skeleton.global_transform.affine_inverse()
		places[&"rifle"] = to_model * pivot.global_position
	if hold != null and hold.visible and state in HAND_STATES:
		var to_model := _skeleton.global_transform.affine_inverse()
		var target := hold.find_child("LeftHandTarget", true, false) as Node3D
		var hand := _skeleton.get_bone_global_pose(_skeleton.find_bone(&"hand_l")).origin
		_gap = maxf(_gap, hand.distance_to(to_model * target.global_position))
	for joint: StringName in places:
		if _last.has(joint):
			var moved: float = (places[joint] - _last[joint]).length()
			if moved > _most:
				_most = moved
				_where = "%s (%s)" % [joint, state]
	_last = places

# The slide's rack in the player's own scene (kit #1337): a reload of an empty pistol ends with the
# rack clip (`RackLayer`), whose hand closes on the slide where it stands locked back, pulls it the
# rest of the way and lets it run home, with the slide's sound there; the rounds go in at the end
# of `reload_time` as before; a reload with rounds left has none; a shot or a switch cuts the rack
# short and leaves the slide at rest. On both bodies the left hand holds the slide within the
# hold's limits (`tools/blender/weapons.md#hands-on-the-weapon`) on every update it grips, both
# hands pass through nothing on the way, and the carried arm stays in through the rack.
extends GdUnitTestSuite

const MODELS: Array[String] = ["female", "male"]
## How deep a hand may pass through the gun or the other hand on its way, in metres (the reload's
## own cap, `test_pistol_rack.gd`).
const PASSING_DEPTH := 0.006
## Ticks a reload and its rack take at most, with room (1.6 s and 0.93 s at 60 a second).
const RELOAD_AND_RACK := 180

var _hold: WeaponHold
var _skeleton: Skeleton3D
var _contact: HandContact
var _pistol: Node3D
var _gripped := 0
var _measured := 0
var _fails: Array[String] = []
var _deepest := 0.0
var _deepest_at := ""
var _swung := 0.0


func before_test() -> void:
	InputSim.release_all()


func after_test() -> void:
	InputSim.release_all()


func test_an_empty_reload_ends_with_the_rack() -> void:
	var arena: PlayArena = auto_free(PlayArena.new())
	add_child(arena)
	var player := await _player(arena, "female")
	var hold := player.get_node("WeaponHold") as WeaponHold
	var slide := player.get_node("Model/PistolHeld/Pistol/Pistol/Slide") as Node3D
	var sound := player.weapon.get_node("%ReloadSound") as AudioStreamPlayer3D
	var slide_sound := DecodedSounds.decoded(player.weapon.definition.reload_sounds[-1])
	var rack := hold.rack_fit()
	var rest := slide.transform
	player.weapon.set_ammo(0, 24)
	await InputSim.ticks(get_tree(), 2)
	sound.stream = null
	await _press(KEY_R)
	var reload_ticks := roundi(player.weapon.definition.reload_time * 60.0)
	var rack_from := -1
	var rounds_in := -1
	var forward_at := -1.0
	var sounded_at := -1.0
	var back_before := true
	var magazine_in_hand := 0
	for tick in RELOAD_AND_RACK:
		await InputSim.ticks(get_tree(), 1)
		if rounds_in >= 0 and hold.held_magazine().visible:
			magazine_in_hand += 1
		var racked := (player.get_node("Animation") as CharacterAnimation).rack.progress()
		if rack_from < 0 and racked.x > 0.0:
			rack_from = tick
		if rounds_in < 0 and player.weapon.ammo == 12:
			rounds_in = tick
		var off := (slide.transform.origin - rest.origin).dot(rest.basis.x.normalized())
		var before_release := rack_from < 0 or hold.rack_share < rack.release.x - 0.002
		if forward_at < 0.0 and off < 0.001:
			forward_at = hold.rack_share if rack_from >= 0 else -2.0
		elif forward_at < 0.0 and off < hold.slide_travel - 0.0005 and before_release:
			back_before = false
		if sounded_at < 0.0 and sound.stream == slide_sound:
			sounded_at = hold.rack_share if rack_from >= 0 else -2.0
	# The rack comes in over the reload's last moments and the rounds go in at its end.
	(
		assert_int(rack_from)
		. override_failure_message("the rack started at tick %d of %d" % [rack_from, reload_ticks])
		. is_between(reload_ticks - 12, reload_ticks + 2)
	)
	assert_int(rounds_in).is_between(reload_ticks - 5, reload_ticks + 2)
	# The slide stood back until the hand let it go, then ran home, with its sound.
	assert_bool(back_before).override_failure_message("the slide came forward early").is_true()
	(
		assert_float(forward_at)
		. override_failure_message("the slide ran home at %.3f of the rack" % forward_at)
		. is_between(rack.release.x, rack.release.x + rack.slam + 0.05)
	)
	(
		assert_float(sounded_at)
		. override_failure_message("the slide's sound played at %.3f of the rack" % sounded_at)
		. is_between(rack.release.x - 0.01, rack.release.x + 0.05)
	)
	assert_bool(slide.transform.origin.is_equal_approx(rest.origin)).is_true()
	assert_float((player.get_node("Animation") as CharacterAnimation).rack.progress().x).is_equal(
		0.0
	)
	# Through the rack and its fade the new magazine is the pistol's, never in the hand again.
	(
		assert_int(magazine_in_hand)
		. override_failure_message("a magazine in the hand on %d ticks" % magazine_in_hand)
		. is_equal(0)
	)
	AudioDrain.stop_all(arena)


func test_a_reload_with_rounds_left_has_no_rack() -> void:
	var arena: PlayArena = auto_free(PlayArena.new())
	add_child(arena)
	var player := await _player(arena, "female")
	var sound := player.weapon.get_node("%ReloadSound") as AudioStreamPlayer3D
	var slide_sound := DecodedSounds.decoded(player.weapon.definition.reload_sounds[-1])
	player.weapon.set_ammo(3, 24)
	await InputSim.ticks(get_tree(), 2)
	await _press(KEY_R)
	var racked := 0
	var sounded := false
	for tick in RELOAD_AND_RACK:
		await InputSim.ticks(get_tree(), 1)
		if (player.get_node("Animation") as CharacterAnimation).rack.progress().x > 0.0:
			racked += 1
		sounded = sounded or sound.stream == slide_sound
	assert_int(racked).is_equal(0)
	assert_bool(sounded).override_failure_message("the slide's sound did not play").is_true()
	assert_int(player.weapon.ammo).is_equal(12)
	AudioDrain.stop_all(arena)


# A shot while the hand has the slide back: the rack fades out, the hand leaves the slide and the
# slide is at rest; the shot is the one the rounds allow.
func test_a_shot_cuts_the_rack_short_and_leaves_the_slide_at_rest() -> void:
	var arena: PlayArena = auto_free(PlayArena.new())
	add_child(arena)
	var player := await _player(arena, "female")
	var hold := player.get_node("WeaponHold") as WeaponHold
	var slide := player.get_node("Model/PistolHeld/Pistol/Pistol/Slide") as Node3D
	var rest := slide.transform
	await _into_the_pull(player, hold)
	assert_bool(slide.transform.origin.is_equal_approx(rest.origin)).is_false()
	# The fire button raises the arm and fires once it is up.
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	for tick in 60:
		await InputSim.ticks(get_tree(), 1)
		if player.weapon.ammo < 12:
			break
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	await InputSim.ticks(get_tree(), roundi(RackLayer.FADE_OUT * 60.0) + 4)
	assert_int(player.weapon.ammo).is_less(12)
	assert_float((player.get_node("Animation") as CharacterAnimation).rack.progress().x).is_equal(
		0.0
	)
	assert_float(hold.rack_weight).is_equal(0.0)
	assert_bool(slide.transform.origin.is_equal_approx(rest.origin)).is_true()
	assert_bool(hold.rack_modifiers()[0].active).is_false()
	AudioDrain.stop_all(arena)


# A switch to the empty hands while the hand has the slide back: the same, and back on the pistol
# the slide is at rest with nothing to rack.
func test_a_switch_cuts_the_rack_short_and_leaves_the_slide_at_rest() -> void:
	var arena: PlayArena = auto_free(PlayArena.new())
	add_child(arena)
	var player := await _player(arena, "female")
	var hold := player.get_node("WeaponHold") as WeaponHold
	var slide := player.get_node("Model/PistolHeld/Pistol/Pistol/Slide") as Node3D
	var rest := slide.transform
	await _into_the_pull(player, hold)
	await _press(KEY_H)
	await InputSim.ticks(get_tree(), 90)
	assert_float((player.get_node("Animation") as CharacterAnimation).rack.progress().x).is_equal(
		0.0
	)
	assert_bool(slide.transform.origin.is_equal_approx(rest.origin)).is_true()
	await _press(KEY_H)
	await InputSim.ticks(get_tree(), 90)
	assert_float((player.get_node("Animation") as CharacterAnimation).rack.progress().x).is_equal(
		0.0
	)
	assert_bool(slide.transform.origin.is_equal_approx(rest.origin)).is_true()
	assert_int(player.weapon.ammo).is_equal(12)
	AudioDrain.stop_all(arena)


# The hands on the live player through the rack, on every update: the left hand on the slide
# within the hold's limits while it grips, nothing deeper than `PASSING_DEPTH` on the way, and the
# carried arm in.
func test_the_hands_hold_the_slide_on_the_live_player(
	model: String, _test_parameters := [["female"], ["male"]]
) -> void:
	var arena: PlayArena = auto_free(PlayArena.new())
	add_child(arena)
	var player := await _player(arena, model)
	_hold = player.get_node("WeaponHold") as WeaponHold
	_skeleton = player.model.skeleton()
	_pistol = player.get_node("Model/PistolHeld/Pistol") as Node3D
	_contact = HandContact.new(_skeleton)
	_gripped = 0
	_measured = 0
	_fails.clear()
	_deepest = 0.0
	_deepest_at = ""
	_swung = 0.0
	player.weapon.set_ammo(0, 24)
	await InputSim.ticks(get_tree(), 2)
	await _press(KEY_R)
	_skeleton.skeleton_updated.connect(_read)
	await InputSim.ticks(get_tree(), RELOAD_AND_RACK)
	_skeleton.skeleton_updated.disconnect(_read)
	await InputSim.ticks(get_tree(), 2)
	assert_int(_gripped).override_failure_message("never gripped").is_greater(4)
	assert_int(_measured).is_greater(30)
	assert_array(_fails).override_failure_message("\n".join(_fails)).is_empty()
	(
		assert_float(_deepest)
		. override_failure_message(
			"%s: a hand passed %.1f mm deep (%s)" % [model, _deepest * 1e3, _deepest_at]
		)
		. is_less(PASSING_DEPTH)
	)
	assert_float(_swung).override_failure_message("the arm swung out").is_equal(0.0)
	AudioDrain.stop_all(arena)


func _player(arena: PlayArena, model: String) -> Player:
	var player := arena.add_player(Vector3.ZERO)
	if model != "female":
		var old := player.model.rig()
		player.model.remove_child(old)
		old.free()
		player.model.add_child((load(HoldStage.MODELS[model]) as PackedScene).instantiate())
	var view := Camera3D.new()
	view.position = Vector3(0.0, 1.3, 3.0)
	arena.add_child(view)
	view.make_current()
	await InputSim.ticks(get_tree(), 20)
	return player


func _press(key: Key) -> void:
	InputSim.key(key, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(key, false)


# Reloads the empty pistol and waits until the rack's hand has the slide part of the way back.
func _into_the_pull(player: Player, hold: WeaponHold) -> void:
	player.weapon.set_ammo(0, 24)
	await InputSim.ticks(get_tree(), 2)
	await _press(KEY_R)
	var rack := hold.rack_fit()
	for tick in RELOAD_AND_RACK:
		await InputSim.ticks(get_tree(), 1)
		if hold.rack_weight >= 1.0 and hold.rack_share >= lerpf(rack.pull.x, rack.pull.y, 0.5):
			return


# The pose is copied in the skeleton's update and measured once the gun's attachment moved too.
func _read() -> void:
	if _hold.rack_weight <= 0.0:
		return
	_contact.snapshot()
	var grip := _hold.grip_modifier()
	if _hold.rack_weight >= 1.0 and grip != null:
		_swung = maxf(_swung, grip.swing_degrees)
	_measure.call_deferred(_hold.rack_share, _hold.rack_weight)


func _measure(share: float, weight: float) -> void:
	var rack := _hold.rack_fit()
	# The slide moves: the weapon's surface is taken where it is now.
	_contact.set_weapon(_pistol)
	_measured += 1
	var tag := "rack %.3f (weight %.2f)" % [share, weight]
	var gripping := weight >= 1.0 and rack.is_gripping(share)
	if gripping:
		_gripped += 1
		var parts := _contact.measure("l", true)
		_fails.append_array(HandContact.failures(tag + " l:", parts, RackStage.SLIDE_CONTACTS))
	var limit := HandContact.MAX_DEPTH if gripping else PASSING_DEPTH
	for side: String in ["l", "r"]:
		var parts := _contact.measure(side, true)
		for part: String in parts:
			var depth: float = -parts[part].distance
			if depth > _deepest:
				_deepest = depth
				_deepest_at = "%s %s %s" % [tag, side, part]
			if depth >= limit:
				_fails.append("%s %s %s %.1f mm inside" % [tag, side, part, depth * 1e3])

# The rifle's charging handle is pulled only in a reload of an empty magazine (kit #1402), as the
# pistol's slide is racked only then (`test_pistol_rack_live.gd`). In the player's own scene on
# both bodies: an empty reload ends with the left hand on the handle, the bolt pulled all the way
# back and home when the hand lets go, with the bolt's sound there; a reload with rounds left
# (a tactical reload) never moves the bolt, never brings the hand to the handle and has no bolt
# sound, and the hand goes straight back from the magazine under the hand guard. A switch or a
# blow cuts the pull short with the bolt home; a body lying down has no pull. On the stage
# (`RifleStage`, every half hundredth) the tactical reload's hand holds the hand guard at its ends
# and passes through nothing on the way. Each reload plays its own clip on the body (kit #1508):
# `Rifle_Reload_Empty`, with the beat for the bolt, only in the empty one.
extends GdUnitTestSuite

const MODELS: Array[String] = ["female", "male"]
const RIFLE := "res://gameplay/weapon/rifle.tres"
## How far a hand's bone may be from its place on the rifle, in metres (`test_rifle_hold.gd`).
const REACH := 0.005
## How deep the left hand may pass through the rifle on its way, in metres (`test_rifle_hold.gd`).
const PASSING_DEPTH := 0.006
## The reload's share step on the stage (`test_rifle_hold.gd`'s `RELOAD_STEP`).
const RELOAD_STEP := 0.005
## How near the charging handle the left hand comes in a tactical reload at the nearest, in metres:
## it never goes there (on the handle it is within 2 mm).
const AWAY_FROM_HANDLE := 0.05
## Ticks past the reload's own that a run is followed for.
const AFTER := 30

var _holder: Node3D
var _arena: PlayArena
var _player: Player
var _hold: TwoHandHold
var _skeleton: Skeleton3D
# Each update's distance of each hand's bone from its place on the rifle (x right, y left).
var _gaps: Array[Vector2] = []


func before_test() -> void:
	InputSim.release_all()
	_holder = auto_free(Node3D.new())
	add_child(_holder)
	_gaps.clear()


func after_test() -> void:
	InputSim.release_all()
	if _arena != null:
		AudioDrain.stop_all(_arena)
		_arena.queue_free()
	_arena = null


func test_an_empty_reload_ends_with_the_pull_on_both_bodies() -> void:
	for model in MODELS:
		var run := await _reload(model, 0)
		var travel := _hold.charge.travel.length()
		(
			assert_float(run.bolt_back)
			. override_failure_message(
				"%s: the bolt went %.1f mm back" % [model, run.bolt_back * 1e3]
			)
			. is_greater(travel * 0.95)
		)
		(
			assert_float(run.nearest_handle)
			. override_failure_message("%s: never on the handle" % model)
			. is_less(0.002)
		)
		# The bolt's sound plays where the hand lets the handle go.
		(
			assert_float(run.bolt_sound_at)
			. override_failure_message("%s: the bolt's sound at %.3f" % [model, run.bolt_sound_at])
			. is_between(_hold.charge.release.x - 0.01, _hold.charge.release.x + 0.03)
		)
		assert_str(String(run.clip)).is_equal(String(CharacterClips.RIFLE_RELOAD_EMPTY))
		_assert_ends_at_rest(run, model)
		await _clear()


func test_a_reload_with_rounds_left_has_no_pull_on_both_bodies() -> void:
	for model in MODELS:
		var run := await _reload(model, 3)
		(
			assert_float(run.bolt_back)
			. override_failure_message("%s: the bolt moved %.2f mm" % [model, run.bolt_back * 1e3])
			. is_less(0.00001)
		)
		(
			assert_float(run.nearest_handle)
			. override_failure_message(
				"%s: the hand came %.1f mm from the handle" % [model, run.nearest_handle * 1e3]
			)
			. is_greater(AWAY_FROM_HANDLE)
		)
		(
			assert_float(run.bolt_sound_at)
			. override_failure_message("%s: a bolt sound" % model)
			. is_less(0.0)
		)
		assert_int(run.sounds).override_failure_message("%s: reload sounds" % model).is_equal(2)
		assert_str(String(run.clip)).is_equal(String(CharacterClips.RIFLE_RELOAD))
		# Back under the hand guard by the end of the straight way, well before the reload's end.
		(
			assert_float(run.home_at)
			. override_failure_message("%s: home at %.3f" % [model, run.home_at])
			. is_between(
				_hold.charge.straight_return.y - 0.02, _hold.charge.straight_return.y + 0.03
			)
		)
		_assert_ends_at_rest(run, model)
		await _clear()


# A switch away in the middle of the pull puts the bolt home; the rounds never went in.
func test_a_switch_cuts_the_pull_short_with_the_bolt_home() -> void:
	await _player_with_the_rifle("female")
	var bolt := _hold.get_node(_hold.bolt) as Node3D
	var rest := bolt.transform
	await _into_the_pull()
	assert_bool(bolt.transform.is_equal_approx(rest)).is_false()
	_player.loadout.select(0)
	await InputSim.ticks(get_tree(), 60)
	assert_bool(bolt.transform.is_equal_approx(rest)).is_true()
	assert_bool(_player.weapon.is_reloading()).is_false()


# A blow in the middle of the pull cuts the reload and the pull short, with the bolt home.
func test_a_blow_cuts_the_pull_short_with_the_bolt_home() -> void:
	await _player_with_the_rifle("female")
	var bolt := _hold.get_node(_hold.bolt) as Node3D
	var rest := bolt.transform
	await _into_the_pull()
	assert_bool(bolt.transform.is_equal_approx(rest)).is_false()
	await _tap(KEY_V)
	await InputSim.ticks(get_tree(), 4)
	assert_bool(_player.weapon.is_reloading()).is_false()
	assert_bool(bolt.transform.is_equal_approx(rest)).is_true()
	await InputSim.ticks(get_tree(), 60)
	assert_bool(bolt.transform.is_equal_approx(rest)).is_true()


# Lying down, an empty reload has no pull (the pistol's prone reload has no rack); the bolt stays
# home and the hand never goes to the handle.
func test_an_empty_reload_lying_down_has_no_pull() -> void:
	await _player_with_the_rifle("female")
	await _tap(KEY_Z)
	await InputSim.ticks(get_tree(), 90)
	assert_bool(_player.prone).is_true()
	var bolt := _hold.get_node(_hold.bolt) as Node3D
	var rest := bolt.transform
	var handle := _hold.find_child("ChargeHand", true, false) as Node3D
	var left := _hold.find_child("LeftHandTarget", true, false) as Node3D
	_player.weapon.set_ammo(0, 60)
	await _tap(KEY_R)
	var moved := 0.0
	var nearest := 1.0
	var reloaded := false
	for _tick in roundi(_player.weapon.definition.reload_time * 60.0) + AFTER:
		await InputSim.ticks(get_tree(), 1)
		reloaded = reloaded or _player.weapon.is_reloading()
		moved = maxf(moved, bolt.transform.origin.distance_to(rest.origin))
		nearest = minf(nearest, left.transform.origin.distance_to(handle.transform.origin))
	assert_bool(reloaded).override_failure_message("no reload lying down").is_true()
	assert_float(moved).is_less(0.00001)
	assert_float(nearest).is_greater(AWAY_FROM_HANDLE)
	assert_int(_player.weapon.ammo).is_equal(30)


# On the stage, a tactical reload every half hundredth on both bodies: the bolt never moves, the
# left hand holds the hand guard before it leaves and from the straight way's end, holds the
# magazine while it is seated, and passes through nothing deeper than `PASSING_DEPTH` between.
func test_the_tactical_reloads_hand_goes_straight_back_on_the_stage() -> void:
	for model in MODELS:
		var stage := RifleStage.make_rifle(_holder, model)
		var hold := stage.hold as TwoHandHold
		hold.charge_bolt.posed_pulls = false
		var bolt := hold.get_node(hold.bolt) as Node3D
		var bolt_rest := bolt.position
		var marker := stage.rifle.get_node(^"MagazineHand") as Node3D
		var back := hold.charge.straight_return
		var on_guard := 0
		var share := 0.0
		while share <= 1.0001:
			stage.pose_rifle(CharacterClips.IDLE, 0.0, 1.0, 0.0, share)
			await stage.settle()
			stage.contact.set_weapon(stage.rifle.get_node(^"Near") as Node3D)
			var tag := "%s tactical reload at %.3f" % [model, share]
			assert_float(bolt.position.distance_to(bolt_rest)).is_less(0.00001)
			var gap := stage.hand_gap("l")
			(
				assert_float(gap)
				. override_failure_message("%s: %.1f mm off" % [tag, gap * 1e3])
				. is_less(REACH)
			)
			var out := share > hold.reload_out.x + 0.001 and share < hold.reload_in.y - 0.001
			var seated := share > hold.reload_leave.y - 0.001 and share < back.x + 0.001
			if share <= hold.reload_leave.x or share >= back.y:
				on_guard += 1
				var fails := HandContact.failures(
					tag + " l:", stage.contact.measure("l"), RifleStage.RIFLE_LEFT_CONTACTS
				)
				assert_array(fails).override_failure_message("\n".join(fails)).is_empty()
			elif out:
				pass
			elif seated:
				var at := stage.bone_origin(&"hand_l").distance_to(marker.global_position)
				assert_float(at).override_failure_message("%s: off the magazine" % tag).is_less(
					REACH
				)
			else:
				var parts := stage.contact.measure("l")
				for part: String in parts:
					var depth: float = -parts[part].distance
					(
						assert_float(depth)
						. override_failure_message(
							"%s l: %s %.1f mm inside on the way" % [tag, part, depth * 1e3]
						)
						. is_less(PASSING_DEPTH)
					)
			share += RELOAD_STEP
		assert_int(on_guard).is_greater(10)
		stage.free()


# Reloads the player's rifle on `model` from a magazine of `rounds` and follows it on every tick.
func _reload(model: String, rounds: int) -> Dictionary:
	await _player_with_the_rifle(model)
	var left := _hold.find_child("LeftHandTarget", true, false) as Node3D
	var handle := _hold.find_child("ChargeHand", true, false) as Node3D
	var bolt := _hold.get_node(_hold.bolt) as Node3D
	var sound := _player.weapon.get_node("%ReloadSound") as AudioStreamPlayer3D
	var bolt_sound := DecodedSounds.decoded(_player.weapon.definition.reload_sounds[-1])
	var run := {
		"rest": left.transform,
		"bolt_rest": bolt.transform,
		"bolt_back": 0.0,
		"nearest_handle": 1.0,
		"bolt_sound_at": -1.0,
		"sounds": 0,
		"home_at": -1.0,
		"left": left,
		"bolt": bolt,
		"clip": &"",
	}
	_player.weapon.set_ammo(rounds, 60)
	await InputSim.ticks(get_tree(), 2)
	sound.stream = null
	_skeleton.skeleton_updated.connect(_read_gaps)
	await _tap(KEY_R)
	var animation := _player.get_node("Animation") as CharacterAnimation
	var root := animation.tree.tree_root as AnimationNodeBlendTree
	run.clip = (root.get_node(&"ReloadClip") as AnimationNodeAnimation).animation
	var last_stream: AudioStream = null
	var away := false
	for _tick in roundi(_player.weapon.definition.reload_time * 60.0) + AFTER:
		await InputSim.ticks(get_tree(), 1)
		var share := _player.weapon.reload_progress() if _player.weapon.is_reloading() else -1.0
		if sound.stream != last_stream and sound.stream != null:
			last_stream = sound.stream
			run.sounds += 1
		if sound.stream == bolt_sound and run.bolt_sound_at < 0.0:
			run.bolt_sound_at = share
		if share < 0.0:
			continue
		var back := bolt.transform.origin.distance_to(run.bolt_rest.origin)
		run.bolt_back = maxf(run.bolt_back, back)
		var on_handle := handle.transform.origin + _hold.charge.travel.normalized() * back
		run.nearest_handle = minf(run.nearest_handle, left.transform.origin.distance_to(on_handle))
		var home := left.transform.is_equal_approx(run.rest)
		away = away or not home
		if away and home and run.home_at < 0.0:
			run.home_at = share
	_skeleton.skeleton_updated.disconnect(_read_gaps)
	return run


func _assert_ends_at_rest(run: Dictionary, model: String) -> void:
	assert_bool((run.bolt as Node3D).transform.is_equal_approx(run.bolt_rest)).is_true()
	assert_bool((run.left as Node3D).transform.is_equal_approx(run.rest)).is_true()
	assert_int(_player.weapon.ammo).is_equal(30)
	assert_int(_gaps.size()).is_greater(100)
	for gap in _gaps:
		(
			assert_float(maxf(gap.x, gap.y))
			. override_failure_message(
				"%s: a hand %.1f mm off its place" % [model, maxf(gap.x, gap.y) * 1e3]
			)
			. is_less(REACH)
		)


# Reloads the empty rifle and waits until the hand has the bolt part of the way back.
func _into_the_pull() -> void:
	_player.weapon.set_ammo(0, 60)
	await _tap(KEY_R)
	var pull := _hold.charge.pull
	for _tick in roundi(_player.weapon.definition.reload_time * 60.0):
		await InputSim.ticks(get_tree(), 1)
		if _player.weapon.reload_progress() > (pull.x + pull.y) * 0.5:
			return


# A player on `model` in an arena with the rifle given, drawn and at the low ready.
func _player_with_the_rifle(model: String) -> void:
	_arena = PlayArena.new()
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	if model != "female":
		var old := _player.model.rig()
		_player.model.remove_child(old)
		old.free()
		_player.model.add_child((load(HoldStage.MODELS[model]) as PackedScene).instantiate())
	var view := Camera3D.new()
	view.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(view)
	view.make_current()
	await InputSim.ticks(get_tree(), 10)
	_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	await InputSim.ticks(get_tree(), 60)
	_hold = _player.model.get_node("RifleHeld") as TwoHandHold
	_skeleton = _player.model.skeleton()
	_gaps.clear()
	assert_str(_player.weapon.definition.display_name).is_equal("Rifle")


# Leaves the arena of one body's run before the next.
func _clear() -> void:
	AudioDrain.stop_all(_arena)
	_arena.queue_free()
	_arena = null
	await InputSim.ticks(get_tree(), 2)


func _tap(key: Key) -> void:
	InputSim.key(key, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(key, false)


func _read_gaps() -> void:
	var gap := Vector2.ZERO
	for side: String in ["r", "l"]:
		var target := (
			_hold.find_child("RightHandTarget" if side == "r" else "LeftHandTarget", true, false)
			as Node3D
		)
		var hand := (
			_skeleton.global_transform
			* _skeleton.get_bone_global_pose(_skeleton.find_bone("hand_" + side))
		)
		gap[0 if side == "r" else 1] = hand.origin.distance_to(target.global_position)
	_gaps.append(gap)

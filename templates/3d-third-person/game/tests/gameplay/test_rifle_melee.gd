# The rifle's melee blows (gdstudio #1288): its category names three clips of our own
# (`Melee_Rifle_Butt_Stroke`, `_Butt_Jab`, `_Smash`) and a hit window that spans their measured
# contacts on both bodies (`melee_clips.json`); V with the rifle lands on a character inside that
# window and once; while a blow's clip plays the two-hand hold takes itself off (`HoldBlow`: the
# rifle rides the clip's right hand, no aim is raised, the chest's turn eases off) and comes back
# after it; and posed on both bodies at every frame of every blow, both hand bones are on their
# places on the rifle, which on the body the clips were keyed on is where the clip has the hand.
extends GdUnitTestSuite

const MODELS: Array[String] = ["female", "male"]
const RIFLE := "res://gameplay/weapon/rifle.tres"
const RIFLE_CATEGORY := "res://gameplay/weapon/categories/rifle.tres"
const CLIPS_JSON := "res://assets/animation/melee/melee_clips.json"
const MELEE := "res://assets/animation/melee/melee.glb"
## The body files the melee build solves against, by file name.
const MEASURED_BODIES: Array[String] = ["form_female", "form_male"]
## The issue that measures `melee_clips.json` again, while its numbers are older than the game's
## measure script: the build cannot make its files since kit #1399 (kit #1493), so the file names
## no measure yet. The test fails once the file is measured again, so this goes with that rebuild.
const STALE_UNTIL := "kit #1493"
const BLOWS: Array[StringName] = [
	CharacterClips.MELEE_RIFLE_BUTT_STROKE,
	CharacterClips.MELEE_RIFLE_BUTT_JAB,
	CharacterClips.MELEE_RIFLE_SMASH,
]
const TICK := 1.0 / 60.0
const FPS := 30.0
## How far a hand's bone may be from its place on the rifle during a blow, in metres.
const REACH := 0.002
## How far the right hand may be from where the clip keys it, on the body the clip was keyed on.
const CLIP_HAND := 0.003

var _holder: Node3D
var _arena: PlayArena
var _player: Player
var _target: Character


func before_test() -> void:
	InputSim.release_all()
	_holder = auto_free(Node3D.new())
	add_child(_holder)


func after_test() -> void:
	InputSim.release_all()
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


func _player_with_the_rifle() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	var view := Camera3D.new()
	view.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(view)
	view.make_current()
	_target = HitRange.target(_arena, Vector3(0.0, 0.0, -1.0))
	await InputSim.ticks(get_tree(), 10)
	_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	await InputSim.ticks(get_tree(), 60)
	assert_str(_player.weapon.definition.display_name).is_equal("Rifle")


func _hold() -> TwoHandHold:
	return _player.model.get_node("RifleHeld") as TwoHandHold


func _clips() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(CLIPS_JSON))["clips"]


# The numbers are the build's measure of melee.glb (kit #1491): the file is the one measured, and
# the measure script and the body files are the game's own, by their hashes, as for a limb
# overlap report (`BodiesOverlap.stale`).
func test_the_numbers_were_measured_on_this_file_by_the_games_measure() -> void:
	var measured: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CLIPS_JSON)).measured
	(
		assert_str(FileAccess.get_sha256(MELEE))
		. override_failure_message(
			"melee.glb is not the file melee_clips.json was measured on: run build_melee.py"
		)
		. is_equal(measured.sha256)
	)
	var stale := BodiesOverlap.stale(
		measured.merged({"clips_file": MELEE.get_file()}), MEASURED_BODIES
	)
	if STALE_UNTIL.is_empty():
		assert_array(stale).is_empty()
	else:
		(
			assert_array(stale)
			. override_failure_message(
				"melee_clips.json is measured again: empty STALE_UNTIL (%s)" % STALE_UNTIL
			)
			. is_not_empty()
		)


func test_the_rifle_category_names_its_blows_and_their_measured_window() -> void:
	var category := load(RIFLE_CATEGORY) as WeaponCategory
	assert_array(category.melee_clips).is_equal(BLOWS)
	# The window spans the picked clips' contacts on both bodies, to the nearest hundredth.
	var clips := _clips()
	var first := INF
	var last := -INF
	for blow in BLOWS:
		var entry: Dictionary = clips[String(blow).get_file()]
		for numbers: Dictionary in [entry, entry["male"]]:
			first = minf(first, numbers["hit_start"])
			last = maxf(last, numbers["hit_end"])
	assert_float(category.melee_hit_start).is_equal_approx(snappedf(first, 0.01), 0.001)
	assert_float(category.melee_hit_end).is_equal_approx(snappedf(last, 0.01), 0.001)
	assert_float(category.melee_cooldown).is_greater(category.melee_hit_end)


func test_v_with_the_rifle_strikes_a_character_in_its_window_and_once() -> void:
	await _player_with_the_rifle()
	var weapon := _player.weapon
	var category := load(RIFLE_CATEGORY) as WeaponCategory
	assert_object(weapon.definition.category).is_same(category)
	var hits: Array[Dictionary] = []
	weapon.hit_scanned.connect(func(hit: Dictionary) -> void: hits.append(hit))
	var full: float = Health.of(_target).value
	var rounds: int = weapon.ammo
	InputSim.key(KEY_V, true)
	await InputSim.ticks(get_tree(), 1)
	InputSim.key(KEY_V, false)
	var early := floori(category.melee_hit_start / TICK) - 2
	await InputSim.ticks(get_tree(), early)
	assert_int(hits.size()).is_equal(0)
	await InputSim.ticks(
		get_tree(), ceili((category.melee_hit_end - category.melee_hit_start) / TICK) + 4
	)
	assert_int(hits.size()).is_equal(1)
	assert_bool(hits[0]["melee"]).is_true()
	assert_float(Health.of(_target).value).is_less(full)
	assert_int(weapon.ammo).is_equal(rounds)
	var animation := _player.get_node("Animation") as CharacterAnimation
	assert_str(String(animation.melee.clip)).is_equal(String(BLOWS[0]))


func test_a_blow_takes_the_two_hand_hold_off_and_gives_it_back() -> void:
	await _player_with_the_rifle()
	var hold := _hold()
	var skeleton := _player.model.skeleton()
	var seen := {"blow": 0.0, "raised": 0.0, "chest": 1.0, "gap": 0.0, "updates": 0}
	var targets: Array[Node3D] = [
		hold.find_child("RightHandTarget", true, false) as Node3D,
		hold.find_child("LeftHandTarget", true, false) as Node3D,
	]
	var read := func() -> void:
		seen["blow"] = maxf(seen["blow"], hold.blow_amount())
		seen["raised"] = maxf(seen["raised"], hold.raised_amount())
		seen["chest"] = minf(seen["chest"], hold.chest_weight())
		for index in 2:
			var bone := skeleton.find_bone(&"hand_r" if index == 0 else &"hand_l")
			var hand := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
			seen["gap"] = maxf(seen["gap"], hand.origin.distance_to(targets[index].global_position))
		seen["updates"] += 1
	assert_float(hold.blow_amount()).is_equal(0.0)
	skeleton.skeleton_updated.connect(read)
	InputSim.key(KEY_V, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_V, false)
	await InputSim.ticks(get_tree(), 40)
	skeleton.skeleton_updated.disconnect(read)
	assert_int(seen["updates"]).is_greater(30)
	# The clip held the whole upper body, the hold's chest turn was off, no aim was raised.
	assert_float(seen["blow"]).is_equal(1.0)
	assert_float(seen["chest"]).is_equal(0.0)
	assert_float(seen["raised"]).is_equal(0.0)
	# Both hands stayed on the rifle through the blow and its fades.
	(
		assert_float(seen["gap"])
		. override_failure_message("a hand was %.1f mm off its place" % (seen["gap"] * 1e3))
		. is_less(0.005)
	)
	# And after it the hold is the hold again.
	await InputSim.ticks(get_tree(), 30)
	assert_float(hold.blow_amount()).is_equal(0.0)
	assert_float(hold.chest_weight()).is_greater(0.99)


func test_both_hands_stay_on_the_rifle_through_every_frame_of_every_blow() -> void:
	for model in MODELS:
		var stage := RifleStage.make_rifle(_holder, model)
		var hand := stage.skeleton.find_bone(&"hand_r")
		for blow in BLOWS:
			var length := stage.clip(blow).length
			for frame in int(round(length * FPS)) + 1:
				var time := minf(frame / FPS, length)
				stage.pose_rifle(blow, time, 0.0, 0.0, -1.0, 0.0, 1.0)
				var keyed := (
					stage.skeleton.global_transform
					* HandPoseModifier.global_pose(stage.skeleton, hand)
				)
				await stage.settle()
				var tag := "%s %s at frame %d" % [model, blow, frame]
				for side: String in ["r", "l"]:
					var gap := stage.hand_gap(side)
					(
						assert_float(gap)
						. override_failure_message(
							"%s: hand_%s is %.1f mm from its place" % [tag, side, gap * 1e3]
						)
						. is_less(REACH)
					)
				if model == "female":
					# The rifle rides the clip's own right hand on the body it was keyed on.
					var off := stage.bone_origin(&"hand_r").distance_to(keyed.origin)
					(
						assert_float(off)
						. override_failure_message(
							"%s: hand_r is %.1f mm from the clip's" % [tag, off * 1e3]
						)
						. is_less(CLIP_HAND)
					)
		stage.free()

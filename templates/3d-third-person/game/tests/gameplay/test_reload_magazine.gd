# The magazines through the pistol reload (kit #1052): the pistol's own leaves the grip when the
# reload's first sound plays and falls to the floor (cosmetic, never sent); a new one is in the left
# hand from the belt, held by its fingers within the hold's limits, comes up the grip's own line
# and is the pistol's own again once it is in; a reload cut short leaves the pistol whole; the
# slide, locked back on an empty pistol, runs forward when the reload's last sound plays. On both
# mannequins posed by hand (`HoldStage`) and on the live player.
extends GdUnitTestSuite

const MODELS: Array[String] = ["female", "male"]
## The step the reload is walked in on the posed stage.
const STEP := 0.01
## The parts of the left hand that hold the new magazine while it is carried: none may be more
## than `HandContact.MAX_FLOAT` off it, none more than `HandContact.MAX_DEPTH` in it.
const CARRY_CONTACTS: Array[String] = ["middle_tip", "ring_tip", "pinky_tip", "palm"]
## How far off its line up the grip the new magazine may be, in metres, and turned, in degrees:
## the hand's arm reaches its place within half a millimetre.
const ON_LINE := 0.0015
const TURNED := 1.0
## How far the old magazine falls before it lies still, at least, in metres (the pistol is held
## at the chest, about 1.2 m above the floor).
const FALLS := 0.8

var _holder: Node3D


func before_test() -> void:
	InputSim.release_all()
	_holder = auto_free(Node3D.new())
	add_child(_holder)


func after_test() -> void:
	InputSim.release_all()


func test_the_new_magazine_rides_the_left_hand_up_the_grips_line() -> void:
	for model in MODELS:
		var stage := HoldStage.make(_holder, model)
		var hold := stage.hold as WeaponHold
		var gun_magazine := stage.pistol.get_node("Pistol/Magazine") as Node3D
		var rest := WeaponHold._in(gun_magazine, stage.pistol)
		var line := hold.magazine_approach.normalized()
		# The hand measured against the new magazine, and the new magazine against the pistol
		# without its own: each contact keeps the meshes shown when it is made.
		_pose_reload(stage, 0.0)
		await stage.settle()
		var held := hold.held_magazine()
		held.visible = true
		var on_magazine := HandContact.new(stage.skeleton)
		on_magazine.set_weapon(held.get_child(0) as Node3D)
		held.visible = false
		gun_magazine.visible = false
		var on_gun := HandContact.new(stage.skeleton)
		on_gun.set_weapon(stage.pistol)
		gun_magazine.visible = true
		stage.skeleton.skeleton_updated.connect(on_magazine.snapshot)
		var carried := 0
		var inserted := 0
		var share := 0.0
		while share <= 1.0 + 1e-6:
			_pose_reload(stage, share)
			await stage.settle()
			var tag := "%s reload at %.2f" % [model, share]
			var plan := hold.left_hand()
			assert_bool(gun_magazine.visible).override_failure_message(tag).is_equal(
				plan.magazine_in_gun
			)
			assert_bool(held.visible).override_failure_message(tag).is_equal(plan.magazine_in_hand)
			if held.visible:
				var mesh := held.get_child(0) as MeshInstance3D
				var place := stage.pistol.global_transform.affine_inverse() * mesh.global_transform
				var parts := on_magazine.measure("l")
				var contacts: Array[String] = []
				if plan.carry >= 1.0:
					contacts = CARRY_CONTACTS
					carried += 1
				var fails := HandContact.failures(tag + " on the magazine:", parts, contacts)
				assert_array(fails).override_failure_message("\n".join(fails)).is_empty()
				if share < hold.reload_insert.x:
					var deepest := _deepest(on_gun, mesh)
					(
						assert_float(deepest)
						. override_failure_message(
							"%s: the new magazine %.1f mm in the pistol" % [tag, deepest * 1e3]
						)
						. is_less_equal(HandContact.MAX_DEPTH)
					)
				else:
					inserted += 1
					var off := place.origin - rest.origin
					var aside := (off - line * off.dot(line)).length()
					(
						assert_float(aside)
						. override_failure_message(
							"%s: the magazine %.1f mm off the grip's line" % [tag, aside * 1e3]
						)
						. is_less(ON_LINE)
					)
					assert_float(off.dot(line)).override_failure_message(tag).is_greater_equal(
						-ON_LINE
					)
					var turn := rad_to_deg(
						place.basis.get_rotation_quaternion().angle_to(
							rest.basis.get_rotation_quaternion()
						)
					)
					(
						assert_float(turn)
						. override_failure_message(
							"%s: the magazine turned %.1f degrees off the grip" % [tag, turn]
						)
						. is_less(TURNED)
					)
			share += STEP
		assert_int(carried).override_failure_message("%s: never carried" % model).is_greater(5)
		assert_int(inserted).override_failure_message("%s: never went in" % model).is_greater(5)
		stage.skeleton.skeleton_updated.disconnect(on_magazine.snapshot)
		stage.free()


func test_the_player_drops_the_old_magazine_and_loads_a_new_one() -> void:
	var arena: PlayArena = auto_free(PlayArena.new())
	add_child(arena)
	var player := arena.add_player(Vector3.ZERO)
	await InputSim.ticks(get_tree(), 20)
	var hold := player.get_node("WeaponHold") as WeaponHold
	var gun_magazine := player.get_node("Model/PistolHeld/Pistol/Pistol/Magazine") as Node3D
	assert_object(hold.dropped_magazine()).is_null()
	player.weapon.set_ammo(3, 24)
	var started := gun_magazine.global_position
	InputSim.key(KEY_R, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_R, false)
	var hidden_at := -1.0
	var shown_again_at := -1.0
	var in_hand := 0
	for tick in roundi(player.weapon.definition.reload_time * 60.0) + 20:
		await InputSim.ticks(get_tree(), 1)
		var progress := player.weapon.reload_progress()
		if not gun_magazine.visible and hidden_at < 0.0:
			hidden_at = progress
		if gun_magazine.visible and hidden_at >= 0.0 and shown_again_at < 0.0:
			shown_again_at = hold.reload_share
		if hold.held_magazine().visible:
			in_hand += 1
	var first_sound: float = player.weapon.definition.reload_sound_at[0]
	(
		assert_float(hidden_at)
		. override_failure_message("the magazine left the grip at %.2f of the reload" % hidden_at)
		. is_between(first_sound - 0.03, first_sound + 0.05)
	)
	(
		assert_float(shown_again_at)
		. override_failure_message("the new magazine was in at %.2f of the clip" % shown_again_at)
		. is_between(hold.reload_insert.y - 0.02, hold.reload_insert.y + 0.04)
	)
	assert_int(in_hand).override_failure_message("never in the hand").is_greater(10)
	assert_bool(gun_magazine.visible).is_true()
	assert_bool(hold.held_magazine().visible).is_false()
	assert_int(player.weapon.ammo).is_equal(12)
	var dropped := hold.dropped_magazine()
	assert_object(dropped).is_not_null()
	await InputSim.ticks(get_tree(), 90)
	assert_bool(dropped.visible).is_true()
	(
		assert_float(started.y - dropped.global_position.y)
		. override_failure_message(
			"the old magazine fell %.2f m" % (started.y - dropped.global_position.y)
		)
		. is_greater(FALLS)
	)
	(
		assert_float(dropped.global_position.y)
		. override_failure_message("the old magazine went through the floor")
		. is_greater(-0.05)
	)
	assert_int(dropped.collision_layer).is_equal(0)
	await InputSim.ticks(get_tree(), roundi(hold.dropped_life * 60.0))
	assert_bool(dropped.visible).override_failure_message("the old magazine stayed").is_false()
	AudioDrain.stop_all(arena)


func test_a_reload_cut_short_leaves_the_pistol_whole() -> void:
	var arena: PlayArena = auto_free(PlayArena.new())
	add_child(arena)
	var player := arena.add_player(Vector3.ZERO)
	await InputSim.ticks(get_tree(), 20)
	var hold := player.get_node("WeaponHold") as WeaponHold
	var gun_magazine := player.get_node("Model/PistolHeld/Pistol/Pistol/Magazine") as Node3D
	player.weapon.set_ammo(3, 24)
	InputSim.key(KEY_R, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_R, false)
	# Into the carry: the old magazine gone, the new one in the hand.
	while player.weapon.reload_progress() < 0.35:
		await InputSim.ticks(get_tree(), 1)
	assert_bool(gun_magazine.visible).is_false()
	assert_bool(hold.held_magazine().visible).is_true()
	InputSim.key(KEY_H, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_H, false)
	await InputSim.ticks(get_tree(), 2)
	assert_bool(player.weapon.is_reloading()).is_false()
	(
		assert_bool(gun_magazine.visible)
		. override_failure_message("the pistol lost its magazine")
		. is_true()
	)
	assert_bool(hold.held_magazine().visible).is_false()
	assert_int(player.weapon.ammo).is_equal(3)
	AudioDrain.stop_all(arena)


func test_the_slide_stands_back_on_an_empty_pistol_until_the_reload_releases_it() -> void:
	var arena: PlayArena = auto_free(PlayArena.new())
	add_child(arena)
	var player := arena.add_player(Vector3.ZERO)
	await InputSim.ticks(get_tree(), 20)
	var hold := player.get_node("WeaponHold") as WeaponHold
	var slide := player.get_node("Model/PistolHeld/Pistol/Pistol/Slide") as Node3D
	var rest := slide.transform
	# Empty with nothing to reload: the slide stays back.
	player.weapon.set_ammo(0, 0)
	await InputSim.ticks(get_tree(), 2)
	assert_float(slide.transform.origin.distance_to(rest.origin)).is_equal_approx(
		hold.slide_travel, 0.0005
	)
	assert_float((slide.transform.origin - rest.origin).dot(rest.basis.x)).is_greater(0.0)
	player.weapon.set_ammo(0, 24)
	InputSim.key(KEY_R, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_R, false)
	var released_at := -1.0
	for tick in roundi(player.weapon.definition.reload_time * 60.0) + 20:
		await InputSim.ticks(get_tree(), 1)
		if released_at < 0.0 and slide.transform.origin.is_equal_approx(rest.origin):
			released_at = player.weapon.reload_progress()
	var last_sound: float = player.weapon.definition.reload_sound_at[-1]
	(
		assert_float(released_at)
		. override_failure_message("the slide ran forward at %.2f of the reload" % released_at)
		. is_between(last_sound - 0.03, last_sound + 0.05)
	)
	assert_bool(slide.transform.origin.is_equal_approx(rest.origin)).is_true()
	AudioDrain.stop_all(arena)


# The deepest any vertex of `mesh` is in the weapon `contact` measures, in metres (0 when none).
func _deepest(contact: HandContact, mesh: MeshInstance3D) -> float:
	var deepest := 0.0
	var faces := mesh.mesh.get_faces()
	for index in range(0, faces.size(), 3):
		deepest = maxf(deepest, -contact.weapon_distance(mesh.global_transform * faces[index]))
	return deepest


func _pose_reload(stage: HoldStage, share: float) -> void:
	var length := stage.clip(CharacterClips.PISTOL_RELOAD).length
	stage.pose(CharacterClips.PISTOL_RELOAD, share * length, 0.0, &"", [], share)

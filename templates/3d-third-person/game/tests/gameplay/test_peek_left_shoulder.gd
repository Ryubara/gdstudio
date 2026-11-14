# The weapon on the left for a left peek lean (gdstudio #1435): the template's weapons are
# right-handed, and leaning left the muzzle stayed right of the head, so a left peek needed a wall's
# edge closer than a right one and its shot could strike the edge it peeked past. Now a left lean
# takes the rifle to the left shoulder and the pistol across to the left eye: aimed ahead, the
# muzzle is as far out to the left as a right lean has it to the right, both hands stay on their
# places on the weapon all the way across, and from one spot behind a pillar a left lean and a
# right lean both hit a target past their edge (the server's bare body too, whose shot start is
# mirrored with the lean).
extends GdUnitTestSuite

const BODY := "res://gameplay/character/character.tscn"
const PLAYER := "res://gameplay/player/player.tscn"
const RIFLE := "res://gameplay/weapon/rifle.tres"
## How far apart a left lean's muzzle and a right lean's mirrored may be, sideways, metres.
const MIRROR_SLACK := 0.04
## How far a hand may be from its place on the weapon, metres (the hold's own 5 mm off).
const HAND_GAP := 0.005
## The most the muzzle may point off the aim, degrees.
const MISS := 3.0
## The pillar's middle, in front of the body at the origin facing -Z, and its depth.
const PILLAR_Z := -2.5
const PILLAR_DEPTH := 0.3
## The pillar's width for each weapon: wide enough that a left lean's shot struck it before the
## left-shoulder hold (its muzzle 0.2 to 0.25 m short of the right lean's mirror), narrow enough
## that a right lean's shot clears its edge (measured: the pistol's shot passes the pillar's face
## 0.51 m out, the rifle's 0.44 m, the server body's pistol 0.5 m).
const PILLAR_WIDTH := {"pistol": 0.9, "rifle": 0.64, "server": 0.9}
## The targets past each edge: 1 m to the side, 8 m ahead.
const TARGET_X := 1.0
const TARGET_Y := 1.5
const TARGET_Z := -8.0

var _arena: PlayArena


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)


func after_test() -> void:
	InputSim.release_all()
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


# A body of `scene` at the origin facing -Z, stepped by hand (`_step`); the dressed player holds
# the rifle when `weapon` says so.
func _body(scene: String, weapon: String) -> Character:
	var body: Character
	if scene == PLAYER:
		body = _arena.add_player(Vector3.ZERO)
		body._present_facing()
		CommandDriver.take(body as Player)
	else:
		body = (load(scene) as PackedScene).instantiate() as Character
		_arena.add_child(body)
		body.facing = PI
		body.set_physics_process(false)
	await InputSim.ticks(get_tree(), 2)
	if weapon == "rifle":
		body.loadout.give(load(RIFLE) as WeaponDef, 60)
		await _step(body, PlayerCommand.new(), 60)
		assert_str(body.weapon.definition.display_name).is_equal("Rifle")
	return body


func _step(body: Character, command: PlayerCommand, count: int, plan := Callable()) -> void:
	var stepped := command.clone()
	for tick in count:
		await get_tree().physics_frame
		if plan.is_valid():
			plan.call(stepped)
		body.step(stepped, CommandDriver.tick_seconds())
		stepped.clear_edges()


func _command(side: int, aimed: bool) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.lean_left = side < 0
	command.lean_right = side > 0
	command.aim = aimed
	var ahead := CommandCodec.direction_angles(Vector3.FORWARD)
	command.yaw = ahead.x
	command.pitch = ahead.y
	return command


func _eye(body: Character) -> Vector3:
	return (body.get_node("CameraTarget") as Node3D).global_position


func _bone(body: Character, bone_name: StringName) -> Vector3:
	var skeleton := body.model.skeleton()
	var pose := skeleton.get_bone_global_pose(skeleton.find_bone(bone_name))
	return (skeleton.global_transform * pose).origin


# The muzzle's place, the aim's miss and each hand's distance from its place on the held weapon,
# on the skeleton's next update.
func _drawn(body: Character) -> Dictionary:
	var skeleton := body.model.skeleton()
	await skeleton.skeleton_updated
	var aim := (body.get_node("AimLayer") as AimLayer).modifier()
	var right_place: Vector3
	var left_place: Vector3
	if body.weapon.definition.display_name == "Rifle":
		var rifle := body.model.get_node("RifleHeld") as TwoHandHold
		right_place = (rifle.find_child("RightHandTarget", true, false) as Node3D).global_position
		left_place = (rifle.find_child("LeftHandTarget", true, false) as Node3D).global_position
	else:
		var seat := body.model.get_node("PistolHeld") as Node3D
		right_place = seat.global_position
		left_place = (seat.get_node("Pistol/SupportHand") as Node3D).global_position
	return {
		"muzzle": body.weapon.muzzle.global_position,
		"head": _bone(body, &"Head"),
		"miss": aim.miss,
		"right": _bone(body, &"hand_r").distance_to(right_place),
		"left": _bone(body, &"hand_l").distance_to(left_place),
	}


func test_aimed_ahead_the_left_lean_muzzle_mirrors_the_right(
	weapon: String, _test_parameters := [["pistol"], ["rifle"]]
) -> void:
	var body := await _body(PLAYER, weapon)
	var sides := {}
	for side: int in [1, -1]:
		await _step(body, _command(0, true), 30)
		await _step(body, _command(side, true), 30)
		sides[side] = await _drawn(body)
	prints("left shoulder", weapon, "right", sides[1], "left", sides[-1])
	var right: Dictionary = sides[1]
	var left: Dictionary = sides[-1]
	# Sideways from the body's middle, the left lean's muzzle where the right lean's is, mirrored.
	var off := absf(left.muzzle.x + right.muzzle.x)
	(
		assert_float(off)
		. override_failure_message(
			"%s: left muzzle %.3f m out, right %.3f m" % [weapon, -left.muzzle.x, right.muzzle.x]
		)
		. is_less(MIRROR_SLACK)
	)
	# Left of the head as the right lean's is right of it, or at least not behind it.
	assert_float(left.muzzle.x).is_less(left.head.x + MIRROR_SLACK)
	for drawn: Dictionary in [right, left]:
		assert_float(drawn.miss).is_less(MISS)
		assert_float(drawn.right).is_less(HAND_GAP)
		assert_float(drawn.left).is_less(HAND_GAP)


func test_the_hands_stay_on_the_weapon_all_the_way_across(
	weapon: String, _test_parameters := [["pistol"], ["rifle"]]
) -> void:
	var body := await _body(PLAYER, weapon)
	await _step(body, _command(0, true), 30)
	var worst := Vector3.ZERO
	# Over to the left at the lean's own pace, then back to the right through upright.
	for side: int in [-1, 1, 0]:
		for _tick in 16:
			await _step(body, _command(side, true), 1)
			var drawn := await _drawn(body)
			worst = Vector3(
				maxf(worst.x, drawn.right), maxf(worst.y, drawn.left), maxf(worst.z, drawn.miss)
			)
	prints("left shoulder across", weapon, "worst right, left, miss", worst)
	assert_float(worst.x).is_less(HAND_GAP)
	assert_float(worst.y).is_less(HAND_GAP)
	assert_float(worst.z).is_less(MISS)


func test_from_one_spot_both_leans_hit_past_their_edge(
	scene: String,
	weapon: String,
	_test_parameters := [[PLAYER, "pistol"], [PLAYER, "rifle"], [BODY, "server"]]
) -> void:
	var body := await _body(scene, weapon)
	var width: float = PILLAR_WIDTH[weapon]
	var pillar := _arena.add_block(Vector2(0.0, PILLAR_Z), Vector3(width, 3.0, PILLAR_DEPTH), 3.0)
	var pillar_health := Health.new()
	pillar_health.max_value = 100.0
	pillar.add_child(pillar_health)
	for side: int in [1, -1]:
		var target := Vector3(TARGET_X * side, TARGET_Y, TARGET_Z)
		var block := _arena.add_block(Vector2(target.x, target.z), Vector3.ONE * 0.6, 1.8)
		var health := Health.new()
		health.max_value = 100.0
		block.add_child(health)
		await get_tree().physics_frame
		await _fire(body, side, target)
		var tag := "%s lean %s" % [weapon, "right" if side > 0 else "left"]
		prints("left shoulder shot", tag, "from", body.weapon.last_origin)
		(
			assert_float(health.value)
			. override_failure_message(tag + ": the target was not hit")
			. is_less(100.0)
		)
		(
			assert_float(pillar_health.value)
			. override_failure_message(tag + ": the shot struck the edge")
			. is_equal(100.0)
		)
		block.queue_free()
		await _step(body, _command(0, false), 20)


# Leans to `side`, aims at `target` from the eye for half a second, then fires and waits for the
# round.
func _fire(body: Character, side: int, target: Vector3) -> void:
	var aim := _command(side, true)
	var look := func(command: PlayerCommand) -> void:
		var angles := CommandCodec.direction_angles(target - _eye(body))
		command.yaw = angles.x
		command.pitch = angles.y
	await _step(body, aim, 30, look)
	var fire := aim.clone()
	fire.fire = true
	fire.fire_pressed = true
	await _step(body, fire, 2, look)
	await _step(body, aim, 40, look)

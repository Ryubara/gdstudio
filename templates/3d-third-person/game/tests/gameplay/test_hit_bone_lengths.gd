# No limb is drawn as a rod when a body is hit (gdstudio #1338). A flinch hands a few limbs to
# their physical bodies while the clip goes on with the rest. Two things stretched them: every
# body not in the flinch stayed where the last flinch or death left it, and once kinematic Jolt
# carried it back over one tick, pulling the limb hanging from it at 50 to 70 m/s; and the clip
# moves the bones between two bodies that have none of their own (the clavicles, the neck), which
# the joints do not follow. Each case hits a body in one of the states a player meets it in
# (running, vaulting, crouched at cover, flinching, up again after a death), moves it, hits it
# again and kills it, while a probe last on the skeleton measures every bone's length against the
# rest's on every drawn frame and every tick reads the fastest flinching body, on both bodies.
extends GdUnitTestSuite

## The most a bone's length may differ from the rest's on any frame, metres: a death's joints
## give about a centimetre; a rod is tens of centimetres.
const LIMIT := 0.05
## The fastest a flinching body may move, m/s: a run, plus the shot's push; the pull was 50 to 70.
const FASTEST := 15.0
## Where the wall's near face is ahead of the body (along -Z), for the vault.
const FACE := 2.5

var _arena: PlayArena
var _body: Player
var _ragdoll: CharacterRagdoll
var _reaction: HitReaction
var _probe: BoneLengthProbe
var _players: Array[Player] = []
# What each part of a case did, in order: its label, the worst stretch and the fastest flinching
# body.
var _parts: Array[String] = []
var _over := false
var _fastest := 0.0
# The body the last shot pushed: a light hand takes the whole push and is fast on its own.
var _pushed: StringName = &""


func _make(model: String) -> void:
	InputSim.release_all()
	_arena = auto_free(ImpactShots.world(self))
	_body = _arena.add_player(Vector3.ZERO)
	_body.model.variant = load(CharacterBodies.BY_NAME[model]) as PackedScene
	CommandDriver.take(_body)
	_players = [_body]
	_parts = []
	_over = false
	_fastest = 0.0
	_ragdoll = _body.ragdoll_body
	_reaction = _body.get_node("HitReaction") as HitReaction
	await InputSim.ticks(get_tree(), 4)
	# The bones are made as the first flinch makes them in the game; the probe goes after them.
	_ragdoll.simulator()
	_probe = BoneLengthProbe.attach(_ragdoll.model.skeleton())


func after_test() -> void:
	InputSim.release_all()
	if is_instance_valid(_arena):
		AudioDrain.stop_all(_arena)


# A shot on `bone` from in front of the body (it faces -Z), as a projectile gives it; `kill`
# takes the health to zero with it.
func _hit(bone: StringName, kill := false) -> void:
	var skeleton := _ragdoll.model.skeleton()
	var pose := skeleton.get_bone_global_pose(skeleton.find_bone(bone))
	var at := skeleton.global_transform * pose.origin
	var health := Health.of(_body)
	health.value = 1.0 if kill else health.max_value
	_pushed = _reaction.body_for(bone)
	_body.take_hit(HitRecord.shot(10.0, &"", bone, at, Vector3.BACK, 40.0))


func _step(command: PlayerCommand, ticks: int, each_tick := Callable()) -> void:
	await CommandDriver.run(
		get_tree(),
		_players,
		command,
		ticks,
		func(tick: int) -> void:
			_watch()
			if each_tick.is_valid():
				each_tick.call(tick)
	)


# Once a tick: the fastest body a flinch holds, but for the one the shot pushed.
func _watch() -> void:
	if not _reaction.is_flinching():
		return
	for key in _reaction.flinch_bones():
		if key != _pushed:
			_fastest = maxf(_fastest, _ragdoll.body(key).linear_velocity.length())


# Ends a part of a case: keeps what it did and starts the measures again.
func _part(label: String) -> void:
	var worst := _probe.worst()
	_over = _over or worst >= LIMIT or _fastest >= FASTEST
	_parts.append(
		(
			"%s: stretch %.3f m %s, fastest flinch %.1f m/s"
			% [label, worst, _probe.first_over(LIMIT), _fastest]
		)
	)
	_probe.clear()
	_fastest = 0.0


func _assert_no_rod(label: String) -> void:
	(
		assert_bool(_over)
		. override_failure_message(
			(
				"%s: a bone stretched %.2f m or a flinching body moved %.0f m/s:\n%s"
				% [label, LIMIT, FASTEST, "\n".join(_parts)]
			)
		)
		. is_false()
	)


func _while_running(model: String) -> void:
	await _make(model)
	var run := CommandDriver.walking(Vector3.FORWARD)
	await _step(run, 30)
	_part("running")
	_hit(&"spine_03")
	await _step(run, 60)
	_part("chest flinch")
	_hit(&"upperarm_l")
	await _step(run, 60)
	_part("arm flinch 1 s on")
	_hit(&"thigh_r")
	await _step(run, 60)
	_part("leg flinch 1 s on")
	_hit(&"spine_03", true)
	await _step(run, 40)
	_part("death")
	_assert_no_rod("running, %s" % model)


func test_hits_while_running_stretch_no_bone_female() -> void:
	await _while_running("female")


func test_hits_while_running_stretch_no_bone_male() -> void:
	await _while_running("male")


func _while_vaulting(model: String) -> void:
	await _make(model)
	var wall := _arena.add_block(Vector2(0.0, -(FACE + 0.2)), Vector3(4.0, 0.9, 0.4), 0.9)
	wall.add_child(Vaultable.new())
	_hit(&"spine_03")
	var walk := CommandDriver.walking(Vector3.FORWARD)
	await _step(walk, 30)
	_part("chest flinch, walking")
	var press := walk.clone()
	press.jump = true
	press.jump_pressed = true
	var vaulted := [false]
	await _step(
		press,
		60,
		func(_tick: int) -> void:
			if _body.state == Character.State.VAULT and not vaulted[0]:
				vaulted[0] = true
				_hit(&"upperarm_r")
	)
	assert_bool(vaulted[0]).override_failure_message("the body never vaulted").is_true()
	_part("arm flinch in the vault")
	_hit(&"Head", true)
	await _step(walk, 40)
	_part("death")
	_assert_no_rod("vaulting, %s" % model)


func test_hits_while_vaulting_stretch_no_bone_female() -> void:
	await _while_vaulting("female")


func test_hits_while_vaulting_stretch_no_bone_male() -> void:
	await _while_vaulting("male")


func _at_cover(model: String) -> void:
	await _make(model)
	_arena.add_block(Vector2(0.0, -1.0), Vector3(3.0, 1.0, 0.5), 1.0)
	var crouch := PlayerCommand.new()
	crouch.crouch = true
	await _step(crouch, 40)
	_part("crouching")
	_hit(&"spine_03")
	await _step(crouch, 30)
	_part("chest flinch")
	# Along the cover, crouched, as a guard moving to its next peek.
	var along := CommandDriver.walking(Vector3.RIGHT)
	along.crouch = true
	await _step(along, 90)
	_part("along the cover")
	_hit(&"lowerarm_l")
	await _step(crouch, 30)
	_part("forearm flinch 1.5 m on")
	_hit(&"spine_03", true)
	await _step(crouch, 40)
	_part("death")
	_assert_no_rod("crouched at cover, %s" % model)


func test_hits_at_cover_stretch_no_bone_female() -> void:
	await _at_cover("female")


func test_hits_at_cover_stretch_no_bone_male() -> void:
	await _at_cover("male")


func _during_a_flinch(model: String) -> void:
	await _make(model)
	var walk := CommandDriver.walking(Vector3.LEFT)
	_hit(&"spine_03")
	await _step(walk, 6)
	_part("chest flinch")
	_hit(&"hand_r")
	await _step(walk, 6)
	_part("hand flinch in it")
	_hit(&"spine_03", true)
	await _step(walk, 40)
	_part("death in it")
	_assert_no_rod("hit during a flinch, %s" % model)


func test_hits_during_a_flinch_stretch_no_bone_female() -> void:
	await _during_a_flinch("female")


func test_hits_during_a_flinch_stretch_no_bone_male() -> void:
	await _during_a_flinch("male")


func _after_getting_up(model: String) -> void:
	await _make(model)
	var idle := PlayerCommand.new()
	_hit(&"spine_03", true)
	await _step(idle, 90)
	_part("death")
	_body.revive()
	await _step(idle, ceili(_ragdoll.get_up_time * Engine.physics_ticks_per_second) + 30)
	_part("getting up")
	_hit(&"spine_03")
	await _step(idle, 40)
	_part("chest flinch after getting up")
	_assert_no_rod("hit after getting up, %s" % model)


func test_a_hit_after_getting_up_stretches_no_bone_female() -> void:
	await _after_getting_up("female")


func test_a_hit_after_getting_up_stretches_no_bone_male() -> void:
	await _after_getting_up("male")

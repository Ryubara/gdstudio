# A vault seen on another screen (gdstudio #1222). A puppet never steps, so it never planned a
# crossing and never played its clip: it showed the capsule's path over the wall in its gait. Now
# the puppet whose drawn state turns to VAULT plans the same crossing from where it was drawn
# (`PuppetVault`), with nothing more sent, and plays the clip the stepping body plays. Ada vaults
# the course's 0.9 m wall in a game served over a loopback link; Bo's puppet of her is checked
# against the server's own plan. An AI replica (a dressed character with no collision of its own)
# plans from its drawn rows the same way.
extends GdUnitTestSuite

const LEVEL := "res://world/prototype/prototype_level.tscn"
const DRESSED := "res://gameplay/character/character_dressed.tscn"
## The course's 0.9 m wall (`test_vault_course.gd`), crossed eastwards.
const WALL := Vector3(-15.5, 0.45, -12.0)
const WALL_DEPTH := 0.4
const EAST := PI / 2.0
## How far the puppet's plan may start and land from the server's: the puppet plans from where it
## was drawn the frame before its state turned, which is at most a tick of the run away.
const MAX_PLAN_GAP := 0.12
## Seconds the puppet's crossing may be longer or shorter than the server's (its speed is read
## from where it was drawn).
const MAX_TIME_GAP := 0.08

var _rig: OnlineRig
var _ada: NetClient
var _bo: NetClient


func after_test() -> void:
	_rig = null
	_ada = null
	_bo = null


func test_a_puppet_plays_the_vault_clip_on_the_plan_the_server_ran() -> void:
	_rig = auto_free(OnlineRig.new(true))
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_ada = await _rig.join("Ada")
	_bo = await _rig.join("Bo")
	assert_object(_ada).is_not_null()
	assert_object(_bo).is_not_null()
	await _rig.wait(20)
	var west := WALL.x - WALL_DEPTH / 2.0
	_put(_ada, Vector3(west - 1.3, 0.0, WALL.z), EAST)
	_put(_bo, Vector3(WALL.x, 0.0, WALL.z + 5.0), PI)
	await _rig.wait(30)
	var puppet := _bo.remote_players.puppet_at(_ada.slot)
	assert_object(puppet).is_not_null()
	var server_plans: Array[VaultPlan] = []
	_rig.server_body(_ada).vault_motion.started.connect(
		func(plan: VaultPlan) -> void: server_plans.append(plan)
	)
	var puppet_plans: Array[VaultPlan] = []
	puppet.vault_motion.started.connect(func(plan: VaultPlan) -> void: puppet_plans.append(plan))
	var animation := puppet.get_node("Animation") as CharacterAnimation
	var clips: Array[StringName] = []
	animation.action_started.connect(func(clip: StringName) -> void: clips.append(clip))

	var run := PlayerCommand.new()
	run.set_from_world(Vector3.RIGHT)
	_rig.controllers[0].next = run
	var radius := _ada.player.tuning.radius
	for _frame in 120:
		await get_tree().physics_frame
		if _ada.player.global_position.x >= west - radius - 0.6:
			break
	var jump := PlayerCommand.new()
	jump.copy_from(run)
	jump.jump = true
	jump.jump_pressed = true
	_rig.controllers[0].next = jump
	var acting_frames := 0
	var vault_frames := 0
	for _frame in 90:
		await get_tree().physics_frame
		_rig.controllers[0].next.jump = false
		if puppet.state == Character.State.VAULT:
			vault_frames += 1
			acting_frames += 1 if animation.is_acting() else 0

	assert_int(server_plans.size()).is_equal(1)
	var served := server_plans[0]
	assert_int(served.kind).is_equal(VaultPlan.Kind.VAULT)
	assert_int(vault_frames).is_greater(5)
	(
		assert_int(puppet_plans.size())
		. override_failure_message("the puppet planned no vault")
		. is_equal(1)
	)
	var drawn := puppet_plans[0]
	assert_int(drawn.kind).is_equal(served.kind)
	assert_bool(drawn.high).is_equal(served.high)
	assert_float(absf(drawn.top - served.top)).is_less(0.01)
	assert_float(drawn.points[0].distance_to(served.points[0])).is_less(MAX_PLAN_GAP)
	assert_float(drawn.end_point().distance_to(served.end_point())).is_less(MAX_PLAN_GAP)
	assert_float(absf(drawn.duration - served.duration)).is_less(MAX_TIME_GAP)
	# The clip the stepping body plays for this crossing, over the whole body while it lasts.
	var clip := animation.traversal_clip(drawn)
	assert_array(clips).contains([clip])
	assert_int(acting_frames).is_greater_equal(vault_frames - 2)
	# Its time ran with the frames and the crossing ended with the drawn state.
	assert_bool(puppet.vault_motion.is_active()).is_false()
	assert_int(PuppetVault.of(puppet).found).is_equal(1)


func test_an_ai_replica_with_no_collision_plans_its_vault_from_its_rows() -> void:
	var level := auto_free(load(LEVEL).instantiate()) as Node3D
	add_child(level)
	var puppet := (load(DRESSED) as PackedScene).instantiate() as Character
	# As `AiReplica` makes one: nothing meets it and it meets nothing, and it never steps.
	puppet.collision_layer = 0
	puppet.collision_mask = 0
	level.add_child(puppet)
	puppet.set_physics_process(false)
	var plans: Array[VaultPlan] = []
	puppet.vault_motion.started.connect(func(plan: VaultPlan) -> void: plans.append(plan))
	var west := WALL.x - WALL_DEPTH / 2.0
	var tick := 1.0 / Engine.physics_ticks_per_second
	var speed := 4.0
	var spot := Vector3(west - 1.2, 0.0, WALL.z)
	puppet.facing = EAST
	puppet.state = Character.State.RUN
	# Walked to the wall a tick at a time, as its glide walks it between rows.
	while spot.x < west - puppet.tuning.radius - 0.4:
		spot.x += speed * tick
		_draw(puppet, spot, Vector3.RIGHT * speed, tick)
		await get_tree().physics_frame
	puppet.state = Character.State.VAULT
	_draw(puppet, spot + Vector3(speed * tick, 0.02, 0.0), Vector3.RIGHT * speed, tick)
	assert_int(plans.size()).is_equal(1)
	assert_int(plans[0].kind).is_equal(VaultPlan.Kind.VAULT)
	assert_float(plans[0].points[0].distance_to(spot)).is_less(0.001)
	assert_float(puppet.vault_motion.elapsed).is_equal_approx(tick, 0.0001)
	# The probe's mask was lent for the cast only.
	assert_int(puppet.collision_mask).is_equal(0)
	for _i in 10:
		_draw(puppet, puppet.global_position, Vector3.ZERO, tick)
	assert_float(puppet.vault_motion.elapsed).is_equal_approx(11.0 * tick, 0.0001)
	assert_int(plans.size()).is_equal(1)
	puppet.state = Character.State.IDLE
	_draw(puppet, puppet.global_position, Vector3.ZERO, tick)
	assert_bool(puppet.vault_motion.plan.is_valid()).is_false()


# As `AiReplica._place` draws a puppet: its place and velocity, then the vault.
func _draw(puppet: Character, spot: Vector3, moving: Vector3, delta: float) -> void:
	puppet.global_position = spot
	puppet.velocity = moving
	PuppetVault.follow(puppet, delta, PhysicsLayers.WORLD)


func _put(client: NetClient, spot: Vector3, heading: float) -> void:
	_rig.server_body(client).teleport(spot, heading)
	client.player.teleport(spot, heading)
	var stand := PlayerCommand.new()
	stand.yaw = heading - PI
	_rig.controllers[_rig.clients.find(client)].next = stand

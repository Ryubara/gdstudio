# The hitscan tracer (gdstudio #1270): `WeaponDef.tracer` is empty by default and a shot then
# draws nothing; with a `TracerDef` a hitscan shot draws one streak from the muzzle to where its ray
# hit (or to `hitscan_range`), from the level's capped `TracerPool`, making no node; a projectile
# shot and a server's weapon (`effects` off) draw none; the streak runs, fades and frees its place,
# the pool hiding itself; a puppet's cosmetic shot draws to what its ray meets and the server's HIT
# ends it there (`end_near`). Every export has its default pinned and the live ones show at once.
extends GdUnitTestSuite

const WEAPON := "res://gameplay/weapon/weapon.tscn"
const POOL := "res://gameplay/effects/tracer_pool.tscn"
const PISTOL_TRACER := "res://gameplay/weapon/pistol_tracer.tres"
## Where the wall stands in front of the muzzle (the muzzle at y = 1, the wall's face at z = -7.9).
const WALL_AT := Vector3(0.0, 1.0, -8.0)
const WALL_FACE := -7.9
const MUZZLE_AT := Vector3(0.0, 1.0, 0.0)

var _world: Node3D
var _weapon: Weapon
var _pool: TracerPool
var _look: TracerDef


func before_test() -> void:
	_world = auto_free(Node3D.new())
	add_child(_world)
	_pool = load(POOL).instantiate() as TracerPool
	_pool.compact = false
	_pool.warm_up_frames = 0
	_world.add_child(_pool)
	_weapon = load(WEAPON).instantiate() as Weapon
	_weapon.self_ticking = false
	_world.add_child(_weapon)
	var muzzle := Marker3D.new()
	muzzle.position = MUZZLE_AT
	_world.add_child(muzzle)
	_weapon.muzzle = muzzle
	_weapon.definition = _weapon.definition.duplicate()
	_weapon.definition.hitscan = true
	_look = (load(PISTOL_TRACER) as TracerDef).duplicate()
	await get_tree().physics_frame


func after_test() -> void:
	AudioDrain.stop_all(_world)


func _wall(at: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 4.0, 0.2)
	shape.shape = box
	wall.add_child(shape)
	wall.position = at
	_world.add_child(wall)
	return wall


func _shoot() -> void:
	_weapon.make_ready()
	assert_int(_weapon.pull()).is_equal(Weapon.Pull.FIRED)


func test_every_pool_and_tracer_export_has_its_default_pinned() -> void:
	var pool_pins := {
		&"enabled": true,
		&"max_tracers": 32,
		&"web_max_tracers": 16,
		&"warm_up_frames": 3,
	}
	var fresh := load(POOL).instantiate() as TracerPool
	assert_array(ExportPins.differences(fresh, pool_pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, pool_pins)).is_empty()
	fresh.free()
	var look_pins := {
		&"color": Color(1.0, 0.82, 0.48),
		&"energy": 2.5,
		&"width": 0.03,
		&"speed": 320.0,
		&"length": 3.0,
		&"fade_time": 0.1,
		&"start_offset": 0.1,
	}
	assert_array(ExportPins.differences(TracerDef.new(), look_pins)).is_empty()
	assert_array(ExportPins.wrong_values(TracerDef.new(), look_pins)).is_empty()
	# The ready-made pistol tracer is the defaults; no weapon holds it until a game sets it.
	assert_array(ExportPins.wrong_values(load(PISTOL_TRACER), look_pins)).is_empty()
	assert_object(WeaponDef.new().tracer).is_null()


func test_with_no_tracer_a_hitscan_shot_draws_nothing() -> void:
	_wall(WALL_AT)
	await get_tree().physics_frame
	_shoot()
	assert_int(_pool.active_count()).is_equal(0)
	assert_bool(_pool.visible).is_false()


func test_a_hitscan_shot_draws_one_streak_from_the_muzzle_to_the_hit() -> void:
	_wall(WALL_AT)
	await get_tree().physics_frame
	_weapon.definition.tracer = _look
	var drawn: Array[Array] = []
	_pool.tracer_drawn.connect(func(from: Vector3, to: Vector3) -> void: drawn.append([from, to]))
	var nodes_before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	_shoot()
	assert_int(drawn.size()).is_equal(1)
	assert_vector(drawn[0][0]).is_equal_approx(MUZZLE_AT, Vector3.ONE * 0.001)
	assert_float(drawn[0][1].z).is_equal_approx(WALL_FACE, 0.01)
	assert_int(_pool.active_count()).is_equal(1)
	assert_bool(_pool.visible).is_true()
	assert_int(_pool.shown_count()).is_equal(1)
	# A miss runs to the range.
	_weapon.definition.hitscan_range = 5.0
	_shoot()
	var line := _pool.line_at(1)
	assert_float(line[0].distance_to(line[1])).is_equal_approx(5.0, 0.001)
	# No node made for a shot, however many.
	for _shot in 50:
		_shoot()
	assert_float(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)).is_equal(nodes_before)
	assert_int(_pool.active_count()).is_equal(_pool.max_tracers)


func test_a_projectile_shot_and_a_server_weapon_draw_no_streak() -> void:
	_wall(WALL_AT)
	await get_tree().physics_frame
	_weapon.definition.tracer = _look
	_weapon.definition.hitscan = false
	_shoot()
	assert_int(_pool.active_count()).is_equal(0)
	_weapon.definition.hitscan = true
	_weapon.effects = false
	_shoot()
	assert_int(_pool.active_count()).is_equal(0)
	_weapon.effects = true
	_pool.enabled = false
	_shoot()
	assert_int(_pool.active_count()).is_equal(0)


func test_a_streak_runs_fades_and_frees_its_place() -> void:
	_wall(WALL_AT)
	await get_tree().physics_frame
	_weapon.definition.tracer = _look
	_shoot()
	var distance := MUZZLE_AT.distance_to(Vector3(0.0, 1.0, WALL_FACE))
	# It shows in the frame of the shot, leaving the muzzle at its full length, and runs at `speed`.
	assert_int(_pool.shown_count()).is_equal(1)
	_pool.advance(0.01)
	var head: Transform3D = _pool.shown(0)["transform"]
	var length := head.basis.y.length()
	assert_float(length).is_less_equal(_look.length + 0.001)
	assert_float(_pool.shown(0)["color"].a).is_equal(1.0)
	# Past its run it fades, then it is gone and the pool hides and stops.
	_pool.advance(_look.travel_time(distance))
	_pool.advance(_look.fade_time * 0.5)
	# Its last `length` metres stay at the wall while it fades (seen in every frame at 30 fps).
	assert_int(_pool.shown_count()).is_equal(1)
	var fading: Transform3D = _pool.shown(0)["transform"]
	assert_float(fading.basis.y.length()).is_equal_approx(_look.length, 0.01)
	assert_float((fading.origin + fading.basis.y * 0.5).z).is_equal_approx(WALL_FACE, 0.01)
	assert_float(_pool.shown(0)["color"].a).is_between(0.3, 0.7)
	_pool.advance(_look.fade_time)
	assert_int(_pool.active_count()).is_equal(0)
	assert_bool(_pool.visible).is_false()
	assert_bool(_pool.is_processing()).is_false()
	# With no speed the whole line shows at once.
	_look.speed = 0.0
	_shoot()
	_pool.advance(0.001)
	var whole: float = _pool.shown(0)["transform"].basis.y.length()
	assert_float(whole).is_equal_approx(distance - _look.start_offset, 0.01)


func test_the_live_numbers_show_in_the_next_shot() -> void:
	_wall(WALL_AT)
	await get_tree().physics_frame
	_weapon.definition.tracer = _look
	_look.width = 0.1
	_look.energy = 3.0
	_look.color = Color(0.2, 0.9, 1.0)
	_look.speed = 0.0
	_shoot()
	_pool.advance(0.001)
	var placed: Transform3D = _pool.shown(0)["transform"]
	assert_float(placed.basis.x.length()).is_equal_approx(0.1, 0.0001)
	assert_float(_pool.shown(0)["energy"]).is_equal_approx(3.0, 0.001)
	var tint: Color = _pool.shown(0)["color"]
	assert_float(tint.g).is_equal_approx(0.9, 0.01)
	# A smaller cap cuts the oldest at once.
	for _shot in 6:
		_shoot()
	_pool.max_tracers = 4
	assert_int(_pool.active_count()).is_equal(4)
	assert_int(_pool.multimesh.instance_count).is_equal(4)


func test_a_puppet_shot_draws_to_its_ray_and_the_hit_ends_it_there() -> void:
	_wall(WALL_AT)
	await get_tree().physics_frame
	_weapon.definition.tracer = _look
	_weapon.authoritative = false
	_weapon.fire_cosmetic(MUZZLE_AT, Vector3.FORWARD)
	assert_int(_pool.active_count()).is_equal(1)
	assert_float(_pool.line_at(0)[1].z).is_equal_approx(WALL_FACE, 0.01)
	# The server's HIT 3 m out (a body this screen draws elsewhere): the streak ends there.
	var hit := Vector3(0.1, 1.0, -3.0)
	assert_int(_pool.end_near(hit, ClientCombat.STOP_RADIUS)).is_equal(1)
	assert_vector(_pool.line_at(0)[1]).is_equal_approx(hit, Vector3.ONE * 0.001)
	# A HIT off the line, or behind the muzzle, ends nothing.
	assert_int(_pool.end_near(Vector3(3.0, 1.0, -3.0), ClientCombat.STOP_RADIUS)).is_equal(0)
	assert_int(_pool.end_near(Vector3(0.0, 1.0, 3.0), ClientCombat.STOP_RADIUS)).is_equal(0)


func test_the_pool_warms_its_program_and_then_hides() -> void:
	var fresh := load(POOL).instantiate() as TracerPool
	_world.add_child(fresh)
	assert_bool(fresh.visible).is_true()
	assert_int(fresh.shown_count()).is_equal(1)
	assert_float(fresh.shown(0)["color"].a).is_equal(0.0)
	for _frame in fresh.warm_up_frames + 1:
		await get_tree().process_frame
	assert_bool(fresh.visible).is_false()
	assert_bool(fresh.is_processing()).is_false()
	assert_object(TracerPool.find(_weapon)).is_not_null()

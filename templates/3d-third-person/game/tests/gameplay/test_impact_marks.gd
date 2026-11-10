# The look of a mark: its size, its turn about the normal (random, or upright), the seeded
# sequence, the surface's own material and scale, and the bodies that take no mark (a character,
# a ragdoll bone, which a shot meets).
extends GdUnitTestSuite

const FLAT := Vector3.ONE * 0.001

var _arena: PlayArena
var _impacts: Impacts
var _wall: StaticBody3D
var _hit: Array[Object] = []


func before_test() -> void:
	_hit.clear()
	_arena = auto_free(ImpactShots.world(self))
	_impacts = ImpactShots.impacts_of(_arena)
	_wall = _arena.add_block(Vector2(0.0, -5.0), Vector3(10.0, 4.0, 0.5), 4.0)
	await get_tree().physics_frame


func after_test() -> void:
	AudioDrain.stop_all(_arena)


func _on_impact(_surface: ImpactSurface, collider: Object, _at: Vector3, _normal: Vector3) -> void:
	_hit.append(collider)


func _shoot(from: Vector3, toward: Vector3) -> void:
	await ImpactShots.shoot(get_tree(), _arena, from, toward)


# A shot at the wall from the south, at height 1.5 and across `x`.
func _shoot_wall(x: float) -> void:
	await _shoot(Vector3(x, 1.5, 0.0), Vector3(x, 1.5, -10.0))


# A shot straight down onto the floor at `x`.
func _shoot_floor(x: float) -> void:
	await _shoot(Vector3(x, 3.0, 0.0), Vector3(x, 0.0, 0.0))


func test_a_mark_is_a_quad_of_the_marks_size_with_no_z_scale() -> void:
	_impacts.size_variation = 0.0
	_impacts.mark_size = 0.2
	await _shoot_wall(0.0)
	var mark := _impacts.marks()[0]
	assert_float(mark.global_basis.x.length()).is_equal_approx(0.2, 0.0005)
	assert_float(mark.global_basis.y.length()).is_equal_approx(0.2, 0.0005)
	assert_float(mark.global_basis.z.length()).is_equal_approx(1.0, 0.0005)


func test_random_rotation_turns_the_mark_about_its_normal_and_off_holds_it_upright() -> void:
	for step in 4:
		await _shoot_wall(-3.0 + step * 2.0)
	var distinct := {}
	for mark in _impacts.marks():
		distinct[snappedf(mark.global_basis.y.normalized().dot(Vector3.UP), 0.01)] = true
	assert_int(distinct.size()).is_greater(1)
	_impacts.clear_marks()
	_impacts.random_rotation = false
	await _shoot_wall(0.0)
	var upright := _impacts.marks()[0]
	assert_vector(upright.global_basis.y.normalized()).is_equal_approx(Vector3.UP, FLAT)


func test_the_same_seed_gives_the_same_marks() -> void:
	var runs: Array[Array] = []
	for _run in 2:
		_impacts.clear_marks()
		_impacts.random_seed = 7
		for step in 3:
			await _shoot_wall(-2.0 + step * 2.0)
		var run: Array[float] = []
		for mark in _impacts.marks():
			run.append(snappedf(mark.global_basis.x.length(), 0.0001))
			run.append(snappedf(mark.global_basis.get_euler().z, 0.0001))
		runs.append(run)
	assert_array(runs[0]).is_equal(runs[1])


func test_the_marks_material_is_the_surfaces_own_or_the_impacts() -> void:
	await _shoot_wall(0.0)
	assert_object(_impacts.marks()[0].material_override).is_same(_impacts.mark_material)
	var own := StandardMaterial3D.new()
	var surface: ImpactSurface = _impacts.surfaces_by_name()[&"default"]
	surface.mark_material = own
	await _shoot_wall(1.0)
	assert_object(_impacts.marks()[1].material_override).is_same(own)


func test_a_surfaces_mark_scale_multiplies_the_marks_size() -> void:
	_impacts.size_variation = 0.0
	_impacts.mark_size = 0.1
	var surface: ImpactSurface = _impacts.surfaces_by_name()[&"default"]
	surface.mark_scale = 2.0
	await _shoot_wall(0.0)
	assert_float(_impacts.marks()[0].global_basis.x.length()).is_equal_approx(0.2, 0.0005)


func test_a_character_body_takes_no_mark() -> void:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	body.add_child(shape)
	body.position = Vector3(-3.0, 1.0, -1.0)
	_arena.add_child(body)
	await get_tree().physics_frame
	await _shoot(Vector3(-3.0, 1.0, 3.0), Vector3(-3.0, 1.0, -1.0))
	assert_int(_impacts.mark_count()).is_equal(0)


func test_a_shot_meets_a_body_on_the_ragdoll_layer_and_marks_neither_it_nor_the_wall() -> void:
	# Shots list the Ragdoll layer (a dead body takes shots, #924): the shot stops at the bone, so
	# the wall behind it takes no mark, and a bone takes none of its own (#876 adds marks that stay
	# on a body as it gets up).
	var bone := PhysicalBone3D.new()
	bone.collision_layer = PhysicsLayers.RAGDOLL
	bone.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	bone.add_child(shape)
	bone.position = Vector3(0.0, 1.5, -2.0)
	_arena.add_child(bone)
	await get_tree().physics_frame
	_impacts.impact_made.connect(_on_impact)
	await _shoot_wall(0.0)
	assert_array(_hit).is_equal([bone])
	assert_int(_impacts.mark_count()).is_equal(0)

# The hit and interact components in the template (#925): a target and a character both take a
# real shot through their `Health`, a node with an `Interactable` and no script of its own is
# found and used by a character, a door or target with its component removed warns instead of
# failing silently, and nothing in `gameplay/` finds another part by a method name.
extends GdUnitTestSuite

const TARGET := "res://gameplay/target/target.tscn"
const DOOR := "res://gameplay/door/door.tscn"
const BODY := "res://gameplay/character/character.tscn"
## What a part must not use to find another: a method looked up or called by its name.
const NAME_LOOKUPS: Array[String] = ["has_method(", '.call(&"', '.call("', "call_group("]

var _arena: PlayArena


func before_test() -> void:
	_arena = auto_free(ImpactShots.world(self))
	await InputSim.ticks(get_tree(), 2)


func after_test() -> void:
	AudioDrain.stop_all(_arena)


func _board(at: Vector3) -> Target:
	var board := load(TARGET).instantiate() as Target
	board.position = at
	_arena.add_child(board)
	return board


func _body(at: Vector3) -> Character:
	var body := load(BODY).instantiate() as Character
	body.position = at
	_arena.add_child(body)
	body.facing = 0.0
	return body


func test_a_target_and_a_character_both_take_a_shot_through_their_health() -> void:
	var board := _board(Vector3(-2.0, 0.0, -4.0))
	var walker := HitRange.target(_arena, Vector3(2.0, 0.0, -4.0))
	await InputSim.ticks(get_tree(), 6)
	HitRange.freeze(walker)
	var board_hits: Array[HitRecord] = []
	Health.of(board).hit_taken.connect(func(hit: HitRecord) -> void: board_hits.append(hit))
	var walker_damage: Array[float] = []
	Health.of(walker).damaged.connect(
		func(amount: float, _hit: HitRecord) -> void: walker_damage.append(amount)
	)
	await ImpactShots.shoot(get_tree(), _arena, Vector3(-2.0, 1.0, 0.0), Vector3(-2.0, 1.0, -4.0))
	assert_int(board_hits.size()).is_equal(1)
	assert_float(board_hits[0].damage).is_equal(34.0)
	assert_bool(board.is_down()).is_true()
	var chest := HitRange.zones_of(walker).zone(&"chest")
	var line := HitRange.line_to(walker, chest)
	await HitRange.shoot(get_tree(), _arena, line[0], line[1])
	assert_array(walker_damage).is_equal([34.0])
	assert_float(walker.health).is_equal(66.0)


func test_a_target_with_no_health_warns_and_a_shot_leaves_it_standing() -> void:
	var board := _board(Vector3(0.0, 0.0, -4.0))
	assert_array(board._get_configuration_warnings()).is_empty()
	var health := Health.of(board)
	board.remove_child(health)
	health.free()
	assert_array(board._get_configuration_warnings()).is_not_empty()
	await InputSim.ticks(get_tree(), 2)
	await ImpactShots.shoot(get_tree(), _arena, Vector3(0.0, 1.0, 0.0), Vector3(0.0, 1.0, -4.0))
	assert_bool(board.is_down()).is_false()


func test_a_character_with_no_health_warns_and_takes_nothing() -> void:
	var walker := _body(Vector3(0.0, 0.0, -4.0))
	assert_array(walker._get_configuration_warnings()).is_empty()
	var health := Health.of(walker)
	walker.remove_child(health)
	health.free()
	assert_array(walker._get_configuration_warnings()).is_not_empty()
	walker.take_hit(HitRecord.shot(500.0, &"head", &"Head", Vector3.INF, Vector3.ZERO, 0.0))
	assert_bool(walker.is_dead()).is_false()
	assert_float(walker.health).is_equal(0.0)


func test_a_node_with_an_interactable_and_no_script_is_found_and_used() -> void:
	var walker := _body(Vector3.ZERO)
	var lever := Node3D.new()
	lever.name = "Lever"
	lever.position = Vector3(0.0, 0.0, 1.0)
	_arena.add_child(lever)
	var usable := Interactable.new()
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	usable.add_child(shape)
	lever.add_child(usable)
	var users: Array[Node3D] = []
	usable.interacted.connect(func(by: Node3D) -> void: users.append(by))
	var told: Array[Node3D] = []
	walker.interacted.connect(func(target: Node3D) -> void: told.append(target))
	await InputSim.ticks(get_tree(), 3)
	assert_object(walker.interact()).is_same(lever)
	assert_array(users).is_equal([walker])
	assert_array(told).is_equal([lever])
	# Switched off, it is passed over.
	usable.enabled = false
	await InputSim.ticks(get_tree(), 40)
	assert_object(walker.interact()).is_null()


func test_a_door_with_no_interactable_warns_and_cannot_be_used() -> void:
	var walker := _body(Vector3.ZERO)
	var door := load(DOOR).instantiate() as Door
	door.position = Vector3(0.0, 0.0, 1.2)
	_arena.add_child(door)
	await InputSim.ticks(get_tree(), 3)
	assert_array(door._get_configuration_warnings()).is_empty()
	assert_object(walker.interact()).is_same(door)
	var usable := door.get_node("Interactable")
	door.remove_child(usable)
	usable.free()
	assert_array(door._get_configuration_warnings()).is_not_empty()
	await InputSim.ticks(get_tree(), 40)
	assert_object(walker.interact()).is_null()


func test_no_part_in_gameplay_finds_another_by_a_method_name() -> void:
	var found: Array[String] = []
	for path in _scripts_under("res://gameplay"):
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for index in lines.size():
			var line := lines[index].strip_edges()
			if line.begins_with("#"):
				continue
			for lookup in NAME_LOOKUPS:
				if line.contains(lookup):
					found.append("%s:%d %s" % [path, index + 1, line])
	assert_array(found).is_empty()


func _scripts_under(folder: String) -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".gd"):
			found.append(folder.path_join(file))
	for sub in DirAccess.get_directories_at(folder):
		found.append_array(_scripts_under(folder.path_join(sub)))
	return found

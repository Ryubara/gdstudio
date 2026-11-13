# On the clock: a ruler is fixed work timed on the wall clock, the divisor of a cost gate.
class_name HeapRuler
extends RefCounted
## Fixed work spread over the heap, timed beside a cost gate's measured frames (kit
## docs/engines/godot/performance-budgets.md#reading-a-timing-on-a-shared-machine): many small
## objects made when the ruler is made, each with its own array and dictionary, visited in a
## shuffled order, and a walk through a large table in a seeded random order. A frame of game work
## reads objects all over memory, which a tight loop of script does not, so a process whose memory
## is slower (a busy neighbour on the runner, a heap spread thin after hours of suites) slows the
## frame and these and not the loop.

## Objects made, and visited a timing.
const OBJECTS := 6000
## Entries of the walked table (4 bytes each: 16 MB, past a runner's caches), and steps a timing.
const TABLE := 1 << 22
const STEPS := 40000

var _objects: Array[Item] = []
var _table := PackedInt32Array()
var _at := 0


func _init(seed_value: int = 1451) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	for index in OBJECTS:
		_objects.append(Item.new(index))
	for index in range(OBJECTS - 1, 0, -1):
		var other := random.randi_range(0, index)
		var held := _objects[index]
		_objects[index] = _objects[other]
		_objects[other] = held
	# One cycle through every entry (Sattolo's shuffle), so a walk never falls into a short loop.
	_table.resize(TABLE)
	for index in TABLE:
		_table[index] = index
	for index in range(TABLE - 1, 0, -1):
		var other := random.randi_range(0, index - 1)
		var held := _table[index]
		_table[index] = _table[other]
		_table[other] = held


## Milliseconds the objects' visit takes now.
func objects_ms() -> float:
	var start := Time.get_ticks_usec()
	for item in _objects:
		item.visit()
	return (Time.get_ticks_usec() - start) / 1000.0


## Milliseconds the table's walk takes now.
func walk_ms() -> float:
	var start := Time.get_ticks_usec()
	var at := _at
	for _step in STEPS:
		at = _table[at]
	_at = at
	return (Time.get_ticks_usec() - start) / 1000.0


## A small object of the kind a frame reads: a position, a list and a table.
class Item:
	extends RefCounted

	var spot := Vector3.ZERO
	var values: Array[float] = [0.0, 1.0, 2.0, 3.0]
	var table: Dictionary[StringName, float] = {&"speed": 1.0, &"blend": 0.5}

	func _init(index: int) -> void:
		spot = Vector3(index, 0.0, -index)

	func visit() -> void:
		spot += Vector3(values[1], 0.0, table[&"blend"]) * 0.001
		values[0] = spot.length()
		table[&"speed"] = values[0]

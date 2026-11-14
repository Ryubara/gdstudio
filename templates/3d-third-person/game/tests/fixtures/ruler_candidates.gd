# On the clock: rulers on trial beside a cost gate's `PhysicsRuler`, printed, never judged.
class_name RulerCandidates
extends Node3D
## Candidate divisors for the AI cost gate (kit #1534), timed right after `PhysicsRuler` at the
## same moments of the measured window, so a soak can tell which one follows the step when a
## runner's neighbours slow it while the physics ruler holds still (kit docs
## third-person/ai-characters.md#cost-gate). Each reads what the physics ruler does not:
## - `chase_2mb_ms`, `chase_16mb_ms`: a pointer chase through a random cycle of 2 MB and 16 MB
##   (each read waits on the last), so a cache the neighbours share or the memory's latency shows;
## - `crowd_physics_ms`: `CROWD` capsules in a ring on a floor of their own, each moved once a
##   round with a ray, the physics server's work spread over many bodies as an AI step's is.
## Add it to the tree before timing (building the cycles takes about a second); free it with the
## arena.

## Steps of a chase a timing.
const CHASE_STEPS := 120000
## Entries (32-bit) of the two cycles: 2 MB and 16 MB.
const SMALL_ENTRIES := 1 << 19
const LARGE_ENTRIES := 1 << 22
## Capsules of the crowd ruler and its rounds a timing.
const CROWD := 64
const CROWD_ROUNDS := 6
## Where the crowd ruler stands, metres, far off every arena and off `PhysicsRuler`'s floor.
const SPOT := Vector3(-400.0, 0.0, 400.0)
## A fixed seed: the cycles are the same in every process.
const SEED := 1534

var _small := PackedInt32Array()
var _large := PackedInt32Array()
var _bodies: Array[CharacterBody3D] = []


func _ready() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = SEED
	_small = _cycle(SMALL_ENTRIES, random)
	_large = _cycle(LARGE_ENTRIES, random)
	_add_box(SPOT + Vector3(0.0, -0.5, 0.0), Vector3(60.0, 1.0, 60.0))
	for index in CROWD:
		var body := CharacterBody3D.new()
		var capsule := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = 0.3
		shape.height = 1.8
		capsule.shape = shape
		capsule.position.y = 0.9
		body.add_child(capsule)
		body.position = _home(index)
		add_child(body)
		_bodies.append(body)


## Milliseconds each candidate takes now, by name.
func measure_ms() -> Dictionary[String, float]:
	return {
		"chase_2mb_ms": _chase_ms(_small),
		"chase_16mb_ms": _chase_ms(_large),
		"crowd_physics_ms": _crowd_ms(),
	}


func _chase_ms(table: PackedInt32Array) -> float:
	var at := 0
	var start := Time.get_ticks_usec()
	for _step in CHASE_STEPS:
		at = table[at]
	return (Time.get_ticks_usec() - start + at * 0) / 1000.0


func _crowd_ms() -> float:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	var start := Time.get_ticks_usec()
	for round_index in CROWD_ROUNDS:
		for index in CROWD:
			var body := _bodies[index]
			var angle := TAU * (index + round_index) / 12.0
			body.velocity = Vector3(cos(angle), -1.0, sin(angle)) * 3.0
			body.move_and_slide()
			query.from = body.global_position + Vector3(0.0, 1.5, 0.0)
			query.to = _bodies[(index + 7) % CROWD].global_position + Vector3(0.0, 1.0, 0.0)
			query.exclude = [body.get_rid()]
			space.intersect_ray(query)
	var spent := (Time.get_ticks_usec() - start) / 1000.0
	for index in CROWD:
		_bodies[index].global_position = _home(index)
		_bodies[index].velocity = Vector3.ZERO
	return spent


## Where capsule `index` stands between timings: a ring, neighbours 1.2 m apart, so they meet.
func _home(index: int) -> Vector3:
	var radius := CROWD * 1.2 / TAU
	var angle := TAU * index / CROWD
	return SPOT + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


## A random single cycle through `entries` slots (Sattolo's shuffle), as next-slot indices.
static func _cycle(entries: int, random: RandomNumberGenerator) -> PackedInt32Array:
	var order := PackedInt32Array()
	order.resize(entries)
	for index in entries:
		order[index] = index
	for index in range(entries - 1, 0, -1):
		var other := random.randi_range(0, index - 1)
		var held := order[index]
		order[index] = order[other]
		order[other] = held
	var table := PackedInt32Array()
	table.resize(entries)
	for index in entries:
		table[order[index]] = order[(index + 1) % entries]
	return table


func _add_box(spot: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = spot
	add_child(body)

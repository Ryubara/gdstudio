class_name ImpactShots
extends RefCounted
## For a suite of the bullet impacts: a small world with a floor, an `Impacts` and real
## `Projectile`s fired through the physics step, so a mark is the one a shot makes.

const PROJECTILE := "res://gameplay/projectile/projectile.tscn"
const IMPACTS := "res://gameplay/impacts/impacts.tscn"


## A flat world (`PlayArena`) holding an `Impacts`; the floor's top is at y = 0.
static func world(parent: Node) -> PlayArena:
	var arena := PlayArena.new()
	parent.add_child(arena)
	arena.add_child(load(IMPACTS).instantiate())
	return arena


## The `Impacts` of a world made by `world()`.
static func impacts_of(arena: Node) -> Impacts:
	for child in arena.get_children():
		if child is Impacts:
			return child
	return null


## Fires a projectile from `from` toward `toward` (a point), at `speed` metres a second.
static func fire(arena: Node, from: Vector3, toward: Vector3, speed := 80.0) -> Projectile:
	var shot := load(PROJECTILE).instantiate() as Projectile
	arena.add_child(shot)
	shot.launch(from, (toward - from).normalized(), speed)
	return shot


## Waits until the projectile has landed (it is freed when it does), at most `max_ticks` ticks.
static func land(tree: SceneTree, shot: Projectile, max_ticks := 120) -> void:
	for _tick in max_ticks:
		if not is_instance_valid(shot) or shot.is_queued_for_deletion():
			return
		await tree.physics_frame


## Fires and waits: the shot has landed when this returns.
static func shoot(tree: SceneTree, arena: Node, from: Vector3, toward: Vector3) -> void:
	await land(tree, fire(arena, from, toward))

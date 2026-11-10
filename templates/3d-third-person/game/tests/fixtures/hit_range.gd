class_name HitRange
extends RefCounted
## For the suites of the hit zones: a flat world with an `Impacts` (`ImpactShots.world`), a
## target made from `character_dressed.tscn` (the body with its model, no input) and real
## `Projectile`s fired at its parts through the physics step.

const DRESSED := "res://gameplay/character/character_dressed.tscn"
## The directions a part is looked for from, in turn: the front, the sides, the back, from above.
const SIDES: Array[Vector3] = [
	Vector3(0.0, 0.0, 1.0),
	Vector3(1.0, 0.0, 0.0),
	Vector3(-1.0, 0.0, 0.0),
	Vector3(0.0, 0.0, -1.0),
	Vector3(0.0, 0.6, 1.0),
	Vector3(0.6, 0.4, 0.6),
	Vector3(-0.6, 0.4, 0.6),
]


## A character made from the dressed scene at `spot`, facing +Z (toward a shooter standing at
## +Z), added to `arena`.
static func target(arena: Node, spot := Vector3.ZERO) -> Character:
	var body := (load(DRESSED) as PackedScene).instantiate() as Character
	body.position = spot
	arena.add_child(body)
	body.facing = 0.0
	return body


## The character's `HitZones`.
static func zones_of(body: Character) -> HitZones:
	return body.get_node("HitZones") as HitZones


## Holds the pose still (the animation tree stops), so a part is where it was looked for.
static func freeze(body: Character) -> void:
	(body.get_node("AnimationTree") as AnimationTree).active = false


## A start 3 m out and a direction from which a shot meets `part` first, or empty when no side
## sees it first.
static func line_to(body: Character, part: HitZone) -> Array[Vector3]:
	var zones := zones_of(body)
	zones.follow_bones()
	var centre := part.global_position
	for side in SIDES:
		var from := centre + side.normalized() * 3.0
		var found := zones.find(from, centre)
		if not found.is_empty() and found.zone == part:
			return [from, (centre - from).normalized()]
	return []


## Fires a real projectile from `from` along `direction` and waits until it lands. The projectile
## carries the weapon's damage and impulse as `projectile.tscn` has them.
static func shoot(tree: SceneTree, arena: Node, from: Vector3, direction: Vector3) -> void:
	await ImpactShots.shoot(tree, arena, from, from + direction)

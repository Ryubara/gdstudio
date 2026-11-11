class_name BodyOverlap
extends RefCounted
## How deep a body stands inside the world where it is now: each of its enabled collision shapes is
## laid against the world with the body's mask (`collide_shape`), and the deepest contact pair's
## distance is the overlap. A predicting client asks it after moving its body by a part of a
## correction: a part that put the body deep inside a ledge would be pushed back out by the next
## step, so the rest is taken whole (`Reconciler.take_rest`, gdstudio #1119).
##
## Not the engine's motion test with the recovery counted as a collision: under Jolt its depth is
## what is left after the recovery's first pass (0.033 m for a capsule 0.25 m inside the dais),
## while the contact pairs give the depth itself (0.25 m).

## Metres inside the world past which a part counts as pushed back. A part of the wire's rounding
## is under 2 mm and a body resting on a floor stands at its safe margin, never this deep.
const PUSHED_BACK := 0.05
## Contact pairs read for each shape.
const MOST_CONTACTS := 8


## The deepest the body's shapes reach into a solid thing at its transform, metres (0: none).
static func depth(body: CollisionObject3D) -> float:
	var space := body.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = body.collision_mask
	query.exclude = [body.get_rid()]
	var deepest := 0.0
	for child in body.get_children():
		var shape := child as CollisionShape3D
		if shape == null or shape.disabled or shape.shape == null:
			continue
		query.shape = shape.shape
		query.transform = shape.global_transform
		var points := space.collide_shape(query, MOST_CONTACTS)
		for index in range(0, points.size() - 1, 2):
			deepest = maxf(deepest, points[index].distance_to(points[index + 1]))
	return deepest


## True when the body stands deeper than `PUSHED_BACK` inside the world.
static func pushed_back(body: CollisionObject3D) -> bool:
	return depth(body) > PUSHED_BACK

class_name AiChoice
extends RefCounted
## Utility scoring with a commitment bonus, used at exactly three choice points: which target,
## which cover or flank spot, which patrol marker next. Nothing else is scored (the research for
## #882, section 2): a choice is kept unless another beats it by more than `bonus`, so two equal
## options do not take turns (Deadnight's flank place re-picked every think).


## The index of the best of `scores` (higher is better), with `bonus` added to the score of the
## option whose id in `ids` is `kept` (the one chosen last time); -1 when there are none.
static func best(ids: Array, scores: PackedFloat32Array, kept: Variant, bonus: float) -> int:
	var winner := -1
	var top := -INF
	for index in scores.size():
		var value := scores[index]
		if kept != null and index < ids.size() and ids[index] == kept:
			value += bonus
		if value > top:
			top = value
			winner = index
	return winner


## The length of the walk from `from` to `to` on `map` (one path query, taken from `budget` when
## there is one), or the straight distance when the map has no answer or the budget is spent.
static func walk_cost(map: RID, from: Vector3, to: Vector3, budget: AiBudget = null) -> float:
	var straight := from.distance_to(to)
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return straight
	if budget != null and not budget.take_path():
		return straight
	var points := NavigationServer3D.map_get_path(map, from, to, true)
	if points.size() < 2:
		return INF
	var length := 0.0
	for index in range(1, points.size()):
		length += points[index - 1].distance_to(points[index])
	# A path that ends short of the goal is as far again from it.
	return length + points[points.size() - 1].distance_to(to) * 2.0

class_name ChargeBolt
extends RefCounted
## The bolt nodes a rifle's `ChargePull` moves (the gun's and its far level's), found under the
## `TwoHandHold`, and the place they stand at home (kit #1266). Cosmetic, never sent.

var _bolts: Array[Node3D] = []
var _rest := Transform3D.IDENTITY
var _has_rest := false


## Finds the bolt nodes at `paths` under `holder`; the first one's place the first time is home.
func find(holder: Node, paths: Array[NodePath]) -> void:
	_bolts.clear()
	for path in paths:
		var found := holder.get_node_or_null(path) as Node3D
		if found != null:
			_bolts.append(found)
	if not _has_rest and not _bolts.is_empty():
		_rest = _bolts[0].transform
		_has_rest = true


## Puts every bolt `pulled` (0 to 1, 0 home) of the pull's travel back.
func put(charge: ChargePull, pulled: float) -> void:
	for each in _bolts:
		var xf := _rest
		if charge != null:
			xf.origin += (
				(each.get_parent() as Node3D).transform.basis.inverse() * (charge.travel * pulled)
			)
		each.transform = xf

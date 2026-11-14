class_name ChargeBolt
extends RefCounted
## The bolt nodes a rifle's `ChargePull` moves (the gun's and its far level's), found under the
## `TwoHandHold`, the place they stand at home (kit #1266), and whether this reload pulls them
## (kit #1402): only a reload of an empty magazine ends with the pull, as only the pistol's ends
## with the slide's rack (`RackLayer`). Cosmetic, never sent: it reads the magazine the weapon
## already has.

## Whether a hold posed by hand (no character: `RifleStage`) pulls the handle in its reload.
var posed_pulls := true

var _bolts: Array[Node3D] = []
var _rest := Transform3D.IDENTITY
var _has_rest := false
# This reload lost its pull: the body lay down before the pull began.
var _dropped := false


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


## Whether `character`'s reload, at `progress` (below 0: none), ends with `charge`'s pull: the
## magazine was empty when it began (its rounds go in at the reload's end, so it still is), and
## the body did not lie down before the pull began (the prone reload has no pull, as it has no
## rack). A reload with rounds left goes straight back to the hand guard.
func pulls(character: Character, progress: float, charge: ChargePull) -> bool:
	if charge == null:
		return false
	if character == null:
		return posed_pulls
	if progress < 0.0:
		_dropped = false
		return false
	if progress < charge.leave.x and character.prone:
		_dropped = true
	var weapon := character.weapon
	return not _dropped and weapon != null and weapon.ammo is int and weapon.ammo == 0

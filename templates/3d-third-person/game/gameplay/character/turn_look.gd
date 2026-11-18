class_name TurnLook
extends RefCounted
## The drawn turn of a reversal or a pivot over a body that steers itself (gdstudio #1565). The
## turn clips are in place: their root's yaw is a curve of `locomotion.json` (`turn`), not a track.
## The body's facing answers the stick within a few ticks, so the clip's hips, swinging round over
## the planted foot, are drawn by turning the rig under the model by how far the clip has turned
## from where the body faced as it began, less how far the body has turned since: the drawn body
## turns as the clip does while the capsule already goes the new way. Out of a turn the difference
## dies away over `CharacterTuning.turn_look_settle`, so a turn cut by a new direction or an action
## never pops.
## Cosmetic: never sent, never stepped; nothing reads the rig's turn but the eye.

## Below this (radians) the rig is put back exactly and left alone.
const AT_REST := 0.0005

## How far the rig is turned from the model now, radians to the left.
var offset := 0.0

var _rig: Node3D
var _base := Transform3D.IDENTITY


## One frame: the rig turned `wanted` radians (from the clip that plays), or, with `wanted` NAN,
## eased back toward none over `delta` seconds, halving every `half_life` seconds.
func follow(rig: Node3D, wanted: float, delta: float, half_life: float) -> void:
	if not is_finite(wanted):
		if offset == 0.0:
			return
		offset *= pow(0.5, delta / maxf(half_life, 0.001))
		if absf(offset) < AT_REST:
			offset = 0.0
	else:
		offset = wanted
	_apply(rig)


## Puts the rig back at once (a new rig, a death, the tree built again).
func clear() -> void:
	offset = 0.0
	if is_instance_valid(_rig):
		_rig.transform = _base
	_rig = null


func _apply(rig: Node3D) -> void:
	if rig == null:
		return
	if rig != _rig:
		if is_instance_valid(_rig):
			_rig.transform = _base
		_rig = rig
		_base = rig.transform
	var turned := Transform3D(Basis(Vector3.UP, offset), Vector3.ZERO)
	rig.transform = turned * _base
